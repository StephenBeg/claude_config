#!/usr/bin/env bash
# Stop — GATE DE CLÔTURE. Le /end était sautable parce que rien ne le vérifiait :
# c'était une ligne de prompt au milieu d'une liste de 15 étapes. Ici il devient
# une CONDITION DE FIN DE TOUR : tant que la MR est mergée sans que /end ait
# réellement écrit le log du jour, la fin de tour est refusée.
#
# La preuve est LUE, jamais supposée : on cherche le numéro de MR dans le log du
# jour (et celui de demain — /end bascule de jour après un /daily consommé).
# Garde-fous : jamais de boucle (stop_hook_active), jamais en heures calmes.
set -uo pipefail

ST="python3 $HOME/.claude/scripts/wf-state.py"
TAB="$HOME/.claude/scripts/cmux-tab.sh"

input=$(cat)
looping=$(printf '%s' "$input" | python3 -c \
  'import sys,json;print("1" if json.load(sys.stdin).get("stop_hook_active") else "")' 2>/dev/null) || looping=""
[[ -n "$looping" ]] && exit 0   # déjà relancé une fois : ne jamais boucler

iid="$($ST get mr)"
merged="$($ST get merged)"
[[ -n "$iid" && -n "$merged" ]] || exit 0

# /end a-t-il écrit ? On cherche la MR dans le log du jour ou du lendemain.
today="$HOME/tmp/$(date +%F).md"
tomorrow="$HOME/tmp/$(date -v+1d +%F).md"
if grep -qE "(!|merge_requests/)$iid\b" "$today" "$tomorrow" 2>/dev/null; then
  $ST set end_done=1
  [[ "$($ST get phase)" == "END" ]] || "$TAB" phase END >/dev/null 2>&1
  exit 0
fi

# Heures calmes : on ne relance pas Claude la nuit (CLAUDE.md).
h=$(date +%H)
if [[ 10#$h -ge 20 || 10#$h -lt 7 ]]; then exit 0; fi

python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
' "MR !$iid mergée mais /end n'a pas été fait : aucune trace de la MR dans $today. Ne pas clore. Lancer /end maintenant (log du jour + lien MR + lien JIRA + tradeoffs en commentaire JIRA en anglais), vérifier le statut JIRA 'To Validate', puis poser le header [END]."
exit 0
