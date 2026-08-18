#!/usr/bin/env bash
# Test des hooks de workflow sur une SURFACE FACTICE (n'affecte pas l'état réel).
# Les payloads sont construits ici et non sur la ligne de commande : sinon le
# hook PostToolUse réel du Claude qui lance le test se déclencherait sur ses
# propres motifs (faux positif observé et corrigé par `invoked()`).
set -uo pipefail
export CMUX_SURFACE_ID=WFTEST WF_SURFACE_ID=WFTEST
S="$HOME/.claude/scripts"
ST="python3 $S/wf-state.py"
fail=0
ck() { # ck <libellé> <attendu> <obtenu>
  if [[ "$3" == *"$2"* ]]; then echo "ok   — $1"; else echo "FAIL — $1 : attendu '$2', obtenu '$3'"; fail=1; fi
}
payload() { printf '{"tool_input":{"command":%s},"tool_response":%s}' \
  "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
  "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")"; }

$ST reset

payload 'git worktree add ~/worktrees/malt/T-1 -b T-1 origin/master' 'Preparing worktree' | "$S/wf-bash-hook.sh" >/dev/null
ck "worktree add -> IMPL" "IMPL" "$($ST get phase)"

# Mention sans invocation : ne doit RIEN faire.
payload 'echo "on va faire git push puis glab mr merge"' 'ok' | "$S/wf-bash-hook.sh" >/dev/null
ck "mention seule ignorée" "IMPL" "$($ST get phase)"

payload 'glab mr create --fill' 'https://gitlab.com/x/-/merge_requests/31799' | "$S/wf-bash-hook.sh" >/dev/null
ck "mr create -> IID mémorisé" "31799" "$($ST get mr)"
ck "mr create -> phase MR" "MR" "$($ST get phase)"
ck "titre porte le numéro" "[MR (31799)]" "$($ST title)"

payload 'git push -u origin T-1' 'done' | "$S/wf-bash-hook.sh" >/dev/null
ck "push -> PIPE" "PIPE" "$($ST get phase)"

# [ASK] collant : l'utilisateur répond -> on ressort tout seul.
$ST phase ASK >/dev/null
ck "entrée en ASK" "ASK" "$($ST get phase)"
echo '{}' | "$S/wf-prompt-hook.sh" >/dev/null
ck "réponse utilisateur -> sortie de ASK" "PIPE" "$($ST get phase)"

payload 'glab mr merge 31799 --squash --remove-source-branch' 'merged' | "$S/wf-bash-hook.sh" >/dev/null
ck "merge -> merged=1" "1" "$($ST get merged)"

out=$(echo '{}' | "$S/wf-stop-hook.sh")
ck "stop bloque tant que /end manque" '"decision": "block"' "$out"
out=$(echo '{"stop_hook_active":true}' | "$S/wf-stop-hook.sh")
ck "stop ne boucle jamais" "" "$out"

# /end écrit -> plus de blocage, header [END].
log="$HOME/tmp/$(date +%F).md"; mkdir -p "$HOME/tmp"; touch "$log"
if ! grep -q '!31799' "$log" 2>/dev/null; then echo "MR: [!31799](url) (wf-hooks-test)" >> "$log"; added=1; fi
out=$(echo '{}' | "$S/wf-stop-hook.sh")
ck "stop passe une fois /end écrit" "" "$out"
ck "phase finale END" "END" "$($ST get phase)"
[[ "${added:-}" == 1 ]] && python3 - "$log" <<'PY'
import sys
p = sys.argv[1]
lines = [l for l in open(p) if "wf-hooks-test" not in l]
open(p, "w").writelines(lines)
PY

$ST reset
[[ $fail -eq 0 ]] && echo "TOUS LES TESTS PASSENT" || echo "ÉCHECS"
exit $fail
