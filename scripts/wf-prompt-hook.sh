#!/usr/bin/env bash
# UserPromptSubmit — deux corrections déterministes :
#
# 1. [ASK] COLLANT. Rien n'a jamais dit comment SORTIR de [ASK] : l'utilisateur
#    répond, et le header reste bloqué sur la question. Or "l'utilisateur vient
#    de répondre" EST un événement que le harness connaît. On sort donc de
#    [ASK]/[BLOCK]/[WAIT] tout seul, en revenant à la phase mémorisée (prev_phase).
# 2. DRIFT APRÈS COMPACTION. Le LLM perd la phase et le résumé, donc laisse le
#    header périmé. On réinjecte l'état à chaque tour : il survit au contexte.
set -uo pipefail

TAB="$HOME/.claude/scripts/cmux-tab.sh"
ST="python3 $HOME/.claude/scripts/wf-state.py"
cat >/dev/null  # payload non utilisé

phase="$($ST get phase)"
[[ -n "$phase" ]] || exit 0

extra=""
case "$phase" in
  ASK|BLOCK|WAIT)
    prev="$($ST get prev_phase)"
    [[ -n "$prev" ]] || prev=IMPL
    "$TAB" phase "$prev" >/dev/null 2>&1
    extra="L'utilisateur a répondu : le header est ressorti de [$phase] vers [$prev] automatiquement. Si la réponse fait changer de phase, poser la bonne : ~/.claude/scripts/cmux-tab.sh phase <PREFIX> \"<résumé>\". "
    ;;
esac

state="$($TAB state show 2>/dev/null)"
printf '%s' "${extra}ÉTAT DE WORKFLOW (persistant, survit à la compaction) : ${state}. Le header doit refléter ce que tu fais MAINTENANT — le poser via ~/.claude/scripts/cmux-tab.sh phase <PREFIX> \"<résumé>\" à chaque transition."
exit 0
