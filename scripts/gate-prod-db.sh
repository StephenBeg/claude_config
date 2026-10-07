#!/usr/bin/env bash
# PreToolUse(Bash|Skill) — la base de PROD n'est ouverte qu'à /hotfix.
#
# /plan, /dev, /orchestrator et une session libre n'ont jamais besoin de vraies
# données : elles ancrent la session sur un cas particulier et la font dériver.
# Seul un diagnostic de bug (/hotfix) lit la prod. Le workflow courant est posé
# par wf-prompt-hook.sh (slash command tapée) et wf-record.sh (Skill invoqué).
#
# Refusé hors workflow=hotfix : malt-sql.sh en env prod (défaut), ouverture d'un
# tunnel pg-prod / mongo-prod*, mint d'un token Cloud SQL, skill malt-prod-sql.
# Autorisé partout : malt-sql.sh --env integ.
#
# Gate : prod-db
set -uo pipefail
. "$HOME/.claude/scripts/wf-gates-lib.sh"

INPUT="$(cat)"
TOOL="$(gate_field tool_name)"

wf="$($ST get workflow)"
[[ "$wf" == "hotfix" ]] && exit 0
why="la base de prod est réservée à /hotfix (workflow courant : ${wf:-aucun}). Hors hotfix, ne PAS demander d'accès DB, de tunnel ni de gcloud auth à l'utilisateur : travailler depuis le code, les contrats, les tests et les fixtures ; une hypothèse sur les données réelles reste marquée « non vérifiée ». Lire l'intégration reste possible : malt-sql.sh --env integ. Si un vrai bug de prod est en jeu : proposer à l'utilisateur de basculer en /hotfix."

case "$TOOL" in
  Skill)
    sk="$(gate_field tool_input skill)"
    [[ "${sk##*:}" == "malt-prod-sql" ]] && gate_deny prod-db "skill malt-prod-sql : $why"
    ;;
  Bash)
    gate_load_cmd
    if gate_invoked '([~a-zA-Z0-9_./-]*/)?malt-sql\.sh' \
       && ! printf '%s' "$CMD_RAW" | grep -Eq 'malt-sql\.sh.*--env[ =]+integ'; then
      gate_deny prod-db "malt-sql.sh vise la prod : $why"
    fi
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|(] *)malt +tunnel +start' \
       && printf '%s' "$CMD_RAW" | grep -Eq 'tunnel +start +(pg-prod|mongo-prod)'; then
      gate_deny prod-db "tunnel de prod : $why"
    fi
    if gate_invoked 'gcloud +sql +generate-login-token'; then
      gate_deny prod-db "token Cloud SQL : $why"
    fi
    ;;
esac
exit 0
