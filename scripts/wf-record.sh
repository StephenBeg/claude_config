#!/usr/bin/env bash
# PostToolUse(Skill|Agent|Task) — ENREGISTREUR D'ÉTAT, côté LANCEMENT.
#
# Les gates ne peuvent exiger une étape que si son accomplissement est OBSERVÉ.
# Ce hook n'observe qu'un seul fait fiable sur un sous-agent : qu'il a été LANCÉ.
#
#   Skill(<nom>)        -> skills=<csv>                 (gate skill-required)
#                          + workflow=<dev|plan|hotfix|orchestrator> (gate prod-db)
#   Agent(<type>)       -> agent_<id>=<type>|<ckpt>|<report>|<epoch>
#                          + judge_pending / smoke_pending
#
# AUCUN GATE N'EST LEVÉ ICI. Mesuré le 2026-10-02 : l'outil `Agent` est toujours
# asynchrone dans ce harnais, `tool_response` vaut
# {isAsync, status:"async_launched", agentId, prompt, outputFile, …} et le champ
# `prompt` REJOUE la consigne. Grep ce blob, c'est grep la requête : un prompt de
# smoke-runner qui nomme BOOTED_OK posait smoke_ok=1 avant tout démarrage.
# Le verdict est posé par wf-subagent-hook.sh (SubagentStop), qui reçoit la
# sortie finale réelle et le même agent_id.
set -uo pipefail
ST="python3 $HOME/.claude/scripts/wf-state.py"
SIG="python3 $HOME/.claude/scripts/wf-signals.py"
input="$(cat)"

field() {
  printf '%s' "$input" | python3 -c '
import sys, json
try: cur = json.load(sys.stdin)
except Exception: print(""); raise SystemExit
for k in sys.argv[1:]:
    cur = cur.get(k) if isinstance(cur, dict) else None
print(cur if isinstance(cur, str) else ("" if cur is None else json.dumps(cur)))' "$@" 2>/dev/null
}

tool="$(field tool_name)"
msgs=()

case "$tool" in
  Skill)
    sk="$(field tool_input skill)"
    sk="${sk##*:}"                       # plugin:skill -> skill
    [[ -n "$sk" ]] || exit 0
    cur="$($ST get skills)"
    case ",$cur," in
      *",$sk,"*) : ;;
      *) $ST set "skills=${cur:+$cur,}$sk" ;;
    esac
    case "$sk" in
      malt-accounting-domain|obsidian) $ST set preanalysis=1 ;;
    esac
    case "$sk" in
      dev|plan|hotfix|orchestrator) $ST set "workflow=$sk" ;;
    esac
    ;;
  Agent|Task)
    at="$(field tool_input subagent_type)"
    pr="$(field tool_input prompt)"
    aid="$(field tool_response agentId)"
    rs="$(printf '%s' "$input" | $SIG resp-text)"
    now="$(date +%s)"

    # Le CHECKPOINT déclaré dit à QUEL gate ce juge est destiné, il ne lève rien
    # tout seul. Le ranger d'après la déclaration, jamais d'après une sous-chaîne
    # du prompt : un juge pre-mr qui MENTIONNE plan-gate était classé en plan-gate.
    ckpt="$(printf '%s' "$pr" | sed -n 's/.*CHECKPOINT=\([a-z-]*\).*/\1/p' | head -1)"
    case "$ckpt" in
      plan-gate|pre-mr|pre-push|hotfix-verify) : ;;
      *) printf '%s' "$pr" | grep -q 'plan-gate' && ckpt=plan-gate || ckpt=pre-mr ;;
    esac
    report="$(printf '%s' "$pr" | sed -nE 's/.*REPORT_FILE=("([^"]*)"|'"'"'([^'"'"']*)'"'"'|([^ ]+)).*/\2\3\4/p' | head -1)"
    report="${report/#\~/$HOME}"

    if [[ -n "$aid" ]]; then
      $ST prune-agents
      $ST set "agent_$aid=$at|$ckpt|$report|$now"
      case "$at" in
        judge)        $ST set "judge_pending=$ckpt|$report|$now" ;;
        smoke-runner) $ST set "smoke_pending=$report|$now" ;;
      esac
      msgs+=("SOUS-AGENT « $at » lancé en asynchrone (id $aid). AUCUN gate n'est levé par un lancement : l'état sera posé par le hook SubagentStop quand la conclusion réelle arrivera. Attendre cette conclusion avant l'étape qu'elle débloque.")
    else
      # Chemin synchrone : ne vaut que si la réponse porte un VRAI résultat
      # (les champs d'écho ont été retirés par wf-signals.py resp-text).
      case "$at" in smoke-runner) sv="$(printf '%s' "$rs" | $SIG smoke-text)" ;; *) sv=NONE ;; esac
      case "$sv" in
        BOOTED_OK)
          $ST set smoke_ok=1
          msgs+=("SMOKE-RUN enregistré (BOOTED_OK rendu par le sous-agent) : le gate pre-push est levé sur ce point.") ;;
      esac
      if [[ "$at" == "judge" ]] || printf '%s' "$pr" | grep -q 'CHECKPOINT='; then
        v="$(printf '%s' "$rs" | $SIG verdict-text)"
      else
        v=NONE
      fi
      case "$v" in
        OK|NEEDS_WORK)
          if [[ "$ckpt" == "plan-gate" ]]; then $ST set judge_ran_plan=1; else $ST set judge_ran_pre_mr=1; fi
          [[ "$v" == "OK" ]] && { [[ "$ckpt" == "plan-gate" ]] && $ST set judge_ok_plan=1 || $ST set judge_ok_pre_mr=1; }
          msgs+=("JUGE ($ckpt) $v enregistré : le passage de juge est acquis, le gate pre-mr est levé.") ;;
      esac
    fi
    ;;
esac

if [[ ${#msgs[@]} -gt 0 ]]; then
  printf '%s' "${msgs[*]}" | python3 -c '
import sys, json
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": sys.stdin.read()}}))'
fi
exit 0
