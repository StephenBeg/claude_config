#!/usr/bin/env bash
# cmux-tab.sh — manipule le titre de l'onglet (tab) cmux courant.
#
# Usage:
#   cmux-tab.sh set   "<titre>"          # renomme le tab courant
#   cmux-tab.sh phase "[PLAN]" "<3-4 mots>"  # prefixe + résumé ([PLAN]|[IMPL]|[MR]|[END]|[ASK])
#   cmux-tab.sh get                      # affiche le ref de surface courant
#   cmux-tab.sh spawn "<prompt>" ["<titre>"] ["<cwd>"] ["<status_dir>"] ["<ticket>"]
#                                        # nouvel onglet -> claude (opus 4.8) + prompt
#                                        # cwd défaut = ~/Documents/projects/malt
#                                        # status_dir+ticket (optionnels, ORCHESTRATION) :
#                                        #   injecte un préambule "report ton statut" dans le
#                                        #   prompt et écrit l'état SPAWNED. Voir report/await.
#
# --- ORCHESTRATION plan->dev (statut via fichiers, cf. CLAUDE.md WORKFLOW DE PLAN) ---
#   cmux-tab.sh report <status_dir> <ticket> <STATE> ["<detail>"]
#                                        # (côté ENFANT) écrit atomiquement l'état du ticket.
#                                        # STATE ∈ SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|BLOCKED
#   cmux-tab.sh await  <status_dir> [--timeout <sec>] [--interval <sec>] <ticket> [<ticket>...]
#                                        # (côté ORCHESTRATEUR) bloque jusqu'à ce que TOUS les
#                                        # tickets soient MERGED. Sort en erreur si l'un passe
#                                        # BLOCKED (code 3) ou timeout (code 2). À lancer en
#                                        # BACKGROUND (le harness re-réveille Claude à la sortie).
#   cmux-tab.sh status <status_dir> [<ticket>]
#                                        # affiche l'état courant (tous les tickets, ou un seul).
#
# Le tab cmux est piloté par défaut par l'OSC de l'agent ; ce script force
# un titre explicite via la CLI cmux (socket local, pas de password requis).
#
# Ciblage workspace/onglet : on résout TOUJOURS depuis $CMUX_SURFACE_ID (UUID de
# surface stable) via `identify --surface`. On n'utilise JAMAIS $CMUX_WORKSPACE_ID :
# c'est un UUID qui peut être périmé et faire échouer new-surface avec
# "Workspace not found" (le short ref workspace:N, lui, bouge quand l'utilisateur
# réordonne ses workspaces). Voir resolve_own_workspace().

set -euo pipefail

CLI="/Applications/cmux.app/Contents/Resources/bin/cmux"

if [[ ! -x "$CLI" ]]; then
  echo "cmux CLI introuvable: $CLI" >&2
  exit 1
fi

# Renomme l'onglet de CE process (Claude) — ciblé par l'UUID stable
# $CMUX_SURFACE_ID, TOTALEMENT INDÉPENDANT du focus utilisateur.
#
# Ce qui NE marche PAS (tout testé) :
# - short ref `surface:N` : RELATIF au contexte focusé → `surface:1` résout vers
#   l'onglet que l'utilisateur regarde → renomme le MAUVAIS onglet.
# - `rename-tab --surface <UUID>` sans contexte → "Tab not found".
# - `--window <ref|UUID>` : la window focus renumérote quand l'utilisateur navigue
#   → "Surface not found in window".
# - les UUID d'env `CMUX_WORKSPACE_ID`/`CMUX_TAB_ID` ne résolvent PAS vers le vrai
#   workspace de Claude (fallback silencieux sur le workspace focusé).
# - l'UUID de surface n'est exposé dans AUCUN `list-panels --json` → pas de mapping.
#
# Ce qui marche : `rename-tab --surface $CMUX_SURFACE_ID --workspace <ws-shortref>`
# quand <ws-shortref> est LE workspace de Claude. Un mauvais workspace échoue
# proprement ("Tab not found") SANS rien renommer (vérifié). Donc on itère tous
# les workspaces : seul celui de Claude réussit. Focus-safe par construction.
# Résout le workspace de CLAUDE (short ref `workspace:N`) de façon INDÉPENDANTE
# DU FOCUS utilisateur. Identité fiable = $CMUX_WORKSPACE_ID (UUID env, stable,
# propre au process Claude).
#
# ATTENTION — piège vérifié : `identify --surface <uuid>` IGNORE l'argument et
# renvoie toujours le bloc `focused` (= workspace AU FOCUS utilisateur). L'utiliser
# faisait ouvrir/renommer les surfaces dans le MAUVAIS workspace dès que le focus
# bougeait. NE PAS s'en servir pour résoudre le workspace.
#
# Le short ref `workspace:N` change quand l'utilisateur réordonne ses workspaces →
# on le RE-MAPPE à chaque appel depuis l'UUID stable via `workspace list --id-format
# both` (grep de l'UUID → colonne workspace:N). Focus-safe + reorder-safe.
resolve_own_workspace() {
  local ws
  if [[ -n "${CMUX_WORKSPACE_ID:-}" ]]; then
    ws="$("$CLI" workspace list --id-format both 2>/dev/null \
      | grep -F "$CMUX_WORKSPACE_ID" | grep -o 'workspace:[0-9]*' | head -1)"
    [[ -n "$ws" ]] && { printf '%s\n' "$ws"; return 0; }
  fi
  # Fallback ultime = workspace [selected] (suit le focus, moins fiable).
  ws="$("$CLI" workspace list 2>/dev/null | grep '\[selected\]' | grep -o 'workspace:[0-9]*' | head -1)"
  [[ -n "$ws" ]] && { printf '%s\n' "$ws"; return 0; }
  return 1
}

