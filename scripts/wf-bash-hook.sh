#!/usr/bin/env bash
# PostToolUse (Bash) — AUTO-AVANCE du header CMUX + rappels de workflow.
#
# Remplace post-push-reminder.sh (qu'il englobe). Principe : le header ne dépend
# plus de la mémoire du LLM. Le hook voit la COMMANDE exécutée ET sa SORTIE, en
# déduit l'état réel, et met le header à jour LUI-MÊME. Ce qu'il ne peut pas
# faire tout seul (rédiger le bloc de clôture, lancer /end), il l'injecte comme
# rappel impératif en additionalContext.
#
# Déclencheurs :
#   git worktree add        -> [IMPL]  (le dev commence réellement)
#   glab mr create          -> mémorise l'IID + [MR (iid)]   <- "la MR n'apparaît jamais"
#   git push                -> [PIPE (iid)] si une MR existe + rappel bloc de clôture
#   glab mr merge           -> merged=1, [CLEAN] + rappel /end OBLIGATOIRE
set -uo pipefail

TAB="$HOME/.claude/scripts/cmux-tab.sh"
ST="python3 $HOME/.claude/scripts/wf-state.py"

input=$(cat)
# La commande et sa sortie, aplaties sur une ligne chacune (pattern-matching pur).
#   Les CHAÎNES CITÉES sont neutralisées : un `git commit -m "... glab mr create
#   ..."` ou un heredoc qui *parle* d'une commande ne doit rien déclencher
#   (faux positif observé). Seul le code shell nu est analysé.
cmd=$(printf '%s' "$input" | python3 -c '
import sys, json, re
d = json.load(sys.stdin)
c = ((d.get("tool_input") or {}).get("command", "")).replace("\n", " ")
c = re.sub(r"\x27[^\x27]*\x27|\"[^\"]*\"", " Q ", c)   # vide le contenu des quotes
print(c)
' 2>/dev/null) || cmd=""
out=$(printf '%s' "$input" | python3 -c '
import sys, json
d = json.load(sys.stdin)
r = d.get("tool_response")
print((r if isinstance(r, str) else json.dumps(r or "")).replace("\n", " ")[:4000])
' 2>/dev/null) || out=""
payload="$cmd $out"

msgs=()
note() { msgs+=("$1"); }

# INVOCATION RÉELLE, pas simple mention. Un `echo "... git push ..."` ou un grep
# sur le motif ne doit RIEN déclencher : on n'accepte le motif qu'en tête de
# commande ou après un séparateur de shell (; && || | ( newline).
invoked() { printf '%s' "$cmd" | grep -Eq "(^|[;&|(] *)($1)"; }

if invoked 'git +worktree +add'; then
  [[ "$($ST get phase)" =~ ^(IMPL|PIPE|MR|CLEAN|END)$ ]] || "$TAB" phase IMPL >/dev/null 2>&1
fi

# MR créée : l'IID sort dans l'URL renvoyée par glab (…/merge_requests/1234).
if invoked 'glab +mr +(create|new)'; then
    iid=$(printf '%s' "$payload" | grep -oE 'merge_requests/[0-9]+' | grep -oE '[0-9]+' | head -1)
    if [[ -n "$iid" ]]; then
      "$TAB" mr "$iid" >/dev/null 2>&1
      "$TAB" phase MR >/dev/null 2>&1
      note "HEADER (auto) : MR !$iid détectée -> onglet passé en [MR ($iid)]. Reviewer @stephen.begot + labels de squad obligatoires."
    else
      note "RAPPEL : une MR vient d'être créée mais son numéro n'a pas pu être lu. Poser le header manuellement : ~/.claude/scripts/cmux-tab.sh mr <IID>"
    fi
fi

if invoked 'git +push'; then
  "$TAB" sync >/dev/null 2>&1
  iid="$($ST get mr)"
  if [[ -n "$iid" ]]; then
    "$TAB" phase PIPE >/dev/null 2>&1
    note "HEADER (auto) : push -> onglet [PIPE ($iid)]. Suivi pipeline OBLIGATOIRE jusqu'au vert cité (skill malt-pipeline-followup), solo comme orchestré."
  fi
  note "RAPPEL (post-push) : terminer la réponse par le BLOC DE CLÔTURE — 'Travail poussé sur : <branche>' + description MR générée via /gitlab-resume (Jira / App / Feature Flag / Comment)."
fi

if invoked 'glab +mr +merge'; then
  $ST set merged=1
  "$TAB" phase CLEAN >/dev/null 2>&1
  note "MR MERGÉE -> il RESTE 3 obligations, dans cet ordre : (1) statut JIRA 'To Validate' ; (2) lancer /end (log du jour + tradeoffs en commentaire JIRA) ; (3) clean du worktree puis header [END]. Le hook Stop BLOQUERA la fin de tour tant que /end n'est pas écrit."
fi

if [[ ${#msgs[@]} -gt 0 ]]; then
  printf '%s' "${msgs[*]}" | python3 -c '
import sys, json
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": sys.stdin.read()}}))
'
fi
exit 0
