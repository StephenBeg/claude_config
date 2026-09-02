#!/usr/bin/env bash
# Stop — GATES DE FIN DE TOUR. C'est le SEUL endroit où une obligation « de fin »
# devient non sautable : le reste du temps, une étape finale oubliée ne coûte rien.
#
# Ce que le hook exige, dans cet ordre :
#   1. end-gate        MR mergée -> /end réellement écrit dans le log du jour
#   2. closing-block   push -> BLOC DE CLÔTURE dans la réponse (CLAUDE.md § GIT WORKFLOW)
#   3. jira-status     MR mergée -> ticket JIRA en « To Validate » (/dev step 14)
#   4. livrable        MR mergée + /end -> tableau LIVRABLE FINAL avec Tradeoffs
#
# Chaque preuve est LUE (log du jour, transcript, API JIRA), jamais supposée.
# Garde-fous : jamais de boucle (stop_hook_active), jamais en heures calmes
# (débloquer la fin de tour la nuit = ré-invoquer Claude, interdit par CLAUDE.md).
set -uo pipefail

ST="python3 $HOME/.claude/scripts/wf-state.py"
TAB="$HOME/.claude/scripts/cmux-tab.sh"
. "$HOME/.claude/scripts/wf-gates-lib.sh"

input=$(cat)
looping=$(printf '%s' "$input" | python3 -c \
  'import sys,json;print("1" if json.load(sys.stdin).get("stop_hook_active") else "")' 2>/dev/null) || looping=""
[[ -n "$looping" ]] && exit 0   # déjà relancé une fois : ne jamais boucler

transcript=$(printf '%s' "$input" | python3 -c \
  'import sys,json;print(json.load(sys.stdin).get("transcript_path","") or "")' 2>/dev/null) || transcript=""

# Dernier message d'assistant du transcript (ce que l'utilisateur vient de lire).
last_msg() {
  [[ -n "$transcript" && -r "$transcript" ]] || return 0
  python3 - "$transcript" <<'PY' 2>/dev/null
import json, sys
txt = ""
for line in open(sys.argv[1], errors="ignore"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") != "assistant":
        continue
    content = (d.get("message") or {}).get("content") or []
    if isinstance(content, list):
        t = " ".join(c.get("text", "") for c in content
                     if isinstance(c, dict) and c.get("type") == "text")
        if t.strip():
            txt = t
print(txt[-6000:])
PY
}

block() {  # $1 = message impératif -> refuse la fin de tour
  gate_is_quiet_hours && exit 0
  python3 -c 'import json,sys;print(json.dumps({"decision":"block","reason":sys.argv[1]}))' "$1"
  exit 0
}

iid="$($ST get mr)"
merged="$($ST get merged)"
ticket="$($ST get ticket)"
today="$HOME/tmp/$(date +%F).md"
tomorrow="$HOME/tmp/$(date -v+1d +%F).md"

# --------------------------------------------------------------------------- #
# 1. /end après merge — la preuve est le log du jour, pas une déclaration.
# --------------------------------------------------------------------------- #
if [[ -n "$iid" && -n "$merged" && -z "$($ST get end_done)" ]]; then
  if grep -qE "(!|merge_requests/)$iid\b" "$today" "$tomorrow" 2>/dev/null; then
    $ST set end_done=1
    [[ "$($ST get phase)" == "END" ]] || "$TAB" phase END >/dev/null 2>&1
  elif [[ "$(gate_mode end-gate)" != "off" ]]; then
    block "MR !$iid mergée mais /end n'a pas été fait : aucune trace de la MR dans $today. Ne pas clore. Lancer /end maintenant (log du jour + lien MR + lien JIRA + tradeoffs en commentaire JIRA en anglais), vérifier le statut JIRA 'To Validate', puis poser le header [END]."
  fi
fi

# --------------------------------------------------------------------------- #
# 2. BLOC DE CLÔTURE après un push — exigé une fois, sur le tour du push.
# --------------------------------------------------------------------------- #
if [[ -n "$($ST get pushed_turn)" && "$(gate_mode closing-block)" != "off" ]]; then
  msg="$(last_msg)"
  $ST set pushed_turn=          # exigé une seule fois, quel que soit l'issue
  if ! printf '%s' "$msg" | grep -qi 'Travail poussé sur'; then
    block "Un push a eu lieu ce tour et la réponse ne porte pas le BLOC DE CLÔTURE. CLAUDE.md § GIT WORKFLOW — obligatoire après TOUT push, terminer la réponse par :
Travail poussé sur : <branche>
Description MR :
<contenu généré par /gitlab-resume>"
  fi
fi

# --------------------------------------------------------------------------- #
# 3. Statut JIRA après merge (/dev step 14) — vérifié contre l'API, pas supposé.
# --------------------------------------------------------------------------- #
if [[ -n "$merged" && -n "$ticket" && "$(gate_mode jira-status)" != "off" ]]; then
  if [[ -n "${ATLASSIAN_EMAIL:-}" && -n "${ATLASSIAN_API_TOKEN:-}" && -n "${ATLASSIAN_SITE:-}" ]]; then
    status=$(curl -s -m 20 -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" \
      "$ATLASSIAN_SITE/rest/api/3/issue/$ticket?fields=status" 2>/dev/null \
      | python3 -c 'import sys,json;print(((json.load(sys.stdin).get("fields") or {}).get("status") or {}).get("name",""))' 2>/dev/null) || status=""
    if [[ -n "$status" && "$status" != "To Validate" ]]; then
      block "MR !$iid mergée mais le ticket $ticket est en « $status » au lieu de « To Validate » (/dev step 14, lu à l'instant via l'API JIRA). Transitionner le ticket (skill /jira, délégable en haiku) avant de clore."
    fi
  fi
fi

# --------------------------------------------------------------------------- #
# 4. LIVRABLE FINAL — le point Tradeoffs est obligatoire (commons § LIVRABLE).
# --------------------------------------------------------------------------- #
if [[ -n "$merged" && -n "$($ST get end_done)" && "$(gate_mode livrable)" != "off" ]]; then
  if [[ -z "$($ST get livrable_done)" ]]; then
    msg="$(last_msg)"
    $ST set livrable_done=1     # exigé une seule fois
    if ! printf '%s' "$msg" | grep -qi 'tradeoff'; then
      block "Fin de workflow d'implémentation sans LIVRABLE FINAL. Skill malt-workflow-commons § LIVRABLE FINAL : retourner le tableau JIRA / Statut JIRA / MR / /end / Obsidian / Tradeoffs / Résumé. Le point **Tradeoffs** est OBLIGATOIRE — lister les arbitrages non différenciants tranchés seul + rappel des décisions d'archi déjà validées par l'utilisateur. Un tradeoff différenciant qui apparaîtrait là sans avoir été validé AVANT = violation de la règle d'escalade."
    fi
  fi
fi

exit 0
