#!/usr/bin/env bash
# SessionStart — réinjecte l'état de workflow de CETTE surface (reprise de
# session / compaction). Sans ça, un Claude qui reprend une surface ne sait plus
# ni où il en est, ni quel header porter, et laisse un titre périmé.
set -uo pipefail
cat >/dev/null
state="$($HOME/.claude/scripts/cmux-tab.sh state show 2>/dev/null)"
[[ -n "$state" ]] || exit 0
printf 'ÉTAT DE WORKFLOW repris sur cette surface : %s. Recaler le header sur la réalité avant toute chose : ~/.claude/scripts/cmux-tab.sh sync (puis phase <PREFIX> "<résumé>" si la phase a changé).' "$state"
exit 0
