#!/usr/bin/env bash
# PostToolUse(Skill|Agent) — ENREGISTREUR D'ÉTAT.
#
# Les gates ne peuvent exiger une étape que si son accomplissement est OBSERVÉ.
# Ce hook transforme trois événements réels en état persistant :
#   Skill(<nom>)            -> skills=<csv>            (gate skill-required)
#   Agent(judge) VERDICT OK -> judge_ok_pre_push=1     (gate pre-push)
#   Agent(smoke-runner) BOOTED_OK -> smoke_ok=1        (gate pre-push)
# Rien n'est déclaré par le LLM : tout est lu dans la réponse de l'outil.
set -uo pipefail
ST="python3 $HOME/.claude/scripts/wf-state.py"
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
    ;;
  Agent|Task)
    at="$(field tool_input subagent_type)"
    pr="$(field tool_input prompt)"
    rs="$(field tool_response)"
    [[ -n "$rs" ]] || rs="$(printf '%s' "$input" | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("tool_response");print(r if isinstance(r,str) else json.dumps(r or ""))' 2>/dev/null)"

    if printf '%s' "$rs" | grep -q 'BOOTED_OK'; then
      $ST set smoke_ok=1
      msgs+=("SMOKE-RUN enregistré (BOOTED_OK) : le gate pre-push est levé sur ce point.")
    fi

    if [[ "$at" == "judge" ]] || printf '%s' "$pr" | grep -q 'CHECKPOINT='; then
      plan_gate=0
      printf '%s' "$pr" | grep -q 'plan-gate' && plan_gate=1
      if printf '%s' "$rs" | grep -Eq 'VERDICT:? *OK'; then
        if [[ $plan_gate -eq 1 ]]; then
          $ST set judge_ok_plan=1
          msgs+=("JUGE (plan-gate) OK enregistré.")
        else
          $ST set judge_ok_pre_push=1
          msgs+=("JUGE (pre-push) OK enregistré : le push est débloqué. Tout nouveau commit REMET ce verdict à zéro (le juge n'a pas vu ce code).")
        fi
      elif printf '%s' "$rs" | grep -Eq 'VERDICT:? *NEEDS_WORK'; then
        r="$($ST get judge_round)"; r="${r:-0}"
        $ST set "judge_round=$((r + 1))"
        msgs+=("JUGE NEEDS_WORK (round $((r + 1))). RÈGLE ABSOLUE malt-judge-loop : pas de round N+1 sans PREUVE DE CLÔTURE PAR GAP — traiter toute l'étendue de chaque GAP (pas seulement l'exemple cité), appliquer le fix, REJOUER la preuve exacte que le GAP mettait en défaut (test cité vert avec sortie, ligne couverte, path:line dans le diff), et seulement ensuite lancer un juge NEUF. Borne : 2 rounds (/dev, /hotfix), 4 (/plan) -> ensuite [ASK].")
      fi
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
