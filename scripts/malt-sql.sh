#!/usr/bin/env bash
# malt-sql.sh — READ-ONLY guarded SQL CLI for Malt Cloud SQL (postgres) via cloudflared tunnel.
#
# HARD GUARANTEE: this script can never write. Three independent layers:
#   1. statement allowlist  (SELECT / WITH / EXPLAIN / SHOW / TABLE / VALUES only)
#   2. keyword denylist     (DML/DDL, SET ROLE, COPY..TO, FOR UPDATE, ...)
#   3. server-side session  default_transaction_read_only=on  (postgres itself refuses writes)
#
# Usage:
#   malt-sql.sh "SELECT 1"
#   malt-sql.sh --env integ "SELECT 1"
#   malt-sql.sh --db keycloak-operator --csv "SELECT ..."
#   echo "SELECT 1" | malt-sql.sh
#
# Options: --env prod|integ (default prod) | --db <name> (default malt) | --csv | --timeout <ms>
set -euo pipefail

GCLOUD_BIN="${GCLOUD_BIN:-/opt/homebrew/bin/gcloud}"
ENVIRONMENT=prod
DB=malt
FORMAT=aligned
TIMEOUT_MS=60000

die() { printf '%s\n' "malt-sql: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENVIRONMENT="${2:-}"; shift 2 ;;
    --db) DB="${2:-}"; shift 2 ;;
    --csv) FORMAT=csv; shift ;;
    --timeout) TIMEOUT_MS="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

case "$ENVIRONMENT" in
  prod) PORT=5434 ;;
  integ|integration) PORT=5433 ;;
  *) die "--env must be prod or integ" ;;
esac

SQL="${1:-}"
[[ -z "$SQL" && ! -t 0 ]] && SQL="$(cat)"
[[ -z "${SQL//[[:space:]]/}" ]] && die "no SQL given"

# ---------- layer 1+2: static analysis of the statement ----------
# strip -- and /* */ comments so keywords cannot hide inside them
STRIPPED="$(printf '%s' "$SQL" \
  | perl -0pe 's{/\*.*?\*/}{ }gs; s{--[^\n]*}{ }g' \
  | tr '\n\r\t' '   ')"
LOWER="$(printf '%s' "$STRIPPED" | tr '[:upper:]' '[:lower:]')"

# single statement only: no ';' followed by anything but whitespace
BODY="${STRIPPED%"${STRIPPED##*[![:space:]]}"}"   # rtrim
BODY="${BODY%;}"
[[ "$BODY" == *";"* ]] && die "REFUSED: multiple statements are not allowed (one read query per call)."

case "$LOWER" in
  select\ *|select$'\t'*|with\ *|explain\ *|show\ *|table\ *|values\ *|"("*) ;;
  *) die "REFUSED: read-only CLI. Statement must start with SELECT / WITH / EXPLAIN / SHOW / TABLE / VALUES." ;;
esac

DENY='insert |update |delete |truncate|drop |alter |create |grant |revoke |reindex|vacuum|analyze|cluster |merge |upsert|copy |set +role|reset +role|set +session|set +local|set +transaction|default_transaction_read_only|do +\$|call |perform |lock |listen |notify |begin |commit|rollback|savepoint|prepare |execute |declare |fetch |move |discard|refresh +materialized|comment +on|security +label|nextval|setval|lo_|pg_terminate_backend|pg_cancel_backend|pg_write|pg_read_file|pg_read_binary_file|pg_ls_dir|pg_reload_conf|pg_rotate|pg_switch_wal|pg_create|pg_drop_replication|pg_promote|pg_sleep|dblink|postgres_fdw|for +update|for +no +key +update|for +share|into +temp|into +temporary|writable|\\\\!|\\\\copy|\\\\i |\\\\o |\\\\g |\\\\connect|\\\\c '
if printf '%s ' "$LOWER" | grep -Eq "$DENY"; then
  BAD="$(printf '%s ' "$LOWER" | grep -Eo "$DENY" | head -1)"
  die "REFUSED: forbidden token '${BAD}' — this CLI is READ-ONLY on production. No exception, ever."
fi

# ---------- credentials ----------
PSQL="${PSQL:-}"
if [[ -z "$PSQL" ]]; then
  for c in "$(command -v psql 2>/dev/null || true)" /opt/homebrew/opt/libpq/bin/psql /usr/local/opt/libpq/bin/psql; do
    [[ -n "$c" && -x "$c" ]] && { PSQL="$c"; break; }
  done
fi
[[ -n "$PSQL" ]] || die "psql not found. Install it: brew install libpq"
[[ -x "$GCLOUD_BIN" ]] || die "gcloud not found at $GCLOUD_BIN (set GCLOUD_BIN)"

if ! (exec 3<>/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null; then
  die "no tunnel on 127.0.0.1:$PORT — ask the user to run:  malt tunnel start pg-$( [[ $ENVIRONMENT == prod ]] && echo prod || echo integ )"
fi

ACCOUNT="$("$GCLOUD_BIN" config get account 2>/dev/null | tail -1)"
[[ -n "$ACCOUNT" && "$ACCOUNT" != "(unset)" ]] || die "no gcloud account — ask the user to run: gcloud auth login"
TOKEN="$("$GCLOUD_BIN" sql generate-login-token 2>/dev/null)" \
  || die "could not mint a Cloud SQL login token — ask the user to run: gcloud auth login"

# ---------- layer 3: server-side read-only session ----------
export PGPASSWORD="$TOKEN"
export PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=${TIMEOUT_MS} -c idle_in_transaction_session_timeout=${TIMEOUT_MS} -c lock_timeout=5000"

ARGS=(-X -w -h 127.0.0.1 -p "$PORT" -U "$ACCOUNT" -d "$DB" -v ON_ERROR_STOP=1 -P pager=off)
[[ "$FORMAT" == csv ]] && ARGS+=(--csv)

# ---------- hard output cap (protects caller context — no exception, no flag to raise it) ----------
# Discipline (LIMIT explicite, count-first) is prose, not enforced. This cap is the deterministic backstop.
MAX_LINES=500
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
"$PSQL" "${ARGS[@]}" -c "$BODY" > "$OUT"
TOTAL_LINES="$(wc -l < "$OUT" | tr -d ' ')"
if [[ "$TOTAL_LINES" -gt "$MAX_LINES" ]]; then
  head -n "$MAX_LINES" "$OUT"
  printf '\n[TRUNCATED by malt-sql.sh: %s lines total, showing first %s. Add LIMIT / narrow the filter instead of re-running as-is.]\n' "$TOTAL_LINES" "$MAX_LINES"
else
  cat "$OUT"
fi
