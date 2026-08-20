#!/usr/bin/env python3
# Assertions sur les fonctions pures de malt-netsuite.py : signature OAuth 1.0a TBA, garde de
# statement, résolution d'URL. Miroir de NetsuiteSuiteQlAuthTest.kt (erp/netsuite-suiteql-lib) :
# si l'un des deux évolue, l'autre doit suivre. Aucun appel réseau, aucune credential.

import importlib.util
import re
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("ns", Path(__file__).resolve().parent.parent / "malt-netsuite.py")
ns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ns)

CREDS = {
    "accountId": "TESTACCOUNT", "consumerKey": "ckey", "consumerSecret": "csecret",
    "tokenId": "tid", "tokenSecret": "tsecret", "serviceUri": "https://example.suitetalk.api.netsuite.com",
}

failures = []


def ck(label, condition):
    print(("ok   — " if condition else "FAIL — ") + label)
    if not condition:
        failures.append(label)


def header(**overrides):
    return ns.build_authorization_header("GET", "https://e.com", {**CREDS, **overrides})


def sig(method="POST", params=None, consumer_secret="cs", token_secret="ts"):
    return ns.compute_signature(method, "https://e.com", {"oauth_nonce": "n", **(params or {})},
                                consumer_secret, token_secret)


print("--- OAuth 1.0a TBA : parité avec NetsuiteSuiteQlAuth.kt ---")
ck("header préfixé OAuth", header().startswith("OAuth "))
ck("realm porte l'accountId", 'realm="TESTACCOUNT"' in header())
ck("signature HMAC-SHA256", 'oauth_signature_method="HMAC-SHA256"' in header())
ck("version 1.0", 'oauth_version="1.0"' in header())
ck("tous les params oauth présents", all(
    f"{p}=" in header() for p in
    ("oauth_consumer_key", "oauth_nonce", "oauth_timestamp", "oauth_token", "oauth_signature")))
ck("nonce = 32 alphanum minuscules", bool(re.search(r'oauth_nonce="[a-z0-9]{32}"', header())))
ck("deux appels = deux nonces", re.search(r'oauth_nonce="([^"]+)"', header()).group(1)
   != re.search(r'oauth_nonce="([^"]+)"', header()).group(1))
ck("espace encodé %20, jamais +",
   'oauth_consumer_key="key%20with%20space"' in header(consumerKey="key with space")
   and "key+with+space" not in header(consumerKey="key with space"))
ck("astérisque encodé %2A", 'oauth_consumer_key="key%2Avalue"' in header(consumerKey="key*value"))
ck("tilde gardé littéral", 'oauth_consumer_key="key~value"' in header(consumerKey="key~value")
   and "key%7Evalue" not in header(consumerKey="key~value"))
ck("credentials différentes = signatures différentes",
   sig(consumer_secret="cs1") != sig(consumer_secret="cs2"))
ck("méthode différente = signature différente", sig(method="GET") != sig(method="POST"))
ck("méthode en minuscules acceptée", sig(method="post") == sig(method="POST"))

# BILL-2747 : sans le repliement des query params dans la base string, ces signatures seraient égales.
ck("query params repliés dans la signature", sig() != sig(params={"limit": "1000", "offset": "0"}))
ck("offsets différents = signatures différentes",
   sig(params={"limit": "1000", "offset": "0"}) != sig(params={"limit": "1000", "offset": "1000"}))
paged = ns.build_authorization_header("POST", "https://e.com", CREDS, {"limit": "1000", "offset": "0"})
ck("limit absent du header émis", "limit" not in paged)
ck("offset absent du header émis", "offset" not in paged)

# Vecteur figé : détecte toute dérive silencieuse de l'algorithme lors d'une refonte.
FROZEN = "AqJ/nUQ51uX6Gmnut4pnBCKXSniPcd0f6F/4/w/rsJk="
ck("vecteur de signature figé", ns.compute_signature(
    "POST", "https://example.suitetalk.api.netsuite.com/services/rest/query/v1/suiteql",
    {"oauth_consumer_key": "ckey", "oauth_nonce": "abc123", "oauth_signature_method": "HMAC-SHA256",
     "oauth_timestamp": "1700000000", "oauth_token": "tid", "oauth_version": "1.0",
     "limit": "1000", "offset": "0"}, "csecret", "tsecret") == FROZEN)

