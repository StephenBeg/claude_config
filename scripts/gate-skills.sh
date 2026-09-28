#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit|Bash|Grep|Glob) — AGENTS.md § Skills To Load
# + CLAUDE.md § CONTEXTE MONOREPO MALT (pré-analyse).
#
# "Read the relevant skill BEFORE editing" est la consigne la plus facile à
# sauter : elle ne coûte rien à ignorer et le code compile quand même. Ici le
# type de fichier touché EXIGE son skill, et l'exigence est vérifiée contre
# l'état (les invocations du tool Skill sont enregistrées par wf-record.sh).
#
# Gates :
#   skill-required  éditer un fichier sans avoir chargé le(s) skill(s) qui le couvre(nt)
#   prose-required  écrire du code sans le skill claude-prose (défaut : warn — le
#                   rappel doit passer même dans un sous-agent sans tool Skill)
#   preanalysis     explorer le monorepo sans pré-analyse (défaut : warn — un
#                   blocage casserait les sous-agents explorer/judge, qui n'ont
#                   pas le tool Skill)
set -uo pipefail
. "$HOME/.claude/scripts/wf-gates-lib.sh"

INPUT="$(cat)"
TOOL="$(gate_field tool_name)"
LOADED=",$($ST get skills),"

need() {  # $1 = skills requis (csv), $2 = raison
  local missing=""
  local IFS=','
  for s in $1; do
    [[ -n "$s" ]] || continue
    case "$LOADED" in *",$s,"*) : ;; *) missing="$missing $s" ;; esac
  done
  [[ -n "$missing" ]] || return 0
  gate_deny skill-required "$2 — skill(s) non chargé(s) :$missing. AGENTS.md § Skills To Load : charger le skill AVANT d'éditer (tool Skill), il porte les conventions du domaine. Déjà lu dans une session antérieure ne compte pas : le charger ici."
}

PROSE_DONE=0
prose() {  # $1 = chemin -> rappelle la barre de prose sur tout fichier de code
  [[ $PROSE_DONE -eq 0 ]] || return 0
  case "$1" in *.kt|*.java|*.ts|*.tsx|*.vue|*.js|*.sql|*.py|*.yaml|*.yml) : ;; *) return 0 ;; esac
  case "$LOADED" in *",claude-prose,"*) return 0 ;; esac
  PROSE_DONE=1
  gate_deny prose-required "code écrit sans le skill claude-prose. Barre permanente : clair, lisible, compréhensible, CONCIS. Commentaires : défaut AUCUN, plafond dur 1 à 2 lignes, seulement un fait impossible à lire dans le code (piège, contrainte externe, pourquoi PAS la solution évidente, TODO, directive outillage). À supprimer à vue : reformulation d'un nom, explication métier (elle vit dans JIRA), récit de ticket, // given/when/then, code commenté. Charger le skill claude-prose (tool Skill) pour le détail, et relire ses propres lignes '+' avant push."
}

skills_for() {  # $1 = chemin -> csv de skills requis
  local p="$1" req=""
  case "$p" in
    *.vue)                      req="vue-best-practices,malt-frontend-conventions" ;;
    *.uispec.ts)                req="malt-frontend-integration-tests" ;;
    *.spec.ts|*.spec.tsx)       req="malt-frontend-unit-tests" ;;
    *.avdl)                     req="malt-shared-broker-avro" ;;
  esac
  case "$p" in
    *-api-contract/*.yaml|*-api-contract/*.yml) req="malt-api-contracts" ;;
    *changelog*.xml|*changelog*.yaml|*db/migration/*) req="malt-postgresql-migrations" ;;
  esac
  case "$p" in
    *Test.kt|*Test.java|*IT.kt|*/src/test/*) req="${req:+$req,}malt-backend-testing" ;;
  esac
  case "$p" in
    */erp/accounting*|*/erp/netsuite*) req="${req:+$req,}malt-accounting-domain" ;;
  esac
  printf '%s' "$req"
}

case "$TOOL" in
  Edit|Write|NotebookEdit)
    fp="$(gate_field tool_input file_path)"
    [[ -n "$fp" ]] || fp="$(gate_field tool_input notebook_path)"
    case "$fp" in "$MAIN_REPO"/*|"$WT_ROOT"/*) : ;; *) exit 0 ;; esac
    req="$(skills_for "$fp")"
    [[ -n "$req" ]] && need "$req" "édition de $(basename "$fp")"
    prose "$fp"
    ;;
  Bash)
    gate_load_cmd
    printf '%s' "$CMD_CODE" | grep -Eq 'sed +-i|perl +-[a-z]*i|>>?[[:space:]]*[^ ;&|]*\.(kt|java|ts|tsx|vue|yaml|yml|xml|avdl)' || exit 0
    for f in $(printf '%s' "$CMD_CODE" | grep -oE '[^ "'"'"';&|>]+\.(kt|java|ts|tsx|vue|yaml|yml|xml|avdl)' | sort -u); do
      case "$f" in "$MAIN_REPO"/*|"$WT_ROOT"/*) : ;; *) continue ;; esac
      req="$(skills_for "$f")"
      [[ -n "$req" ]] && need "$req" "écriture Bash dans $(basename "$f")"
      prose "$f"
    done
    ;;
  Grep|Glob)
    [[ -n "$($ST get preanalysis)" ]] && exit 0
    tgt="$(gate_field tool_input path)"
    case "$tgt" in "$MAIN_REPO"*|"$WT_ROOT"*|"") : ;; *) exit 0 ;; esac
    gate_deny preanalysis "exploration du monorepo Malt sans PRÉ-ANALYSE. CLAUDE.md § CONTEXTE MONOREPO : avant d'explorer (structure, build, où vit un domaine, conventions) -> accounting/NetSuite = skill malt-accounting-domain ; sinon note Obsidian [[Monorepo Malt - Carte technique]] via /obsidian (+ [[Architecture Backend]] / [[Architecture Frontend Nuxt]]). Réutiliser cette pré-analyse au lieu de re-scanner. L'exigence se lève dès qu'un de ces deux est chargé."
    ;;
esac
exit 0
