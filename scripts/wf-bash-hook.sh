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
cmd=$(printf '%s' "$input" | python3 "$HOME/.claude/scripts/wf-normcmd.py" 2>/dev/null) || cmd=""
cmd_raw=$(printf '%s' "$input" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(((d.get("tool_input") or {}).get("command", "")).replace("\n", " "))
' 2>/dev/null) || cmd_raw=""
out=$(printf '%s' "$input" | python3 -c '
import sys, json
d = json.load(sys.stdin)
r = d.get("tool_response")
print((r if isinstance(r, str) else json.dumps(r or "")).replace("\n", " ")[-200000:])
' 2>/dev/null) || out=""
payload="$cmd $out"

# Un enregistrement conclut sur le RÉSULTAT : une commande dont la sortie dit
# qu'elle a échoué ne pose aucun état. Sans ça un merge refusé posait merged=1,
# et la fin de tour exigeait un /end sur une MR jamais mergée.
failed() { printf '%s' "$out" | grep -Eqi '! \[rejected\]|\berror\b|\bfatal\b|\bfailed\b|\bdenied\b|\b4[0-9]{2}\b|\b5[0-9]{2}\b'; }

msgs=()
note() { msgs+=("$1"); }

# INVOCATION RÉELLE, pas simple mention. Un `echo "... git push ..."` ou un grep
# sur le motif ne doit RIEN déclencher : on n'accepte le motif qu'en tête de
# commande ou après un séparateur de shell (; && || | ( newline).
invoked() { printf '%s' "$cmd" | grep -Eq "(^|[;&|(] *)($1)"; }

if invoked 'git +worktree +add'; then
  # Un nouveau worktree = un nouveau ticket : les preuves du precedent ne valent
  # plus rien. Sans cette remise a zero, un judge_ran_pre_mr acquis sur le ticket
  # d'avant ouvrirait la MR du suivant sans aucun juge.
  $ST set judge_ran_pre_mr= judge_ok_pre_mr= judge_ran_plan= judge_ok_plan= judge_pending= \
         judge_round= smoke_ok= smoke_pending= tests_green= rebased_skipci= \
         last_push_at= mr= merged= end_done= livrable_done=
  [[ "$($ST get phase)" =~ ^(IMPL|PIPE|MR|CLEAN|END)$ ]] || "$TAB" phase IMPL >/dev/null 2>&1
fi

# MR créée : l'IID sort dans l'URL renvoyée par glab (…/merge_requests/1234).
if invoked 'glab +mr +(create|new)'; then
    # L'IID vient de la SORTIE (l'URL que glab renvoie), jamais de la commande :
    # un IID lu dans la requête enverrait le gate mr-merge vérifier une autre MR.
    iid=$(printf '%s' "$out" | grep -oE 'merge_requests/[0-9]+' | grep -oE '[0-9]+' | head -1)
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

if invoked 'glab +mr +merge' && ! failed; then
  $ST set merged=1
  "$TAB" phase CLEAN >/dev/null 2>&1
  note "MR MERGÉE -> il RESTE 3 obligations, dans cet ordre : (1) statut JIRA 'To Validate' ; (2) lancer /end (log du jour + tradeoffs en commentaire JIRA) ; (3) clean du worktree puis header [END]. Le hook Stop BLOQUERA la fin de tour tant que /end n'est pas écrit."
fi

# --------------------------------------------------------------------------- #
# ENREGISTREMENTS POUR LES GATES — rien n'est déclaré par le LLM, tout est OBSERVÉ
# dans la commande et sa sortie. Ces clés sont les préconditions lues par
# gate-bash-git.sh (pre-push, mr-merge) et wf-stop-hook.sh.
# --------------------------------------------------------------------------- #

# Tests verts : exige une TÂCHE DE TEST dans la commande ET un succès dans la sortie.
# (Un `BUILD SUCCESSFUL` de compilation ne prouve aucun test — mémoire :
#  un vert Gradle exige des preuves cumulatives.)
# La sortie est gardée par la QUEUE : `BUILD SUCCESSFUL` sort en dernier, une
# troncature en tête rendait le gate pre-push insatisfiable sur une suite longue.
if printf '%s' "$cmd" | grep -Eq 'gradlew[^|]*(test|check)|pnpm[^|]*test|vitest|jest'; then
  printf '%s' "$out" | grep -Eq 'BUILD SUCCESSFUL|[0-9]+ (tests? )?passed|Tests? passed|PASS ' \
    && $ST set tests_green=1
fi

# Smoke-run observé en direct (hors subagent smoke-runner).
# Les apps Kotlin loguent `Started AccountingApplicationKt in` : sans le `Kt`
# optionnel le motif rate le seul succès qu'il doit reconnaître.
printf '%s' "$out" | grep -Eq 'Started [A-Za-z]*Application(Kt)? in' && $ST set smoke_ok=1

# Un commit PÉRIME l'APPROBATION du juge (il n'a pas vu ce code), pas le fait
# qu'un round de jugement ait eu lieu : judge_ran_pre_mr survit, donc corriger
# les GAPS d'un NEEDS_WORK puis committer ne re-bloque pas la création de MR.
if invoked 'git +commit'; then
  $ST set judge_ok_pre_mr=
fi

# Rebase skip_ci=true : précondition du merge (inspecté sur la commande BRUTE,
# l'URL vit entre quotes).
printf '%s' "$cmd_raw" | grep -Eq 'merge_requests/[0-9]+/rebase' \
  && printf '%s' "$cmd_raw" | grep -q 'skip_ci=true' \
  && ! failed \
  && $ST set rebased_skipci=1

# Push de ce tour : le hook Stop exige le BLOC DE CLÔTURE dans la réponse.
# last_push_at date le dernier push RÉEL : c'est lui qui périme un Approved,
# pas le rebase d'API que la procédure de merge prescrit juste avant.
if invoked 'git +push' && ! failed; then
  $ST set pushed_turn=1 "last_push_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

# ANTI-VEILLE (CLAUDE.md) : un process long ne doit pas être coupé par la veille.
# Le hook le fait LUI-MÊME au lieu de le rappeler — et vérifie d'abord qu'un
# caffeinate ne tourne pas déjà.
bg=$(printf '%s' "$input" | python3 -c 'import sys,json;print("1" if (json.load(sys.stdin).get("tool_input") or {}).get("run_in_background") else "")' 2>/dev/null) || bg=""
if [[ -n "$bg" ]] || printf '%s' "$cmd" | grep -Eq 'until .*(sleep|glab|gradlew)'; then
  pgrep -f 'caffeinate -di' >/dev/null 2>&1 || nohup caffeinate -di >/dev/null 2>&1 &
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