rename_own_tab() {
  local title="$1" ws own
  [[ -n "${CMUX_SURFACE_ID:-}" ]] || { echo "CMUX_SURFACE_ID absent — impossible de cibler l'onglet de Claude" >&2; return 1; }
  # Fast path: workspace résolu directement depuis la surface.
  own="$(resolve_own_workspace 2>/dev/null || true)"
  if [[ -n "$own" ]] && CMUX_QUIET=1 "$CLI" rename-tab --surface "$CMUX_SURFACE_ID" --workspace "$own" "$title" 2>/dev/null; then
    return 0
  fi
  # Fallback: sonder chaque workspace (seul celui de Claude réussit).
  for ws in $("$CLI" workspace list 2>/dev/null | grep -o 'workspace:[0-9]*'); do
    if CMUX_QUIET=1 "$CLI" rename-tab --surface "$CMUX_SURFACE_ID" --workspace "$ws" "$title" 2>/dev/null; then
      return 0
    fi
  done
  echo "cmux-tab: onglet de Claude (surface $CMUX_SURFACE_ID) introuvable dans les workspaces" >&2
  return 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  get)
    printf 'surface %s\n' "${CMUX_SURFACE_ID:-?}"
    ;;
  set)
    title="${1:?titre requis}"
    rename_own_tab "$title"
    ;;
  phase)
    prefix="${1:?prefix requis (PLAN|IMPL|TO REVIEW|END)}"
    summary="${2:?résumé requis}"
    rename_own_tab "$prefix $summary"
    ;;
  spawn)
    prompt="${1:?prompt requis}"
    title="${2:-claude opus}"
    # cwd par défaut = repo principal malt (JAMAIS $PWD, qui peut être un worktree
    # du Claude appelant). Un agent de dev fraîchement spawné DOIT démarrer dans
    # ~/Documents/projects/malt pour créer son propre worktree (cf. GIT WORKFLOW).
    cwd="${3:-$HOME/Documents/projects/malt}"
    status_dir="${4:-}"
    ticket="${5:-}"
    model="claude-opus-4-8"
    # ORCHESTRATION : si status_dir+ticket fournis, préfixer le prompt d'un
    # préambule qui apprend à l'enfant à reporter son statut à l'orchestrateur.
    # DEPENDS_ON n'est PAS transmis à l'enfant (bookkeeping orchestrateur only).
    if [[ -n "$status_dir" && -n "$ticket" ]]; then
      preamble="[ORCHESTRATION CMUX] Un orchestrateur de plan t'a lancé et attend tes statuts.
STATUS_DIR=$status_dir TICKET=$ticket
À CHAQUE transition de phase du WORKFLOW DE DEV, exécute :
  ~/.claude/scripts/cmux-tab.sh report $status_dir $ticket <STATE> \"<detail>\"