print("--- couche 1 : transport ---")
ck("URL SuiteQL correcte",
   ns.suiteql_url(CREDS) == "https://example.suitetalk.api.netsuite.com/services/rest/query/v1/suiteql")
ck("slash final toléré",
   ns.suiteql_url({"serviceUri": "https://e.com/"}) == "https://e.com/services/rest/query/v1/suiteql")
source = (Path(__file__).resolve().parent.parent / "malt-netsuite.py").read_text()
code = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
ck("aucune URL Record API construite", "record/v1" not in code)
ck("aucune méthode HTTP mutante construite",
   not re.search(r'method="(PATCH|PUT|DELETE)"', code) and 'method="POST"' in code)

print("--- couche 3 : garde de statement (fonction pure) ---")


def refused(query):
    try:
        ns.assert_read_only(query)
        return None
    except ns.NetsuiteCliError as error:
        return str(error)


for label, query, expected in [
    ("DELETE", "DELETE FROM transaction WHERE id = 1", "only SELECT and WITH"),
    ("UPDATE", "UPDATE transaction SET status = 'x'", "only SELECT and WITH"),
    ("INSERT", "INSERT INTO transaction VALUES (1)", "only SELECT and WITH"),
    ("DROP", "DROP TABLE transaction", "only SELECT and WITH"),
    ("TRUNCATE", "TRUNCATE TABLE transaction", "only SELECT and WITH"),
    ("CALL", "CALL some_proc()", "only SELECT and WITH"),
    ("SELECT INTO", "SELECT id INTO t2 FROM transaction", "forbidden keyword 'INTO'"),
    ("UPDATE en sous-requête", "SELECT id FROM (UPDATE t SET a = 1)", "forbidden keyword 'UPDATE'"),
    ("chaînage ;", "SELECT 1 FROM dual; SELECT 2 FROM dual", "statement chaining"),
    ("DML masqué par un commentaire bloc", "/* ok */ DELETE FROM transaction", "only SELECT and WITH"),
    # Le commentaire de ligne est neutralisé, donc le DROP qui le suit reste visible de la denylist
    # (c'est elle qui rejette, avant même la règle de chaînage).
    ("DML après commentaire de ligne", "SELECT id FROM t -- x\n; DROP TABLE t", "forbidden keyword 'DROP'"),
    ("requête vide", "   ", "empty query"),
]:
    ck(f"{label} rejeté", (refused(query) or "").find(expected) >= 0)

for label, query in [
    ("colonne lastmodifieddate", "SELECT lastmodifieddate FROM transaction"),
    ("littéral 'DELETED'", "SELECT id FROM transaction WHERE status = 'DELETED'"),
    ("littéral avec apostrophe échappée", "SELECT id FROM t WHERE memo = 'it''s a drop'"),
    ("WITH", "WITH x AS (SELECT 1 AS n FROM dual) SELECT n FROM x"),
    ("; final", "SELECT 1 FROM dual;"),
    ("colonne 'createdfrom'", "SELECT createdfrom FROM transaction"),
]:
    ck(f"{label} accepté", refused(query) is None)

print("--- rendu ---")
import io  # noqa: E402  (import tardif : uniquement nécessaire au rendu)

out = io.StringIO()
ns.render([{"a": 1, "b": None}, {"a": 2, "c": "x"}], 2, "table", out)
rendered = out.getvalue()
ck("colonnes de toutes les lignes présentes", all(c in rendered for c in ("a", "b", "c")))
ck("null rendu vide, pas 'None'", "None" not in rendered)
noisy = io.StringIO()
ns.render([{"links": [], "tranid": "FRIN-1"}], 1, "table", noisy)
ck("colonne 'links' (métadonnée NetSuite) écartée", "links" not in noisy.getvalue())
ck("colonnes utiles conservées malgré le filtrage", "tranid" in noisy.getvalue())
empty = io.StringIO()
ns.render([], 0, "table", empty)
ck("0 ligne annoncée explicitement", "(0 rows)" in empty.getvalue())
truncated = io.StringIO()
ns.render([{"a": 1}], 87, "table", truncated)
ck("total annoncé quand tronqué", "of 87" in truncated.getvalue())

print()
print("TOUS LES TESTS PASSENT" if not failures else f"ÉCHECS : {len(failures)}")
sys.exit(1 if failures else 0)
