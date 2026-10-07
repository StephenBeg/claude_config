#!/usr/bin/env bash
# Bibliothèque commune des GATES déterministes (PreToolUse).
#
# Pourquoi : une règle écrite dans CLAUDE.md ou dans un skill est du PROMPT —
# advisory, sautable. Seuls les hooks sont exécutés par le harness. Chaque règle
# "RÈGLE ABSOLUE" mécaniquement vérifiable est donc portée par un gate ici.
#
# Cran par gate, dans l'ordre de priorité :
#   1. WF_GATES_OFF=1                -> tout désactivé (kill switch global)
#   2. WF_GATE_<NOM>=block|warn|off  -> override d'environnement
#   3. ~/.claude/wf-gates.conf        -> <nom>=block|warn|off
#   4. block                          -> défaut
#
# block = exit 2 (appel refusé, stderr renvoyé au LLM) · warn = contexte injecté,
# appel autorisé · off = silence.
#
# INVARIANT : un gate ne doit JAMAIS casser la session sur une erreur interne.
# Toute impossibilité de décider = passe (exit 0), SAUF les gates marqués
# "fail closed" (merge : irréversible).

GATES_CONF="$HOME/.claude/wf-gates.conf"
MAIN_REPO="$HOME/Documents/projects/malt"
WT_ROOT="$HOME/worktrees/malt"
GLAB_PROJECT="maltcommunity/malt/apps/malt"
ST="python3 $HOME/.claude/scripts/wf-state.py"

# --- mode d'un gate -----------------------------------------------------------
gate_mode() {
  local name="$1" m="" var
  [[ -n "${WF_GATES_OFF:-}" ]] && { printf off; return 0; }
  var="WF_GATE_$(printf '%s' "$name" | tr '[:lower:]-' '[:upper:]_')"
  m="${!var:-}"
  if [[ -z "$m" && -r "$GATES_CONF" ]]; then
    m=$(sed -nE "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*([a-z]+).*/\1/p" "$GATES_CONF" 2>/dev/null | tail -1)
  fi
  case "$m" in block|warn|off) printf '%s' "$m" ;; *) printf block ;; esac
}

# --- sorties ------------------------------------------------------------------
gate_ctx() {   # contexte injecté, appel autorisé
  printf '%s' "$1" | python3 -c '
import sys, json
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": sys.stdin.read()}}))' 2>/dev/null
}

gate_deny() {  # $1 = nom du gate, $2 = message (impératif, avec la sortie de secours)
  case "$(gate_mode "$1")" in
    off)   return 0 ;;
    warn)  gate_ctx "GATE $1 — AVERTISSEMENT (mode warn, appel laissé passer) : $2"; return 0 ;;
    block) printf 'BLOQUÉ par le gate %s : %s\n' "$1" "$2" >&2; exit 2 ;;
  esac
}

# --- lecture du payload -------------------------------------------------------
# gate_field <clé...> : chemin dans le JSON du hook (INPUT doit être posé).
gate_field() {
  printf '%s' "${INPUT:-}" | python3 -c '
import sys, json
try:
    cur = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
for k in sys.argv[1:]:
    cur = cur.get(k) if isinstance(cur, dict) else None
print(cur if isinstance(cur, str) else ("" if cur is None else json.dumps(cur)))' "$@" 2>/dev/null
}

