#!/usr/bin/env bash
# cmux-wake-test.sh — TEST DE NON-RÉGRESSION du mécanisme de réveil de l'orchestrateur.
#
# Vérifie bout-en-bout, SANS AUCUNE INTERVENTION HUMAINE :
#   T1 (nominal)    : une surface enfant qui fait `report --notify` réveille une
#                     surface orchestrateur Claude AU REPOS, avec l'info de transition.
#   T2 (nominal)    : idem via `note --notify`.
#   T3 (adverse)    : si le réveil échoue (surface morte), le STATUT est quand même
#                     écrit et `report` sort 0 → aucune information perdue.
#   T4 (adverse)    : garde HEURES CALMES — `wake` n'envoie rien entre 20h et 7h (code 4).
#   T5 (compat)     : `report`/`await`/`note`/`status` sans les nouveaux flags marchent.
#
# Usage : ~/.claude/scripts/tests/cmux-wake-test.sh
# Durée : ~2 min. Crée une surface CMUX jouet et la ferme à la fin.
set -uo pipefail

CLI="/Applications/cmux.app/Contents/Resources/bin/cmux"
TAB="$HOME/.claude/scripts/cmux-tab.sh"
DIR="$HOME/tmp/cmux-wake-test"
SD="$DIR/_status"
FAIL=0
ok()   { echo "  ✓ $1"; }
ko()   { echo "  ✗ $1" >&2; FAIL=1; }

rm -rf "$DIR"; mkdir -p "$SD"

# --- bootstrap de la surface orchestrateur jouet -----------------------------
ws="$("$CLI" workspace list --id-format both 2>/dev/null | grep -F "${CMUX_WORKSPACE_ID:-__none__}" \
      | grep -o 'workspace:[0-9]*' | head -1)"
[[ -n "$ws" ]] || { echo "workspace introuvable (lancer depuis une surface CMUX)" >&2; exit 1; }
out="$(CMUX_QUIET=1 "$CLI" new-surface --type terminal --workspace "$ws" \
        --working-directory "$HOME/Documents/projects/malt" --focus false 2>&1)"
SREF="$(printf '%s' "$out" | grep -o 'surface:[0-9]*' | head -1)"
UUID="$("$CLI" tree --workspace "$ws" --id-format both 2>/dev/null \
        | grep -o "$SREF [0-9A-F-]\{36\}" | grep -o '[0-9A-F-]\{36\}' | head -1)"
[[ -n "$UUID" ]] || { echo "UUID de la surface jouet introuvable" >&2; exit 1; }
trap '"$CLI" close-surface --surface "$SREF" >/dev/null 2>&1 || true' EXIT
"$CLI" rename-tab --surface "$SREF" "TOY-ORCH (test)" >/dev/null 2>&1
echo "surface jouet: $SREF / $UUID"

P="Tu es un ORCHESTRATEUR JOUET pour un test de reveil. Regle unique: A CHAQUE FOIS que tu recois un message, tu ecris un NOUVEAU fichier $DIR/woke-\$(date +%s).txt contenant le texte exact du message recu, avec Bash echo. Puis tu ne fais RIEN dautre et tu attends. Ne pose aucune question."
pf="$(mktemp "$DIR/toyprompt.XXXX")"; printf '%s' "$P" > "$pf"
sleep 1
"$CLI" send --surface "$SREF" "claude --model claude-haiku-4-5-20251001 --permission-mode acceptEdits \"\$(cat '$pf')\"" >/dev/null
"$CLI" send-key --surface "$SREF" enter >/dev/null

echo "attente que l'orchestrateur jouet soit au repos…"
lifecycle() {
  python3 - "$UUID" <<'PY' 2>/dev/null || echo unknown
import json,os,sys
try:
    d=json.load(open(os.path.expanduser('~/.cmuxterm/claude-hook-sessions.json')))
    sid=d['activeSessionsBySurface'][sys.argv[1].upper()]['sessionId']
    print(d['sessions'][sid].get('agentLifecycle','unknown'))
except Exception:
    print('unknown')
PY
}
for _ in $(seq 1 60); do sleep 3; compgen -G "$DIR/woke-*.txt" >/dev/null && break; done
compgen -G "$DIR/woke-*.txt" >/dev/null || { echo "le Claude jouet n'a jamais démarré" >&2; exit 1; }
# … puis attendre un état RÉELLEMENT posé (le harness peut relancer un tour de
# suite après le premier) : 3 relevés non-`running` consécutifs.
stable=0
for _ in $(seq 1 40); do
  if [[ "$(lifecycle)" != "running" ]]; then stable=$((stable+1)); else stable=0; fi
  [[ $stable -ge 3 ]] && break
  sleep 2
