#!/usr/bin/env bash
# UserPromptSubmit — deux corrections déterministes :
#
# 1. [ASK] COLLANT. Rien n'a jamais dit comment SORTIR de [ASK] : l'utilisateur
#    répond, et le header reste bloqué sur la question. Or "l'utilisateur vient
#    de répondre" EST un événement que le harness connaît. On sort donc de
#    [ASK]/[BLOCK]/[WAIT] tout seul, en revenant à la phase mémorisée (prev_phase).
# 2. DISPATCHER DE WORKFLOW. CLAUDE.md impose de choisir le workflow AVANT toute
#    action, et le signal est mécanique : un numéro de ticket JIRA en entrée -> /dev.
#    Le rappel est donc posé par le harness, pas laissé à l'initiative du LLM.
# 3. HEURES CALMES. « Vérifier date +%H%M avant de programmer » est un ordre que
#    le LLM oublie : l'heure et l'état de la plage sont injectés, factuels.
# 4. DRIFT APRÈS COMPACTION. Le LLM perd la phase et le résumé, donc laisse le
#    header périmé. On réinjecte l'état à chaque tour : il survit au contexte.
set -uo pipefail

TAB="$HOME/.claude/scripts/cmux-tab.sh"
ST="python3 $HOME/.claude/scripts/wf-state.py"
input=$(cat)
prompt=$(printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("prompt","") or "")' 2>/dev/null) || prompt=""

# Workflow courant, lu par le gate prod-db (la base de prod n'est ouverte qu'à /hotfix).
wf=$(printf '%s' "$prompt" | sed -nE '1s#^[[:space:]]*/(dev|plan|hotfix|orchestrator)([[:space:]].*)?$#\1#p; s#.*<command-name>/?(dev|plan|hotfix|orchestrator)</command-name>.*#\1#p' | head -1)
[[ -n "$wf" ]] && $ST set "workflow=$wf"

phase="$($ST get phase)"
extra=""
case "$phase" in
  ASK|BLOCK|WAIT)
    prev="$($ST get prev_phase)"
    [[ -n "$prev" ]] || prev=IMPL
    "$TAB" phase "$prev" >/dev/null 2>&1
    extra="L'utilisateur a répondu : le header est ressorti de [$phase] vers [$prev] automatiquement. Si la réponse fait changer de phase, poser la bonne : ~/.claude/scripts/cmux-tab.sh phase <PREFIX> \"<résumé>\". "
    ;;
esac

state=""
[[ -n "$phase" ]] && state="$($TAB state show 2>/dev/null)"

# --- dispatcher : ticket JIRA en entrée -> /dev (CLAUDE.md § WORKFLOWS) -------
ticket=$(printf '%s' "$prompt" | grep -oE '\b[A-Z][A-Z0-9]+-[0-9]+\b' | head -1)
if [[ -n "$ticket" && -z "$($ST get ticket)" ]]; then
  # Sans cette écriture, le gate jira-status du hook Stop ne se déclenche jamais :
  # il lit une clé que rien ne posait.
  $ST set "ticket=$ticket"
  extra="${extra}DISPATCHER (CLAUDE.md § WORKFLOWS) : le prompt porte le ticket $ticket et aucun workflow n'est en cours sur cette surface -> lancer /dev (ticket JIRA en entrée = /dev, la consigne vit dans le champ Prompt customfield_11956). Besoin large sans ticket -> /plan ; bug signalé sans ticket -> /hotfix. Poser aussi le titre de session commençant par $ticket, et le sujet : cmux-tab.sh topic \"<3-4 mots>\". "
fi

# --- heures calmes : fait, pas rappel ---------------------------------------
now="${WF_FAKE_HOUR:+${WF_FAKE_HOUR}h}"; now="${now:-$(date "+%H:%M")}"
h="${WF_FAKE_HOUR:-$(date +%H)}"
if [[ 10#$h -ge 20 || 10#$h -lt 7 ]]; then
  extra="${extra}HEURES CALMES ACTIVES (il est $now, plage 20h00-07h00) : aucune ré-invocation de Claude — /loop, ScheduleWakeup, boucle until en background, spawn d'/orchestrator, smoke-run en boucle sont GELÉS (le gate quiet-hours les refusera). Travail synchrone demandé par l'utilisateur : autorisé. "
fi

if [[ -n "$state" ]]; then
  printf '%s' "${extra}ÉTAT DE WORKFLOW (persistant, survit à la compaction) : ${state}. Le header doit refléter ce que tu fais MAINTENANT — le poser via ~/.claude/scripts/cmux-tab.sh phase <PREFIX> \"<résumé>\" à chaque transition."
elif [[ -n "$extra" ]]; then
  printf '%s' "$extra"
fi
exit 0
