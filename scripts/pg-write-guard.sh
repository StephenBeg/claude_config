#!/usr/bin/env bash
# PreToolUse(Bash) guard — no direct DB client, no write-access escalation.
# Only ~/.claude/scripts/malt-sql.sh may talk to the Cloud SQL tunnel (read-only by construction).
set -uo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)"
# fail closed: if the payload cannot be parsed, inspect the raw payload instead of allowing blindly
[[ -z "$CMD" ]] && CMD="$INPUT"

LOWER="$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')"

deny() { printf '%s\n' "BLOCKED by pg-write-guard: $1" >&2; exit 2; }

# 1. escalation to write privileges — never allowed, whatever the position in the command line
if printf '%s' "$LOWER" | grep -Eq 'pam +cloudsql-postgresql-write|set +role +readwrite|mongo-(prod|integ)-rw'; then
  deny "prod DB write access is forbidden for Claude, without exception. Give the user the command/SQL to run themselves."
fi

# 2. direct DB clients — only as an invoked command (start of line or after a separator),
#    so that `grep psql file.md` or a doc path stays allowed.
#    Wrappers (sudo/env/…) and leading VAR=value assignments are stripped first so they cannot mask the client.
NORM="$(printf '%s' "$LOWER" | perl -pe 's/(?:(?<=^)|(?<=[;&|(`]))\s*(?:(?:sudo|env|time|nohup|command|xargs|stdbuf|nice)\s+|[a-z_][a-z0-9_]*=[^\s]*\s+)+/ /g')"
CLIENTS='psql|pgcli|pg_dump|pg_restore|pgbench|mongo|mongosh|mongoimport|mongorestore|mongodump'
if printf '%s' "$NORM" | grep -Eq "(^|[;&|(\`]|\\\$\\()[[:space:]]*([a-z0-9_./-]*/)?($CLIENTS)([[:space:]]|$)"; then
  printf '%s' "$LOWER" | grep -q 'malt-sql.sh' && exit 0
  deny "use ~/.claude/scripts/malt-sql.sh (read-only guarded) instead of a direct DB client."
fi

exit 0
