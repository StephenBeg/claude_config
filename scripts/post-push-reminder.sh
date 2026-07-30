#!/usr/bin/env bash
# PostToolUse (Bash) — rappelle le BLOC DE CLÔTURE obligatoire après un git push.
# Non bloquant : injecte un rappel en additionalContext.
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
case "$cmd" in
  *"git push"*|*"git-push"*)
    cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"RAPPEL (post-push-reminder) : un push vient d'avoir lieu. Terminer la réponse par le BLOC DE CLÔTURE obligatoire — 'Travail poussé sur : <branche>' + la description MR générée via le skill /gitlab-resume (Jira / App / Feature Flag / Comment)."}}
EOF
    ;;
esac
exit 0