STATES : IN_PROGRESS (worktree créé) | MR_OPEN (MR créée — mets le lien MR en detail) | MERGED (MR mergée par l'humain — lien MR en detail) | BLOCKED (blocage nécessitant l'humain — raison en detail).
Ne clos JAMAIS ta tâche sans avoir reporté MERGED (ou BLOCKED). L'orchestrateur en dépend pour déclencher les tickets suivants.
---
"
      prompt="${preamble}${prompt}"
    fi
    # Onglet (surface) dans le WORKSPACE DE CLAUDE (résolu depuis la surface
    # stable, pas depuis $CMUX_WORKSPACE_ID qui est un UUID potentiellement
    # périmé → "Workspace not found"). --workspace explicite est requis : sans
    # ça, new-surface retombe sur le workspace focused → mauvais workflow CMUX.
    ws="$(resolve_own_workspace)" || { echo "cmux-tab: workspace de Claude introuvable (surface ${CMUX_SURFACE_ID:-?})" >&2; exit 1; }
    out="$(CMUX_QUIET=1 "$CLI" new-surface --type terminal \
      --workspace "$ws" \
      --working-directory "$cwd" --focus true 2>&1)"
    surface="$(printf '%s' "$out" | grep -o 'surface:[0-9]*' | head -1)"
    [[ -n "$surface" ]] || { echo "création surface échouée: $out" >&2; exit 1; }
    "$CLI" rename-tab --surface "$surface" "$title" >/dev/null 2>&1 || true
    # printf %q rend le prompt sûr pour le shell (espaces, quotes, etc.).
    runcmd="claude --model $model $(printf '%q' "$prompt")"
    sleep 1  # laisser le shell du terminal démarrer
    CMUX_QUIET=1 "$CLI" send --surface "$surface" "$runcmd"$'\n'
    if [[ -n "$status_dir" && -n "$ticket" ]]; then
      "$0" report "$status_dir" "$ticket" SPAWNED "surface=$surface" >/dev/null
    fi
    echo "$surface"
    ;;

  # ---- ORCHESTRATION : statut plan<->dev via fichiers ----
  report)
    dir="${1:?status_dir requis}"
    ticket="${2:?ticket requis}"
    state="${3:?state requis (SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|BLOCKED)}"
    detail="${4:-}"
    case "$state" in
      SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|BLOCKED) ;;
      *) echo "state invalide: $state (attendu SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|BLOCKED)" >&2; exit 2 ;;
    esac
    mkdir -p "$dir"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="$(mktemp "$dir/.$ticket.XXXXXX")"
    printf '%s|%s|%s\n' "$state" "$ts" "$detail" > "$tmp"
    mv -f "$tmp" "$dir/$ticket.status"   # écriture atomique (rename)
    echo "$ticket -> $state"
    ;;

  await)
    dir="${1:?status_dir requis}"; shift
    timeout=7200; interval=20
    tickets=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --timeout) timeout="$2"; shift 2 ;;
        --interval) interval="$2"; shift 2 ;;
        *) tickets+=("$1"); shift ;;
      esac
    done
    [[ ${#tickets[@]} -gt 0 ]] || { echo "await: au moins un ticket requis" >&2; exit 2; }
    seen=" "   # liste des tickets déjà annoncés MERGED (bash 3.2 friendly, pas d'assoc array)
    elapsed=0
    while :; do
      all_done=1
      for t in "${tickets[@]}"; do
        f="$dir/$t.status"
        if [[ -f "$f" ]]; then
          st="$(cut -d'|' -f1 "$f" 2>/dev/null || true)"
          case "$st" in
            MERGED) [[ "$seen" == *" $t "* ]] || { echo "✓ $t MERGED"; seen="$seen$t "; } ;;
            BLOCKED) echo "✗ $t BLOCKED — $(cat "$f")" >&2; exit 3 ;;
            *) all_done=0 ;;
          esac
        else
          all_done=0
        fi
      done
      [[ $all_done -eq 1 ]] && { echo "all MERGED: ${tickets[*]}"; exit 0; }
      sleep "$interval"; elapsed=$((elapsed + interval))
      [[ $elapsed -ge $timeout ]] && { echo "await timeout ${timeout}s (en attente: ${tickets[*]})" >&2; exit 2; }
    done
    ;;

  status)
    dir="${1:?status_dir requis}"
    ticket="${2:-}"
    if [[ -n "$ticket" ]]; then
      f="$dir/$ticket.status"
      [[ -f "$f" ]] && { printf '%s ' "$ticket"; cat "$f"; } || echo "$ticket (aucun statut)"
    else
      shopt -s nullglob
      for f in "$dir"/*.status; do
        printf '%s\t' "$(basename "$f" .status)"; cat "$f"
      done
    fi
    ;;
  *)
    echo "Usage: cmux-tab.sh set \"<titre>\" | phase <PREFIX> \"<résumé>\" | get | spawn \"<prompt>\" [titre] [cwd] [status_dir] [ticket] | report <dir> <ticket> <STATE> [detail] | await <dir> [--timeout s] [--interval s] <ticket...> | status <dir> [ticket]" >&2
    exit 2
    ;;
esac
