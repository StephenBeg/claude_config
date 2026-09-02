#!/usr/bin/env bash
# Test des hooks de FIN DE TOUR et de PROMPT (ils décident, ils n'exit-code pas :
# on vérifie la DÉCISION émise sur stdout).
set -uo pipefail
cd "$(dirname "$0")/.."
export CMUX_SURFACE_ID="gates-test"
export WF_FAKE_HOUR=14          # hors heures calmes : les gates de fin doivent parler
ST="python3 $PWD/wf-state.py"
SCRATCH="$HOME/tmp/scratch/hooks-test"
mkdir -p "$SCRATCH"
pass=0; fail=0

check() {  # check <libellé> <attendu-dans-stdout|VIDE> <sortie>
  local label="$1" want="$2" got="$3"
  if [[ "$want" == "VIDE" ]]; then
    [[ -z "$got" ]] && { pass=$((pass+1)); echo "  ok   $label"; return; }
  elif printf '%s' "$got" | grep -q "$want"; then
    pass=$((pass+1)); echo "  ok   $label"; return
  fi
  fail=$((fail+1)); printf '  FAIL %s\n       %s\n' "$label" "${got:0:200}"
}

transcript() {  # transcript <texte du dernier message assistant> -> chemin
  local f="$SCRATCH/t.jsonl"
  python3 -c '
import json, sys
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "message": {"content": "go"}}) + "\n")
    f.write(json.dumps({"type": "assistant",
                        "message": {"content": [{"type": "text", "text": sys.argv[2]}]}}) + "\n")' "$f" "$1"
  printf '%s' "$f"
}

stop() {  # stop <transcript> [stop_hook_active]
  python3 -c '
import json, sys
print(json.dumps({"transcript_path": sys.argv[1],
                  "stop_hook_active": bool(sys.argv[2:] and sys.argv[2])}))' "$@" | ./wf-stop-hook.sh 2>&1
}

$ST reset
echo "== wf-stop-hook : /end après merge =="
$ST set mr=987654 merged=1
check "MR mergée sans /end -> bloque" '"decision": "block"' "$(stop "$(transcript 'fini')")"
check "boucle évitée (stop_hook_active)" VIDE "$(stop "$(transcript 'fini')" 1)"

echo "== wf-stop-hook : bloc de clôture après push =="
$ST reset; $ST set mr=987654 pushed_turn=1
check "push sans bloc de clôture -> bloque" 'BLOC DE CL' "$(stop "$(transcript 'Voilà, c est poussé.')")"
$ST set pushed_turn=1
check "push avec bloc de clôture -> passe" VIDE "$(stop "$(transcript 'Travail poussé sur : T-1-desc
Description MR : ...')")"
check "exigé une seule fois" VIDE "$(stop "$(transcript 'rien')")"

echo "== wf-stop-hook : livrable final =="
$ST reset; $ST set mr=987654 merged=1 end_done=1
check "fin sans Tradeoffs -> bloque" 'LIVRABLE FINAL' "$(stop "$(transcript 'MR mergée, ticket To Validate.')")"
$ST set livrable_done=
check "fin avec Tradeoffs -> passe" VIDE "$(stop "$(transcript '| Tradeoffs | aucun |')")"

echo "== wf-stop-hook : cran off =="
$ST reset; $ST set mr=987654 merged=1
check "end-gate=off" VIDE "$(WF_GATE_END_GATE=off stop "$(transcript 'fini')")"

echo "== wf-prompt-hook : dispatcher =="
$ST reset
out=$(printf '{"prompt":"BILL-2854 corrige l arrondi"}' | ./wf-prompt-hook.sh 2>&1)
check "ticket JIRA en entrée -> /dev" 'DISPATCHER' "$out"
$ST set ticket=BILL-2854
out=$(printf '{"prompt":"BILL-2854 suite"}' | ./wf-prompt-hook.sh 2>&1)
check "workflow déjà en cours -> pas de dispatch" VIDE "$(printf '%s' "$out" | grep -o DISPATCHER || true)"
$ST set phase=IMPL topic=TEST
out=$(printf '{"prompt":"go"}' | ./wf-prompt-hook.sh 2>&1)
check "état de workflow réinjecté" 'ÉTAT DE WORKFLOW' "$out"
out=$(printf '{"prompt":"go"}' | WF_FAKE_HOUR=22 ./wf-prompt-hook.sh 2>&1)
check "heures calmes annoncées" 'HEURES CALMES ACTIVES' "$out"

$ST reset; rm -rf "$SCRATCH"
printf '\n%d ok, %d FAIL\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
