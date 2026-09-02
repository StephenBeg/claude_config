#!/usr/bin/env bash
# PreToolUse(Bash|mcp__notion__*|mcp__*Atlassian*) — CLAUDE.md § LANGUE DES
# ÉCRITURES EXTERNES.
#
# "Tout ce qui est écrit dans Notion, JIRA ou GitLab est en ANGLAIS" est la règle
# la plus violée par construction : le contexte de travail est en français, donc
# le premier jet sort en français. Ici l'écriture est INSPECTÉE avant de partir.
#
# Détection : comptage de mots-outils exclusivement français (mots entiers), les
# ambigus EN/FR (plus, car, son, la, le, on, en, or, ou) étant exclus pour ne pas
# bloquer un texte anglais. Seuil : 3 occurrences.
# Exception CLAUDE.md : le champ JIRA Prompt (customfield_11956) est en FRANÇAIS
# -> tout appel qui le porte est laissé passer.
#
# Gate : external-lang
set -uo pipefail
. "$HOME/.claude/scripts/wf-gates-lib.sh"

INPUT="$(cat)"
TOOL="$(gate_field tool_name)"
TEXT=""

case "$TOOL" in
  Bash)
    gate_load_cmd
    is_write=0
    gate_invoked 'glab +(mr|issue) +(create|new|update|note|comment)' && is_write=1
    printf '%s' "$CMD_CODE" | grep -Eq -- '--method +(POST|PUT)|curl[^|]*-X +(POST|PUT)' && is_write=1
    # un curl JIRA avec un corps est une écriture même sans -X explicite
    printf '%s' "$CMD_CODE" | grep -Eq 'rest/api/3' && printf '%s' "$CMD_CODE" | grep -Eq -- '(-d|--data|--data-raw|--data-binary) ' && is_write=1
    [[ $is_write -eq 1 ]] || exit 0
    printf '%s' "$CMD_CODE" | grep -Eq 'rest/api/3|atlassian|jira|glab|gitlab|notion' || exit 0
    TEXT="$CMD_TRUE"
    ;;
  mcp__notion__*)
    case "$TOOL" in
      *create*|*update*|*comment*|*message*) TEXT="$(gate_field tool_input)" ;;
      *) exit 0 ;;
    esac
    ;;
  *Atlassian*|*atlassian*)
    case "$TOOL" in
      *create*|*update*|*comment*|*transition*) TEXT="$(gate_field tool_input)" ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

[[ -n "$TEXT" ]] || exit 0
# Champ Prompt JIRA : français assumé par CLAUDE.md.
printf '%s' "$TEXT" | grep -q 'customfield_11956' && exit 0

hits=$(printf '%s' "$TEXT" | python3 -c '
import sys, re
FR = """les des une dans pour avec être est sont qui que sur aux cette ces ainsi
donc mais où par ses nous vous elle alors quand depuis vers chaque toute tous
fait faire été avoir doit peut pas cela ceci afin lors dont leur leurs même
aussi très entre sans sous déjà encore tant sinon lorsque puisque celui celle
ceux entre notre votre leurs quil quon dune dun cest""".split()
txt = sys.stdin.read().lower()
words = re.findall(r"[a-zà-ÿ]+", txt)
found = sorted({w for w in words if w in FR})
print("%d|%s" % (len(found), " ".join(found[:8])))' 2>/dev/null)

n="${hits%%|*}"
words="${hits#*|}"
[[ "${n:-0}" =~ ^[0-9]+$ ]] || exit 0
if [[ "$n" -ge 3 ]]; then
  gate_deny external-lang "cette écriture externe ($TOOL) contient du FRANÇAIS (mots détectés : $words). CLAUDE.md § LANGUE — RÈGLE ABSOLUE : tout ce qui part vers JIRA, GitLab ou Notion est en ANGLAIS (titres, descriptions, commentaires, notes de statut, subjects de commit, notes de review, même une réponse d'une ligne). Traduire avant d'envoyer. Seule exception : le champ JIRA Prompt (customfield_11956)."
fi
exit 0