done
echo "état de la surface jouet: $(lifecycle) (stable=$stable)"

count() { ls -1 "$DIR"/woke-*.txt 2>/dev/null | wc -l | tr -d ' '; }
last()  { cat "$(ls -1t "$DIR"/woke-*.txt | head -1)"; }
wait_new() { local b="$1" i; for i in $(seq 1 20); do sleep 3; [[ "$(count)" -gt "$b" ]] && return 0; done; return 1; }

# --- T1 : report --notify réveille l'orchestrateur au repos ------------------
echo "T1 — report --notify réveille un Claude au repos"
b="$(count)"
"$TAB" report --notify "$UUID" "$SD" TOY-1 MERGED "MR!99999 verte" >/dev/null
if wait_new "$b" && last | grep -q 'TOY-1 -> MERGED'; then
  ok "réveillé, transition transmise : $(last)"
else
  ko "pas de réveil ou info de transition perdue"
fi

# --- T2 : note --notify ------------------------------------------------------
echo "T2 — note --notify réveille le propriétaire de l'inbox"
"$TAB" pair-init "$DIR/TOY.md" <<<"header de test" >/dev/null 2>&1
b="$(count)"
"$TAB" note --notify "$UUID" "$DIR/TOY.md" "TOY[dev]" "STEP:mr" "MR ouverte" >/dev/null
if wait_new "$b" && last | grep -q 'STEP:mr'; then ok "réveillé : $(last)"; else ko "pas de réveil"; fi

# --- T3 (adverse) : réveil impossible → l'information reste sur disque -------
echo "T3 — surface morte : le statut est écrit quand même (aucune info perdue)"
"$TAB" report --notify "DEAD-SURFACE-0000" "$SD" TOY-2 BLOCKED "conflit" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 && "$(cut -d'|' -f1 "$SD/TOY-2.status")" == "BLOCKED" ]]; then
  ok "report exit=0 et TOY-2.status=BLOCKED — le re-scan rattrapera"
else
  ko "report a échoué (rc=$rc) ou statut non écrit"
fi

# --- T4 (adverse) : garde heures calmes --------------------------------------
echo "T4 — garde HEURES CALMES (date stubbée à 22h)"
stub="$(mktemp -d)"
printf '#!/bin/sh\nif [ "$1" = "+%%H" ]; then echo 22; else exec /bin/date "$@"; fi\n' > "$stub/date"
chmod +x "$stub/date"
b="$(count)"
PATH="$stub:$PATH" "$TAB" wake "$UUID" "ne doit PAS partir" >/dev/null 2>&1
rc=$?; sleep 6
if [[ $rc -eq 4 && "$(count)" -eq "$b" ]]; then ok "rien envoyé, exit 4"; else ko "wake envoyé en heures calmes (rc=$rc)"; fi

# --- T5 : rétro-compatibilité -------------------------------------------------
echo "T5 — rétro-compatibilité des commandes existantes"
"$TAB" report "$SD" TOY-3 MERGED "legacy" >/dev/null           && ok "report sans --notify" || ko "report legacy"
"$TAB" status "$SD" >/dev/null                                  && ok "status" || ko "status"
"$TAB" await "$SD" --timeout 5 --interval 1 TOY-3 >/dev/null    && ok "await" || ko "await"
"$TAB" note "$DIR/TOY.md" "TOY[dev]" "STEP:x" "legacy" >/dev/null && ok "note sans --notify" || ko "note legacy"
"$TAB" await-note --match 'STEP:x' --timeout 5 --interval 1 "$DIR/TOY.md" >/dev/null && ok "await-note" || ko "await-note"

echo
[[ $FAIL -eq 0 ]] && echo "RÉSULTAT: TOUS LES TESTS PASSENT" || echo "RÉSULTAT: ÉCHEC" >&2
exit $FAIL
