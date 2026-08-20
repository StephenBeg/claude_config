#!/usr/bin/env python3
# malt-netsuite.py — READ-ONLY SuiteQL CLI for the Malt NetSuite accounts (prod + sandbox).
#
# HARD GUARANTEE: this script can never write. Three independent layers:
#   1. transport      only POST /services/rest/query/v1/suiteql is ever built. The REST Record API
#                     (the ONLY write path of the NetSuite REST API) is not implemented at all.
#   2. server-side    NetSuite's SuiteQL parser is read-only by design: it refuses DML/DDL outright.
#                     This is the non-bypassable layer — it does not depend on this script's logic.
#   3. statement      local allowlist (SELECT / WITH) + keyword denylist, as a second net that fails
#                     fast with a clear message instead of burning a round-trip.
#
# The TBA token is carried by a read-write NetSuite role, so layers 1+2 are what make writes
# impossible, not the role. Direct calls to NetSuite that bypass this script are blocked by the
# PreToolUse hook ~/.claude/scripts/netsuite-write-guard.sh.
#
# Usage:
#   malt-netsuite.py "SELECT id, tranid, status FROM transaction WHERE tranid = 'FRIN-123'"
#   malt-netsuite.py --env sandbox --json "SELECT ..."
#   echo "SELECT 1 FROM dual" | malt-netsuite.py
#   malt-netsuite.py --setup prod --from-config   # decrypt app-config -> keychain, no secret shown
#   malt-netsuite.py --setup prod                 # or print the command to run yourself
#
# Options: --env prod|sandbox (default prod) | --json | --csv | --limit N | --timeout S |
#          --setup ENV [--from-config]
#
# Credentials live in the macOS keychain, never on disk in clear text:
#   service = malt-netsuite-<env>, password = JSON with accountId/consumerKey/consumerSecret/
#   tokenId/tokenSecret/serviceUri. `--setup <env> --from-config` sources them from the app-config
#   SOPS secrets (prod under `netsuite.<key>`, sandbox under the `.sandbox` twin) and writes them
#   straight to the keychain, so the plaintext never reaches stdout or a session log.
#
# SuiteQL lowercases every column key in its response; the output keeps them as returned, without
# any invented re-casing.

import argparse
import base64
import csv
import getpass
import hashlib
import hmac
import json
import re
import subprocess
import sys
import time
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request
from secrets import choice

PAGE_SIZE = 1000
NONCE_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
CRED_FIELDS = ("accountId", "consumerKey", "consumerSecret", "tokenId", "tokenSecret", "serviceUri")

# Layer 3a — only read statements may even be attempted.
ALLOWED_START = re.compile(r"^\s*(select|with)\b", re.IGNORECASE)
# Layer 3b — anything that could mutate, escalate or chain, matched on word boundaries so that a
# column named `updated_at` or a literal 'DELETED' stays queryable.
DENIED_KEYWORDS = re.compile(
    r"\b(insert|update|delete|merge|upsert|create|drop|truncate|alter|grant|revoke|call|exec|"
    r"execute|commit|rollback|savepoint|lock|into)\b",
    re.IGNORECASE,
)


class NetsuiteCliError(Exception):
    """Any user-facing failure: bad query, missing credentials, NetSuite rejection."""


# --------------------------------------------------------------------------------------------
# OAuth 1.0a TBA — faithful port of NetsuiteSuiteQlAuth.kt (erp/netsuite-suiteql-lib).
# Keep the two in sync: the query-param folding below is BILL-2747.
# --------------------------------------------------------------------------------------------

def encode(value):
    """Percent-encoding per RFC 5849: space -> %20, * -> %2A, ~ kept literal."""
    return urllib.parse.quote(str(value), safe="~")


def build_authorization_header(method, url, creds, query_params=None):
    query_params = query_params or {}
    oauth_params = {
        "oauth_consumer_key": creds["consumerKey"],
        "oauth_nonce": "".join(choice(NONCE_CHARS) for _ in range(32)),
        "oauth_signature_method": "HMAC-SHA256",
        "oauth_timestamp": str(int(time.time())),
        "oauth_token": creds["tokenId"],
        "oauth_version": "1.0",
    }
    # Per RFC 5849, request query parameters (SuiteQL `limit`/`offset`) MUST be folded into the
    # signature base string alongside the oauth_* params, with `url` carrying no query string. They
    # are NOT emitted in the Authorization header. Signing them here (rather than appending them to
    # the signed URL) is what keeps the signed request in sync with the sent URI when a query string
    # is present (BILL-2747: a signed-vs-sent mismatch surfaced as INVALID_LOGIN_ATTEMPT).
    signature = compute_signature(
        method, url, {**oauth_params, **query_params}, creds["consumerSecret"], creds["tokenSecret"]
    )
    parts = (
        [f'realm="{creds["accountId"]}"']
        + [f'{k}="{encode(v)}"' for k, v in sorted(oauth_params.items())]
        + [f'oauth_signature="{encode(signature)}"']
    )
    return "OAuth " + ", ".join(parts)


