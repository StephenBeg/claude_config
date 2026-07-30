#!/usr/bin/env bash
# PreToolUse (Edit|Write) — GIT WORKFLOW guardrail.
# Bloque toute édition dans le repo PRINCIPAL Malt tant qu'il est sur master.
# Les worktrees (~/worktrees/malt/*) et les autres chemins (~/.claude, ...) ne sont jamais bloqués.
input=$(cat)
fp=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
repo="$HOME/Documents/projects/malt"
case "$fp" in
  "$repo"/*)
    branch=$(git -C "$repo" branch --show-current 2>/dev/null)
    if [ "$branch" = "master" ]; then
      echo "BLOQUÉ (master-guard) : le repo principal $repo est sur 'master'. GIT WORKFLOW — ne jamais modifier le working tree sur master. Créer d'abord un worktree hors repo (base origin/master) et éditer uniquement dedans :
  cd $repo && git fetch origin master && git worktree add ~/worktrees/malt/TICKET -b TICKET-desc origin/master" >&2
      exit 2
    fi
    ;;
esac
exit 0
