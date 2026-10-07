#!/usr/bin/env bash
# SubagentStop — ENREGISTREUR D'ÉTAT, côté RÉSULTAT.
#
# C'est le seul endroit du harnais où la sortie réelle d'un sous-agent est
# disponible. Mesuré le 2026-10-02 : le payload porte `agent_id` (identique à
# l'`agentId` rendu au lancement, y compris avec plusieurs sous-agents en
# parallèle), `agent_type`, `agent_transcript_path` et `last_assistant_message`
# NON tronqué (3392 caractères relus intacts).
#
#   Agent(judge)        -> judge_ran_<ckpt>=1 (+ judge_ok_<ckpt>=1 si OK)
#   Agent(smoke-runner) -> smoke_ok=1 sur BOOTED_OK, jamais sur BOOT_FAILED
#
# Le checkpoint vient de l'entrée posée au lancement par wf-record.sh ; à défaut,
# il est relu dans le transcript du sous-agent. Jamais deviné.
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

aid="$(field agent_id)"
atype="$(field agent_type)"
msg="$(field last_assistant_message)"
tr="$(field agent_transcript_path)"

pending=""
[[ -n "$aid" ]] && pending="$($ST get "agent_$aid")"
IFS='|' read -r p_type p_ckpt p_report p_since <<<"${pending:-}"
[[ -n "${p_type:-}" ]] && atype="$p_type"
since="${p_since:-0}"
report="${p_report:-}"
ckpt="${p_ckpt:-}"

# Sans entrée de lancement (hook ajouté en cours de route, état réinitialisé),
# le checkpoint se relit dans la consigne reçue par le sous-agent lui-même.
if [[ -z "$ckpt" && -n "$tr" && -r "$tr" ]]; then
  ckpt="$(grep -o 'CHECKPOINT=[a-z-]*' "$tr" 2>/dev/null | head -1 | cut -d= -f2)"
fi
case "$ckpt" in plan-gate) ckpt=plan-gate ;; *) ckpt=pre-mr ;; esac

msgs=()

case "$atype" in
  smoke-runner)
    v="$(printf '%s' "$msg" | $SIG smoke-text)"
    [[ "$v" == "NONE" && -n "$report" ]] && v="$($SIG smoke-file "$report" "$since")"
    case "$v" in
      BOOTED_OK)
        $ST set smoke_ok=1
        msgs+=("SMOKE-RUN terminé : BOOTED_OK rendu par le sous-agent. Le gate pre-push est levé sur ce point.") ;;
      BOOT_FAILED)
        msgs+=("SMOKE-RUN terminé : BOOT_FAILED. Le gate pre-push reste FERMÉ sur ce point. Corriger le boot si le diff en est la cause, ou consigner l'indisponibilité de l'env local en Tradeoffs.") ;;
      *)
        msgs+=("SMOKE-RUN terminé sans verdict lisible (ni BOOTED_OK ni BOOT_FAILED en début de ligne). Le gate pre-push reste FERMÉ sur ce point.") ;;
    esac
    ;;
  judge)
    v="$(printf '%s' "$msg" | $SIG verdict-text)"
    [[ "$v" == "NONE" && -n "$report" ]] && v="$($SIG verdict-file "$report" "$since")"
    case "$v" in
      OK|NEEDS_WORK)
        if [[ "$ckpt" == "plan-gate" ]]; then $ST set judge_ran_plan=1; else $ST set judge_ran_pre_mr=1; fi
        if [[ "$v" == "OK" ]]; then
          if [[ "$ckpt" == "plan-gate" ]]; then $ST set judge_ok_plan=1; else $ST set judge_ok_pre_mr=1; fi
          msgs+=("JUGE ($ckpt) VERDICT: OK enregistré. Le passage de juge est acquis : la création de MR est débloquée.")
        else
          r="$($ST get judge_round)"; r="${r:-0}"
          $ST set "judge_round=$((r + 1))"
          msgs+=("JUGE ($ckpt) VERDICT: NEEDS_WORK (round $((r + 1))). Le PASSAGE est enregistré : le gate pre-mr est levé, la MR n'attend plus rien. RÈGLE ABSOLUE malt-judge-loop : le juge ne passe QU'UNE FOIS, il n'y a PAS de round 2 et PAS de GO à demander pour pousser. Traiter toute l'étendue de chaque GAP MÉTIER (pas seulement l'exemple cité), appliquer le fix, produire la PREUVE LISIBLE que le GAP est clos (path:line du comportement métier désormais écrit, nom du cas de test métier ajouté), puis CONTINUER le workflow (commit, push, création de MR) en rapportant GAPS, corrections et preuves dans le bloc de clôture et la description de MR, et ce qui reste ouvert en Tradeoffs. Un GAP de lint, style, commentaire ou test rouge remonté par erreur est du bruit : le noter et passer.")
        fi ;;
      *)
        msgs+=("JUGE ($ckpt) terminé sans verdict lisible : ni ligne commençant par VERDICT: dans sa conclusion, ni JUDGE-VERDICT: postérieur au lancement dans son compte rendu. Le gate pre-mr reste FERMÉ. Lire le compte rendu du juge et, s'il a réellement conclu, le constater avec : python3 ~/.claude/scripts/wf-signals.py verdict-file <REPORT_FILE> $since") ;;
    esac
    ;;
esac

[[ -n "$aid" ]] && $ST set "agent_$aid="

if [[ ${#msgs[@]} -gt 0 ]]; then
  printf '%s' "${msgs[*]}" | python3 -c '
import sys, json
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": sys.stdin.read()}}))'
fi
exit 0
