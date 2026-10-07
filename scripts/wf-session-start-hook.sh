#!/usr/bin/env bash
# SessionStart — réinjecte l'état de workflow de CETTE surface (reprise de
# session / compaction). Sans ça, un Claude qui reprend une surface ne sait plus
# ni où il en est, ni quel header porter, et laisse un titre périmé.
set -uo pipefail
input="$(cat)"
src="$(printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("source",""))' 2>/dev/null)"
# Une session neuve n'hérite pas du workflow de la précédente : sinon un ancien /hotfix rouvrirait la prod.
case "$src" in startup|clear) python3 "$HOME/.claude/scripts/wf-state.py" set workflow= ;; esac
state="$($HOME/.claude/scripts/cmux-tab.sh state show 2>/dev/null)"
[[ -n "$state" ]] || exit 0
printf 'ÉTAT DE WORKFLOW repris sur cette surface : %s. Recaler le header sur la réalité avant toute chose : ~/.claude/scripts/cmux-tab.sh sync (puis phase <PREFIX> "<résumé>" si la phase a changé).' "$state"
exit 0