# Commande brute (une ligne) et commande NORMALISÉE (contenu des quotes vidé).
# La normalisée sert à détecter une INVOCATION ; la brute à inspecter un message.
# TROIS lectures de la même commande, à ne pas confondre — la confusion est la
# source n°1 de faux positifs :
#   CMD_TRUE  brute, heredocs INCLUS. Pour un contrôle de CONTENU qui doit voir
#             le corps d'un heredoc (message de commit : Claude Code compose ses
#             commits en heredoc, donc le Co-Authored-By y vit).
#   CMD_CODE  heredocs retirés, quotes gardées. Pour détecter un appel dont
#             l'argument vit entre quotes (URL d'API) et pour les redirections.
#   CMD       heredocs retirés + contenu des quotes vidé. Pour détecter une
#             INVOCATION (gate_invoked) : un fichier qui PARLE de `glab mr merge`
#             ne merge rien.
gate_load_cmd() {
  CMD_TRUE=$(gate_field tool_input command)
  CMD_CODE=$(printf '%s' "${INPUT:-}" | python3 "$HOME/.claude/scripts/wf-normcmd.py" --keep-quotes 2>/dev/null)
  CMD=$(printf '%s' "${INPUT:-}" | python3 "$HOME/.claude/scripts/wf-normcmd.py" 2>/dev/null)
  CMD_RAW="$CMD_CODE"
  CWD=$(gate_field cwd)
}

# invoqué = motif en tête de commande ou après un séparateur shell (pas une simple mention)
gate_invoked() { printf '%s' "${CMD:-}" | grep -Eq "(^|[;&|(] *)($1)"; }

# Répertoire effectif d'une commande git : `git -C <path>` gagne (c'est LUI le
# dépôt visé), sinon le dernier `cd <path>`, sinon le cwd du hook. Sans ça un
# `git -C ~/worktrees/... push` lancé depuis le repo principal serait attribué
# au repo principal -> faux positif garanti.
gate_effective_dir() {
  local d
  d=$(printf '%s' "$CMD_RAW" | grep -oE 'git +-C +[^ ;&|]+' | tail -1 | sed -E 's/.*-C +//' | tr -d '"'"'"'')
  if [[ -n "$d" ]]; then
    d="${d/#\~/$HOME}"
    [[ -d "$d" ]] && { printf '%s' "$d"; return 0; }
  fi
  d=$(printf '%s' "$CMD_RAW" | grep -oE '(^|[;&|(] *)cd +[^ ;&|]+' | tail -1 | sed -E 's/.*cd +//' | tr -d '"'"'"'')
  [[ -n "$d" ]] && d="${d/#\~/$HOME}"
  [[ -z "$d" ]] && d="$CWD"
  [[ -d "$d" ]] || d="$CWD"
  printf '%s' "$d"
}

gate_branch() { git -C "$1" branch --show-current 2>/dev/null; }

# WF_FAKE_HOUR : uniquement pour tester le gate (tests/gates_test.sh).
gate_is_quiet_hours() {
  local h; h="${WF_FAKE_HOUR:-$(date +%H)}"
  [[ 10#$h -ge 20 || 10#$h -lt 7 ]]
}

# --- preuve par ARTEFACT (second chemin, indépendant de SubagentStop) ---------
# Un gate doit rester levable même si l'événement de fin de sous-agent ne tire
# pas (sous-agent tué, session dont le snapshot de hooks ne le porte pas). Le
# compte rendu du sous-agent est alors la preuve : il n'existe qu'une fois le
# travail fini, et il n'est accepté que s'il est POSTÉRIEUR au lancement, sinon
# un verdict d'un round précédent présent dans la même inbox lèverait le gate.
gate_proof() {  # $1 = verdict-file|smoke-file, $2 = clé pending -> 0 si preuve fraîche
  local kind="$1" pend ckpt report since v
  pend="$($ST get "$2")"
  [[ -n "$pend" ]] || return 1
  if [[ "$2" == "judge_pending" ]]; then
    IFS='|' read -r ckpt report since <<<"$pend"
    [[ "$ckpt" == "plan-gate" ]] && return 1
  else
    IFS='|' read -r report since <<<"$pend"
  fi
  [[ -n "$report" && -r "$report" ]] || return 1
  v="$(python3 "$HOME/.claude/scripts/wf-signals.py" "$kind" "$report" "${since:-0}" 2>/dev/null)"
  case "$v" in OK|NEEDS_WORK|BOOTED_OK) return 0 ;; *) return 1 ;; esac
}
