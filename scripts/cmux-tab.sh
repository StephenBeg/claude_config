#!/usr/bin/env bash
# cmux-tab.sh — manipule le titre de l'onglet (tab) cmux courant.
#
# Usage:
#   cmux-tab.sh set   "<titre>"          # renomme le tab courant
#   cmux-tab.sh phase "[PLAN]" "<3-4 mots>"  # prefixe + résumé ([PLAN]|[IMPL]|[MR]|[END]|[ASK])
#   cmux-tab.sh get                      # affiche le ref de surface courant
#   cmux-tab.sh spawn "<prompt>" ["<titre>"] ["<cwd>"]
#                                        # nouvel onglet -> claude (opus 5) + prompt
#                                        # cwd défaut = ~/Documents/projects/malt
#                                        # SPAWN = LIEN SEUL : aucun préambule injecté. Pour une
#                                        #   surface orchestrée, le prompt de départ complet vit
#                                        #   dans le header de l'inbox de la surface (voir pair-init) ;
#                                        #   le prompt passé ici n'est qu'un pointeur
#                                        #   "Lis <inbox_file> et exécute…". Le report SPAWNED et
#                                        #   le câblage juge/bus sont gérés par l'ORCHESTRATEUR.
#
# --- RÉVEIL D'UNE AUTRE SURFACE (PUSH ACTIF) ---
#   cmux-tab.sh wake [--force] <surface> "<message>"
#                                        # injecte <message> comme prompt dans la surface cible
#                                        # (UUID ou surface:N) et le SOUMET. Réveille un Claude au
#                                        # repos ; MET EN FILE si occupé (jamais de tour corrompu).
#                                        # Refuse d'envoyer en HEURES CALMES 20h-7h (code 4) sauf
#                                        # --force. Best-effort : un échec n'est jamais fatal.
#
# --- ORCHESTRATION orchestrator->dev/plan (statut via fichiers, cf. commande /orchestrator) ---
#   cmux-tab.sh report [--notify <orch_surface>] <status_dir> <ticket> <STATE> ["<detail>"]
#                                        # --notify = écrit le statut ET réveille l'orchestrateur.
#                                        # C'est le mode NOMINAL en orchestré (remplace le polling).
#                                        # (côté ENFANT) écrit atomiquement l'état du ticket.
#                                        # STATE ∈ SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|PLANNED|BLOCKED
#   cmux-tab.sh await  <status_dir> [--timeout <sec>] [--interval <sec>] [--terminal <STATE>] <ticket> [<ticket>...]
#                                        # (côté ORCHESTRATEUR) bloque jusqu'à ce que TOUS les
#                                        # tickets atteignent l'état terminal (défaut MERGED ;
#                                        # --terminal PLANNED pour des tickets-planner). Sort en
#                                        # erreur si l'un passe BLOCKED (code 3) ou timeout (code 2).
#                                        # LEGACY / SECOURS — même réserve que await-note : ces
#                                        # process background sont tués sans garantie. Le réveil
#                                        # nominal est désormais le PUSH (`report --notify`).
#   cmux-tab.sh status <status_dir> [<ticket>]
#                                        # affiche l'état courant (tous les tickets, ou un seul).
#
# --- BUS D'ÉCHANGE PAR INBOX de surface (skill malt-surface-exchange) ---
# Un fichier INBOX par SURFACE (nœud) ; chaque surface n'écoute QUE son propre
# fichier. Chemins déterministes sous
# /Users/stephenbegot/claude-exchange-llm/<WORKFLOW>/ : _inbox/orchestrator.md,
# _inbox/judge.md, <T>.md. Requête → inbox du destinataire ; réponse → inbox du
# demandeur (REPLY_TO). Les primitives ci-dessous sont GÉNÉRIQUES sur fichier —
# c'est le skill qui porte les conventions de chemin et de routage.
#   cmux-tab.sh pair-init <inbox_file>   (header lu sur STDIN)
#                                        # crée l'inbox : header immuable (prompt de départ pour
#                                        # une surface, ou rôle du canal pour l'inbox orchestrateur
#                                        # /juge — écrit UNE FOIS par l'orchestrateur) + marqueur
#                                        # de journal append-only. Refuse d'écraser un fichier
#                                        # déjà initialisé. (nom historique conservé.)
#   cmux-tab.sh note [--notify <surface>] <inbox_file> <LABEL> <EVENT> ["<detail>"]
#                                        # append atomique (lock) d'une entrée immuable
#                                        # horodatée dans le journal d'un inbox. --notify réveille
#                                        # le propriétaire de l'inbox (push actif).
#   cmux-tab.sh await-note --match <regex> [--timeout s] [--interval s] <inbox_file>...
#                                        # LEGACY / SECOURS. bloque jusqu'à ce qu'une ligne matche
#                                        # (à lancer en BACKGROUND). Le harness TUE régulièrement
#                                        # ces process (pas de garantie de survie) — ne plus s'en
#                                        # servir comme mécanisme de réveil PRINCIPAL : préférer
#                                        # `report --notify` / `note --notify` (push) + le filet
#                                        # cron de l'orchestrateur. Conservé pour compatibilité.
#                                        # Sert au loop /dev|/plan <-> /judge (verdict, chacun sur
#                                        # SON inbox) et à l'écoute du juge/orchestrateur (leur
#                                        # inbox fixe unique). Accepte plusieurs fichiers mais le
#                                        # modèle inbox n'en passe normalement qu'UN.
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