def compute_signature(method, url, params, consumer_secret, token_secret):
    normalized = "&".join(f"{encode(k)}={encode(params[k])}" for k in sorted(params))
    base_string = "&".join([method.upper(), encode(url), encode(normalized)])
    signing_key = f"{encode(consumer_secret)}&{encode(token_secret)}"
    digest = hmac.new(signing_key.encode(), base_string.encode(), hashlib.sha256).digest()
    return base64.b64encode(digest).decode()


# --------------------------------------------------------------------------------------------
# Credentials
# --------------------------------------------------------------------------------------------

def keychain_service(env):
    return f"malt-netsuite-{env}"


def load_credentials(env):
    service = keychain_service(env)
    try:
        raw = subprocess.run(
            ["security", "find-generic-password", "-s", service, "-w"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        raise NetsuiteCliError(
            f"no credentials for env '{env}' (keychain service '{service}').\n"
            f"Run: malt-netsuite.py --setup {env}"
        )
    try:
        creds = json.loads(raw)
    except json.JSONDecodeError:
        raise NetsuiteCliError(f"keychain entry '{service}' is not valid JSON. Re-create it: --setup {env}")
    missing = [f for f in CRED_FIELDS if not creds.get(f)]
    if missing:
        raise NetsuiteCliError(f"keychain entry '{service}' is missing: {', '.join(missing)}")
    return creds


APP_CONFIG_SECRETS = (
    "helm/spring-apps-template/configurations/netsuite-connector/spring-secrets.production.enc.yaml"
)
# Both environments live in the same SOPS file: prod under `netsuite.<key>`, sandbox under the
# `.sandbox`-suffixed twin. One source, one decryption, no application-local.yml dependency.
CONFIG_KEYS = {
    "accountId": "account-id", "consumerKey": "consumer-key", "consumerSecret": "consumer-secret",
    "tokenId": "token-id", "tokenSecret": "token-secret", "serviceUri": "service-uri",
}


def app_config_root():
    import os
    return Path(os.environ.get("MALT_APP_CONFIG", Path.home() / "Documents/projects/app-config"))


def decrypt_app_config():
    """Return the decrypted `appSecrets` mapping. The plaintext never leaves this process."""
    secrets_file = app_config_root() / APP_CONFIG_SECRETS
    if not secrets_file.is_file():
        raise NetsuiteCliError(
            f"app-config secrets not found at {secrets_file}.\n"
            "Set MALT_APP_CONFIG to your app-config checkout."
        )
    try:
        plain = subprocess.run(
            ["sops", "-d", str(secrets_file)], capture_output=True, text=True, check=True
        ).stdout
    except FileNotFoundError:
        raise NetsuiteCliError("sops is not installed (brew install sops).")
    except subprocess.CalledProcessError as error:
        raise NetsuiteCliError(
            "sops could not decrypt the app-config secrets (GCP KMS access?):\n"
            + error.stderr.strip()
        )
    # Minimal parse of the flat `appSecrets` block: `    <key>: <value>`, quotes optional. A full YAML
    # parser is not worth a dependency here, and the file shape is fixed by app-config's generator.
    entries = {}
    for line in plain.splitlines():
        match = re.match(r"^\s+([A-Za-z0-9._-]+):\s*(.*)$", line)
        if match:
            entries[match.group(1)] = match.group(2).strip().strip('"').strip("'")
    return entries


def store_credentials(env):
    """Decrypt app-config and write the keychain entry. No secret is ever printed or logged."""
    entries = decrypt_app_config()
    suffix = ".sandbox" if env == "sandbox" else ""
    creds = {}
    missing = []
    for field, key in CONFIG_KEYS.items():
        value = entries.get(f"netsuite.{key}{suffix}")
        if value:
            creds[field] = value
        else:
            missing.append(f"netsuite.{key}{suffix}")
    if missing:
        raise NetsuiteCliError(f"app-config is missing: {', '.join(missing)}")
    service = keychain_service(env)
    try:
        subprocess.run(
            ["security", "add-generic-password", "-U", "-s", service, "-a", getpass.getuser(),
             "-w", json.dumps(creds, separators=(",", ":"))],
            capture_output=True, text=True, check=True,
        )
    except subprocess.CalledProcessError as error:
        raise NetsuiteCliError(f"could not write the keychain entry '{service}': {error.stderr.strip()}")
    return (
        f"stored {len(creds)} fields in keychain '{service}' "
        f"(accountId={creds['accountId']}, serviceUri={creds['serviceUri']}).\n"
        f"Check it with: malt-netsuite.py --env {env} \"SELECT 1 AS ok FROM dual\""
    )


def setup_instructions(env):
    """Print the command for the user to run; never run it, so the secret stays out of any log."""
    sample = {f: f"<{f}>" for f in CRED_FIELDS}
    if env == "sandbox":
        sample["accountId"] = "5025154_SB1"
        sample["serviceUri"] = "https://5025154-sb1.suitetalk.api.netsuite.com"
    payload = json.dumps(sample, separators=(",", ":"))
    return (
        f"Store the {env} TBA credentials in the keychain by running this yourself:\n\n"
        f"  security add-generic-password -U -s {keychain_service(env)} -a \"$USER\" -w '{payload}'\n\n"
        "Fill each <field> from 1Password first. serviceUri has no trailing slash and no /services path.\n"
        "Sandbox values are also readable from erp/netsuite-connector/src/main/resources/application-local.yml."
    )


# --------------------------------------------------------------------------------------------
# Layer 3 — statement guard
# --------------------------------------------------------------------------------------------

def strip_literals_and_comments(query):
    """Blank out string literals and comments so the guard cannot be fooled by, nor trip on, their content."""
    without_block = re.sub(r"/\*.*?\*/", " ", query, flags=re.DOTALL)
    without_line = re.sub(r"--[^\n]*", " ", without_block)
    return re.sub(r"'(?:[^']|'')*'", "''", without_line)


def assert_read_only(query):
    if not query.strip():
        raise NetsuiteCliError("empty query.")
    bare = strip_literals_and_comments(query)
    if not ALLOWED_START.match(bare):
        raise NetsuiteCliError("only SELECT and WITH queries are allowed (malt-netsuite is read-only).")
    denied = DENIED_KEYWORDS.search(bare)
    if denied:
        raise NetsuiteCliError(
            f"forbidden keyword '{denied.group(0).upper()}' (malt-netsuite is read-only). "
            "NetSuite's SuiteQL endpoint would refuse it anyway."
        )
    if ";" in bare.rstrip().rstrip(";"):
        raise NetsuiteCliError("statement chaining with ';' is not allowed; send a single query.")


# --------------------------------------------------------------------------------------------
# SuiteQL transport — the only request this script can build
# --------------------------------------------------------------------------------------------

def suiteql_url(creds):
    return f"{creds['serviceUri'].rstrip('/')}/services/rest/query/v1/suiteql"


def fetch_page(creds, query, offset, page_size, timeout):
    url = suiteql_url(creds)
    query_params = {"offset": str(offset), "limit": str(page_size)}
    # Single source of truth for the query string: the pagination params are folded into the OAuth
    # signature (over the query-less base URL) and appended to the sent URI, so the signed request
    # matches the wire request even with a query string (BILL-2747).
    sent_uri = url + "?" + "&".join(f"{k}={v}" for k, v in query_params.items())
    body = json.dumps({"q": query}).encode()

    # TBA reads occasionally come back as a transient 401 INVALID_LOGIN_ATTEMPT (NetSuite-side
    # throttling of concurrent token use); one bounded retry with a fresh nonce and timestamp
    # recovers instead of surfacing it as an error (BILL-2830).
    last_error = None
    for attempt in (1, 2):
        request = urllib.request.Request(sent_uri, data=body, method="POST")
        request.add_header("Authorization", build_authorization_header("POST", url, creds, query_params))
        request.add_header("Content-Type", "application/json")
        # NetSuite requires `Prefer: transient` on every SuiteQL REST query; without it the API
        # rejects the call with 400 "The required request header Prefer is missing" (BILL-2827). The
        # value must be exactly `transient`, not the HTTP-standard `return=transient`.
        request.add_header("Prefer", "transient")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")
            last_error = NetsuiteCliError(f"NetSuite rejected the query [{error.code}]: {detail}")
            if error.code != 401 or attempt == 2:
                raise last_error
            print(f"malt-netsuite: 401 on attempt {attempt}/2, retrying with a fresh nonce", file=sys.stderr)
        except urllib.error.URLError as error:
            raise NetsuiteCliError(f"cannot reach NetSuite: {error.reason}")
    raise last_error


def run_query(creds, query, max_rows, timeout):
    rows = []
    offset = 0
    while True:
        page_size = PAGE_SIZE if max_rows is None else min(PAGE_SIZE, max_rows - len(rows))
        page = fetch_page(creds, query, offset, page_size, timeout)
        rows.extend(page.get("items", []))
        total = page.get("totalResults", len(rows))
        if max_rows is not None and len(rows) >= max_rows:
            return rows[:max_rows], total
        if len(rows) >= total or not page.get("items"):
            return rows, total
        offset += page_size


# --------------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------------

def columns_of(rows):
    # `links` is NetSuite's HATEOAS metadata, present (and empty) on every SuiteQL row. It is noise
    # in every single output, so it is dropped unless the query explicitly asked for it.
    seen = []
    for row in rows:
        for key in row:
            if key not in seen and key != "links":
                seen.append(key)
    return seen


def render(rows, total, fmt, stream):
    if fmt == "json":
        json.dump(rows, stream, indent=2, ensure_ascii=False, default=str)
        stream.write("\n")
        return
    if not rows:
        stream.write("(0 rows)\n")
        return
    cols = columns_of(rows)
    if fmt == "csv":
        writer = csv.DictWriter(stream, fieldnames=cols, extrasaction="ignore")
        writer.writeheader()
        writer.writerows([{c: row.get(c, "") for c in cols} for row in rows])
        return
    cells = [[render_cell(row.get(c)) for c in cols] for row in rows]
    widths = [max(len(cols[i]), *(len(r[i]) for r in cells)) for i in range(len(cols))]
    stream.write(" | ".join(c.ljust(widths[i]) for i, c in enumerate(cols)) + "\n")
    stream.write("-+-".join("-" * w for w in widths) + "\n")
    for row in cells:
        stream.write(" | ".join(row[i].ljust(widths[i]) for i in range(len(cols))) + "\n")
    suffix = f" of {total}" if total > len(rows) else ""
    stream.write(f"({len(rows)} rows{suffix})\n")


def render_cell(value):
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


# --------------------------------------------------------------------------------------------

def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="malt-netsuite.py",
        description="Read-only SuiteQL CLI for the Malt NetSuite accounts.",
    )
    parser.add_argument("query", nargs="?", help="SuiteQL query; read from stdin when omitted")
    parser.add_argument("--env", choices=("prod", "sandbox"), default="prod")
    parser.add_argument("--json", dest="fmt", action="store_const", const="json")
    parser.add_argument("--csv", dest="fmt", action="store_const", const="csv")
    parser.add_argument("--limit", type=int, help="cap the number of rows returned")
    parser.add_argument("--timeout", type=float, default=60.0, help="per-request timeout in seconds")
    parser.add_argument("--setup", choices=("prod", "sandbox"), help="configure credentials for an env")
    parser.add_argument("--from-config", action="store_true",
                        help="with --setup: decrypt app-config via sops and write the keychain directly")
    parser.set_defaults(fmt="table")
    return parser.parse_args(argv)


def main(argv=None, stdin=None, stdout=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout

    if args.setup:
        if not args.from_config:
            stdout.write(setup_instructions(args.setup) + "\n")
            return 0
        try:
            stdout.write(store_credentials(args.setup) + "\n")
        except NetsuiteCliError as error:
            print(f"malt-netsuite: {error}", file=sys.stderr)
            return 1
        return 0
    if args.from_config:
        print("malt-netsuite: --from-config only applies to --setup.", file=sys.stderr)
        return 1

    query = args.query if args.query is not None else stdin.read()
    try:
        assert_read_only(query)
        if args.limit is not None and args.limit <= 0:
            raise NetsuiteCliError("--limit must be a positive integer.")
        creds = load_credentials(args.env)
        rows, total = run_query(creds, query.strip().rstrip(";"), args.limit, args.timeout)
    except NetsuiteCliError as error:
        print(f"malt-netsuite: {error}", file=sys.stderr)
        return 1
    render(rows, total, args.fmt, stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
