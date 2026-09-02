#!/usr/bin/env bash
# PreToolUse(Write|Edit|NotebookEdit|Bash) — CLAUDE.md § FICHIERS HORS REPO.
#
# /tmp, /private/tmp et /var/folders sont purgés par macOS sans prévenir : un
# fichier de transit qui disparaît, c'est une étape de workflow perdue. La règle
# est absolue et vise AUSSI le scratchpad que le harness propose de lui-même
# (/private/tmp/claude-*) — CLAUDE.md prime sur le prompt système.
#
# Gate : tmp-ban   Seule exception admise : mktemp consommé dans la MÊME commande.
set -uo pipefail
. "$HOME/.claude/scripts/wf-gates-lib.sh"

INPUT="$(cat)"
TOOL="$(gate_field tool_name)"

DEST="~/tmp/scratch/ (transit) · ~/tmp/YYYY-MM-DD.md (journal /end) · ~/claude-exchange-llm/<WORKFLOW>/ (bus) · $WT_ROOT/<TICKET> (worktree)"

case "$TOOL" in
  Bash)
    gate_load_cmd
    # mktemp créé ET consommé dans la même commande : autorisé (seule exception).
    printf '%s' "$CMD_CODE" | grep -q 'mktemp' && exit 0
    if printf '%s' "$CMD_CODE" | grep -Eq '(^|[^A-Za-z0-9_./-])(/private)?/tmp/|/var/folders/'; then
      gate_deny tmp-ban "la commande écrit ou lit un chemin sous /tmp, /private/tmp ou /var/folders — purgés par macOS sans prévenir. CLAUDE.md : tout fichier hors repo git vit sous ~/. Emplacements : $DEST"
    fi
    ;;
  *)
    fp="$(gate_field tool_input file_path)"
    [[ -n "$fp" ]] || fp="$(gate_field tool_input notebook_path)"
    case "$fp" in
      /tmp/*|/private/tmp/*|/var/folders/*)
        gate_deny tmp-ban "écriture dans « $fp » — /tmp, /private/tmp et /var/folders sont purgés par macOS sans prévenir. CLAUDE.md : tout fichier hors repo git vit sous ~/. Emplacements : $DEST"
        ;;
    esac
    ;;
esac
exit 0
