#!/usr/bin/env bash
# PreToolUse(Bash) guard — no direct NetSuite call, no credential exfiltration.
# Only ~/.claude/scripts/malt-netsuite.py may talk to NetSuite (SuiteQL only, read-only by
# construction AND by NetSuite's own parser). The TBA token is carried by a read-write role, so any
# bypass of the script is a potential write to production NetSuite.
set -uo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"
# fail closed: if the payload cannot be parsed, inspect the raw payload instead of allowing blindly
[[ -z "$CMD" ]] && CMD="$INPUT"

LOWER="$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')"

deny() { printf '%s\n' "BLOCKED by netsuite-write-guard: $1" >&2; exit 2; }

# The sanctioned wrapper is allowed through whatever else the command line mentions.
printf '%s' "$LOWER" | grep -q 'malt-netsuite.py' && exit 0

# 1. credential exfiltration — the keychain entries hold a read-write TBA token.
if printf '%s' "$LOWER" | grep -Eq 'security[[:space:]]+(find|delete|add)-generic-password.*malt-netsuite'; then
  deny "the NetSuite TBA token must not be read or altered outside malt-netsuite.py. To (re)create it, run 'malt-netsuite.py --setup <env>' and execute the printed command yourself."
fi

# 2. decrypting the NetSuite secrets by hand — `--setup <env> --from-config` does it in-process so
#    the plaintext never reaches stdout or a session log. Decrypting to the terminal would leak the
#    read-write prod token into the transcript.
if printf '%s' "$LOWER" | grep -Eq 'sops.*(-d|--decrypt|decrypt)' \
   && printf '%s' "$LOWER" | grep -Eq 'netsuite-connector|netsuite'; then
  deny "do not decrypt the NetSuite secrets to the terminal (the prod TBA token would land in the session log). Use 'malt-netsuite.py --setup <env> --from-config'."
fi

# 3. direct network call to a NetSuite host — only as an invoked client (start of line or after a
#    separator), so that `grep netsuite.com erp/` or a doc path stays allowed. Wrappers (sudo/env/…)
#    and leading VAR=value assignments are stripped first so they cannot mask the client.
NORM="$(printf '%s' "$LOWER" | perl -pe 's/(?:(?<=^)|(?<=[;&|(`]))\s*(?:(?:sudo|env|time|nohup|command|xargs|stdbuf|nice)\s+|[a-z_][a-z0-9_]*=[^\s]*\s+)+/ /g')"
CLIENTS='curl|wget|http|https|httpie|nc|ncat|telnet|openssl|python|python3|node|ruby|php|perl|java'
if printf '%s' "$LOWER" | grep -Eq '(suitetalk\.api\.netsuite\.com|restlets\.api\.netsuite\.com|\.netsuite\.com)'; then
  if printf '%s' "$NORM" | grep -Eq "(^|[;&|(\`]|\\\$\\()[[:space:]]*([a-z0-9_./-]*/)?($CLIENTS)([[:space:]]|$)"; then
    deny "use ~/.claude/scripts/malt-netsuite.py (SuiteQL, read-only) instead of calling NetSuite directly. The prod TBA role can write."
  fi
fi

exit 0