# ---------------------------------------------------------------------------
# RÉVEIL PAR PUSH ACTIF (`wake`) — corrige le bug « l'orchestrateur ne se
# réveille pas ». Vérifié empiriquement (2026-08-17) :
#  - `cmux send --surface <UUID|surface:N> "<texte>"` écrit dans le TTY de la
#    surface ; ciblage par UUID OK, SANS --workspace, SANS focus.
#  - Un Claude AU REPOS est réveillé (~4 s) : le texte devient un prompt soumis.
#  - Un Claude OCCUPÉ met le message EN FILE ("Press up to edit queued
#    messages") — ni perdu, ni intercalé, ni tour corrompu.
#  - PIÈGE : un texte MULTI-LIGNE n'est PAS soumis par son \n final (newline
#    soft). Donc on envoie TOUJOURS un texte mono-ligne, puis un `send-key
#    enter` séparé. C'est la seule forme fiable dans les deux cas.
# Un `wake` qui échoue n'est JAMAIS fatal : la récupération de référence reste
# le RE-SCAN idempotent depuis la source de vérité (JIRA + git + STATUS_DIR).
#
# HEURES CALMES 20h–7h (CLAUDE.md) : un `wake` RÉ-INVOQUE Claude → interdit
# dans la plage. On n'envoie rien et on sort en code 4 (l'appelant continue) ;
# l'information n'est pas perdue (elle est déjà dans le statut/inbox), seul le
# réveil est différé au redémarrage manuel du matin. `--force` outrepasse.
quiet_hours_now() {
  local h; h=$(date +%H)
  [[ 10#$h -ge 20 || 10#$h -lt 7 ]]
}

# Cycle de vie de l'agent d'une surface, lu dans l'index tenu par cmux :
# surfaceUUID -> sessionId -> agentLifecycle (idle|running|needsInput|unknown).
# Renvoie la valeur, ou "unknown" si non résoluble (surface:N, index absent…).
surface_lifecycle() {
  python3 - "$1" <<'PY' 2>/dev/null || echo unknown
import json,os,sys
try:
    d=json.load(open(os.path.expanduser('~/.cmuxterm/claude-hook-sessions.json')))
    sid=d['activeSessionsBySurface'][sys.argv[1].upper()]['sessionId']
    print(d['sessions'][sid].get('agentLifecycle','unknown'))
except Exception:
    print('unknown')
PY
}

# wake_surface <surface> <message-mono-ligne>
wake_surface() {
  local surface="$1" msg="$2" i
  # aplatir : tout \n / \r interne casserait la soumission.
  msg="$(printf '%s' "$msg" | tr '\n\r\t' '   ')"
  # ATTENDRE QUE LA CIBLE SOIT POSÉE (max ~40 s). Un envoi pile pendant la
  # bascule de fin de tour peut être PERDU (observé : le texte n'atteint ni la
  # file ni le prompt). Un agent `running` met bien le message en file, mais on
  # évite quand même la fenêtre de transition. `unknown` → on envoie direct.
  for i in $(seq 1 20); do
    [[ "$(surface_lifecycle "$surface")" != "running" ]] && break
    sleep 2
  done
  for i in 1 2 3; do
    if CMUX_QUIET=1 "$CLI" send --surface "$surface" "$msg" >/dev/null 2>&1 \
       && CMUX_QUIET=1 "$CLI" send-key --surface "$surface" enter >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
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
    prefix="${1:?prefix requis (MAIN|PLAN|IMPL|PIPE|MR|ASK|BLOCK|WAIT|CLEAN|END)}"
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
    # Modèle des surfaces spawnées. Défaut = Opus 5 fenêtre 1M : les surfaces
    # orchestrées portent un contexte long (ticket + ADR + code + rounds de juge)
    # et compressaient trop en 200k. Surchargeable ponctuellement via
    # CMUX_SPAWN_MODEL=... cmux-tab.sh spawn ...
    # ATTENTION : l'ID contient des crochets ; il DOIT rester quoté dans la
    # commande envoyée au terminal (zsh globerait `[1m]` → "no matches found").
    model="${CMUX_SPAWN_MODEL:-claude-opus-5[1m]}"
    # SPAWN = LIEN SEUL (skill malt-surface-exchange § SPAWN = LIEN SEUL) :
    # ce script ne construit AUCUN préambule. Le prompt de départ complet d'une
    # surface orchestrée vit dans le header de son inbox, écrit par
    # l'orchestrateur via `pair-init`. Le prompt passé ici n'est qu'un pointeur
    # ("Lis <fichier> et exécute…"). Le report SPAWNED + le câblage du bus/juge
    # sont désormais gérés par l'orchestrateur lui-même, hors de ce spawn.
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
    # Passage ROBUSTE du prompt : on écrit le prompt dans un fichier temporaire et
    # on le relit dans le shell cible via "$(cat FICHIER)". Évite tout piège de
    # quoting/encodage quand le prompt contient des guillemets simples, des
    # apostrophes, des retours à la ligne ou de l'unicode.
    # Sous $HOME, JAMAIS /tmp (CLAUDE.md § FICHIERS HORS REPO) : ce fichier est
    # relu par le shell de la surface cible APRÈS le retour de cette commande —
    # une purge macOS de /tmp entre les deux ferait démarrer l'agent sans prompt.
    prompt_dir="$HOME/tmp/scratch/cmux-prompts"; mkdir -p "$prompt_dir"
    prompt_file="$(mktemp "$prompt_dir/cmux-prompt.XXXXXX")"
    printf '%s' "$prompt" > "$prompt_file"
    runcmd="claude --model '$model' \"\$(cat '$prompt_file')\""
    sleep 1  # laisser le shell du terminal démarrer
    CMUX_QUIET=1 "$CLI" send --surface "$surface" "$runcmd"$'\n'
    echo "$surface"
    ;;

  # ---- RÉVEIL PAR PUSH ACTIF ----
  wake)
    # wake [--force] <surface> "<message>"
    force=0
    if [[ "${1:-}" == "--force" ]]; then force=1; shift; fi
    surface="${1:?surface requise (UUID ou surface:N)}"
    msg="${2:?message requis}"
    if [[ $force -eq 0 ]] && quiet_hours_now; then
      echo "wake: heures calmes (20h–7h) — réveil de $surface NON envoyé (récupération au re-scan matinal)" >&2
      exit 4
    fi
    if wake_surface "$surface" "$msg"; then
      echo "wake -> $surface"
    else
      echo "wake: échec d'envoi vers $surface (non fatal — le re-scan rattrape)" >&2
      exit 1
    fi
    ;;

  # ---- ORCHESTRATION : statut plan<->dev via fichiers ----
  report)
    # report [--notify <orch_surface>] <dir> <ticket> <STATE> [detail]
    notify=""
    if [[ "${1:-}" == "--notify" ]]; then notify="${2:?--notify requiert une surface}"; shift 2; fi
    dir="${1:?status_dir requis}"
    ticket="${2:?ticket requis}"
    state="${3:?state requis (SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|PLANNED|BLOCKED)}"
    detail="${4:-}"
    case "$state" in
      SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|PLANNED|BLOCKED) ;;
      *) echo "state invalide: $state (attendu SPAWNED|IN_PROGRESS|MR_OPEN|MERGED|PLANNED|BLOCKED)" >&2; exit 2 ;;
    esac
    case "$dir" in
      /tmp/*|/private/tmp/*|/var/folders/*)
        echo "report: ATTENTION — STATUS_DIR sous /tmp ($dir) : macOS le PURGE. Utiliser /Users/stephenbegot/claude-exchange-llm/<WORKFLOW>/_status" >&2 ;;
    esac
    mkdir -p "$dir"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="$(mktemp "$dir/.$ticket.XXXXXX")"
    printf '%s|%s|%s\n' "$state" "$ts" "$detail" > "$tmp"
    mv -f "$tmp" "$dir/$ticket.status"   # écriture atomique (rename)
    echo "$ticket -> $state"
    # PUSH ACTIF : réveiller l'orchestrateur. Best-effort — un échec (ou les
    # heures calmes) ne compromet JAMAIS le statut, déjà écrit sur disque.
    if [[ -n "$notify" ]]; then
      # Pas de --force, même sur BLOCKED : les HEURES CALMES priment (CLAUDE.md).
      if quiet_hours_now; then
        echo "wake: heures calmes — réveil différé (statut écrit, récupéré au re-scan matinal)" >&2
      else
        wake_surface "$notify" \
          "[CMUX-WAKE] $ticket -> $state${detail:+ ($detail)}. Re-scanne le DAG (STATUS_DIR=$dir) et déclenche les dépendants." \
          && echo "wake -> $notify" \
          || echo "wake: échec vers $notify (non fatal — le re-scan rattrape)" >&2
      fi
    fi
    ;;

  await)
    dir="${1:?status_dir requis}"; shift
    timeout=7200; interval=20; terminal=MERGED
    tickets=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --timeout) timeout="$2"; shift 2 ;;
        --interval) interval="$2"; shift 2 ;;
        --terminal) terminal="$2"; shift 2 ;;
        *) tickets+=("$1"); shift ;;
      esac
    done
    [[ ${#tickets[@]} -gt 0 ]] || { echo "await: au moins un ticket requis" >&2; exit 2; }
    case "$terminal" in
      MERGED|PLANNED) ;;
      *) echo "await: --terminal invalide: $terminal (attendu MERGED|PLANNED)" >&2; exit 2 ;;
    esac
    seen=" "   # liste des tickets déjà annoncés terminaux (bash 3.2 friendly, pas d'assoc array)
    elapsed=0
    while :; do
      all_done=1
      for t in "${tickets[@]}"; do
        f="$dir/$t.status"
        if [[ -f "$f" ]]; then
          st="$(cut -d'|' -f1 "$f" 2>/dev/null || true)"
          if [[ "$st" == "$terminal" ]]; then
            [[ "$seen" == *" $t "* ]] || { echo "✓ $t $terminal"; seen="$seen$t "; }
          elif [[ "$st" == "BLOCKED" ]]; then
            echo "✗ $t BLOCKED — $(cat "$f")" >&2; exit 3
          else
            all_done=0
          fi
        else
          all_done=0
        fi
      done
      [[ $all_done -eq 1 ]] && { echo "all $terminal: ${tickets[*]}"; exit 0; }
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
  # ---- BUS D'ÉCHANGE PAR INBOX de surface (skill malt-surface-exchange) ----
  pair-init)
    # pair-init <inbox_file>   (header lu sur STDIN)
    # Crée l'inbox : header (prompt de départ d'une surface, ou rôle du canal pour
    # l'inbox orchestrateur/juge — écrit UNE SEULE FOIS par le créateur =
    # l'orchestrateur) suivi du marqueur de journal append-only. Idempotent-safe :
    # refuse d'écraser un fichier déjà initialisé (le header est immuable).
    file="${1:?inbox_file requis}"
    if [[ -e "$file" ]]; then
      echo "pair-init: $file existe déjà (header immuable) — non réécrit" >&2
      exit 0
    fi
    mkdir -p "$(dirname "$file")"
    header="$(cat)"
    { printf '# INBOX — %s\n\n' "$(basename "$file" .md)"
      printf '%s\n\n' "$header"
      printf '## JOURNAL (append-only)\n'; } > "$file"
    echo "pair-init $file"
    ;;

  note)
    # note <inbox_file> <LABEL> <EVENT> [detail]
    # Append atomique (lock mkdir — PIPE_BUF macOS=512 insuffisant) d'une entrée
    # horodatée immuable dans le journal d'un inbox. JAMAIS d'édition ni de
    # suppression : le journal est append-only auditable.
    # note [--notify <surface>] <inbox_file> <LABEL> <EVENT> [detail]
    notify=""
    if [[ "${1:-}" == "--notify" ]]; then notify="${2:?--notify requiert une surface}"; shift 2; fi
    file="${1:?inbox_file requis}"
    label="${2:?surface label requis}"
    event="${3:?event requis}"
    detail="${4:-}"
    mkdir -p "$(dirname "$file")"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    lock="$file.lock"
    tries=0
    until mkdir "$lock" 2>/dev/null; do
      tries=$((tries+1)); [[ $tries -ge 200 ]] && { echo "note: lock timeout sur $file" >&2; break; }
      sleep 0.05
    done
    { printf '\n## %s — %s — %s\n' "$ts" "$label" "$event"; [[ -n "$detail" ]] && printf '%s\n' "$detail"; } >> "$file"
    rmdir "$lock" 2>/dev/null || true
    echo "$label -> $event"
    # PUSH ACTIF vers le propriétaire de l'inbox (best-effort, jamais fatal :
    # l'entrée est déjà sur disque, une lecture ultérieure la retrouve).
    if [[ -n "$notify" ]]; then
      if quiet_hours_now; then
        echo "wake: heures calmes — réveil différé (entrée écrite dans $file)" >&2
      else
        wake_surface "$notify" "[CMUX-WAKE] $label — $event. Relis ton inbox: $file" \
          && echo "wake -> $notify" \
          || echo "wake: échec vers $notify (non fatal)" >&2
      fi
    fi
    ;;

  await-note)
    # await-note --match <regex> [--timeout s] [--interval s] <inbox_file> [<inbox_file>...]
    # Bloque jusqu'à ce qu'une ligne matchant <regex> apparaisse dans l'UN des
    # fichiers. Sort 0 au match, 2 au timeout. Mécanisme de réveil ÉVÉNEMENTIEL
    # (calqué sur `await`) : à lancer en BACKGROUND, le harness re-réveille Claude
    # à la sortie. PAS de watch permanent — un await borné pendant un échange
    # actif. Modèle inbox : chaque surface l'appelle sur SON seul inbox.
    match=""; timeout=7200; interval=15
    files=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --match) match="$2"; shift 2 ;;
        --timeout) timeout="$2"; shift 2 ;;
        --interval) interval="$2"; shift 2 ;;
        *) files+=("$1"); shift ;;
      esac
    done
    [[ -n "$match" ]] || { echo "await-note: --match requis" >&2; exit 2; }
    [[ ${#files[@]} -gt 0 ]] || { echo "await-note: au moins un bus_file requis" >&2; exit 2; }
    elapsed=0
    while :; do
      for f in "${files[@]}"; do
        [[ -f "$f" ]] && grep -Eq "$match" "$f" && { echo "✓ match '$match' dans $f"; exit 0; }
      done
      sleep "$interval"; elapsed=$((elapsed + interval))
      [[ $elapsed -ge $timeout ]] && { echo "await-note timeout ${timeout}s (match '$match' absent)" >&2; exit 2; }
    done
    ;;

  *)
    echo "Usage: cmux-tab.sh set \"<titre>\" | phase <PREFIX> \"<résumé>\" | get | spawn \"<prompt>\" [titre] [cwd] | wake [--force] <surface> \"<message>\" | report [--notify <surface>] <dir> <ticket> <STATE> [detail] | await <dir> [--timeout s] [--interval s] [--terminal MERGED|PLANNED] <ticket...> | status <dir> [ticket] | pair-init <inbox_file> (header sur STDIN) | note <inbox_file> <LABEL> <EVENT> [detail] | await-note --match <regex> [--timeout s] [--interval s] <inbox_file...>" >&2
    exit 2
    ;;
esac
