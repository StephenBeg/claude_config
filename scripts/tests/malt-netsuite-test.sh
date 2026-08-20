#!/usr/bin/env bash
# Test de bout en bout de malt-netsuite.py (CLI) et de netsuite-write-guard.sh (hook).
# AUCUN appel réseau, aucune credential requise : la garde de statement s'exécute avant la lecture
# du keychain, donc les rejets sont testables à sec.
# Les assertions sur les fonctions pures (OAuth, garde, rendu) vivent dans malt-netsuite-oauth-test.py.
set -uo pipefail
S="$HOME/.claude/scripts"
NS="$S/malt-netsuite.py"
GUARD="$S/netsuite-write-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

ck() { # ck <libellé> <attendu> <obtenu>
  if [[ "$3" == *"$2"* ]]; then echo "ok   — $1"; else echo "FAIL — $1 : attendu '$2', obtenu '$3'"; fail=1; fi
}
ck_not() { # ck_not <libellé> <interdit> <obtenu>
  if [[ "$3" != *"$2"* ]]; then echo "ok   — $1"; else echo "FAIL — $1 : '$2' ne devait pas apparaître"; fail=1; fi
}
guard() { # guard <commande> — remplit GOUT et GRC
  printf '{"tool_input":{"command":%s}}' \
    "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
    | "$GUARD" >"$TMP/guard.out" 2>&1
  GRC=$?
  GOUT="$(cat "$TMP/guard.out")"
}

echo "=== fonctions pures ==="
python3 "$S/tests/malt-netsuite-oauth-test.py" || fail=1

echo
echo "=== CLI ==="
out="$(python3 "$NS" "DELETE FROM transaction" 2>&1)"; rc=$?
ck "requête mutante -> code retour 1" "1" "$rc"
ck "requête mutante -> message read-only" "malt-netsuite:" "$out"

out="$(echo "DROP TABLE transaction" | python3 "$NS" 2>&1)"; rc=$?
ck "lecture stdin gardée aussi" "1" "$rc"

out="$(python3 "$NS" --limit 0 "SELECT 1 FROM dual" 2>&1)"
ck "--limit 0 refusé" "positive integer" "$out"

out="$(python3 "$NS" --env prod "SELECT 1 FROM dual" 2>&1 </dev/null)"
if [[ "$out" == *"no credentials"* ]]; then
  ck "creds absentes -> message actionnable" "--setup prod" "$out"
else
  echo "skip — des credentials prod existent déjà dans le keychain"
fi

ck "--setup imprime la commande sans l'exécuter" "security add-generic-password" "$(python3 "$NS" --setup prod)"
ck_not "--setup n'invente aucun secret" "csecret" "$(python3 "$NS" --setup prod)"
ck "--setup préremplit la sandbox" "5025154-sb1.suitetalk.api.netsuite.com" "$(python3 "$NS" --setup sandbox)"
ck "--env n'accepte que prod|sandbox" "invalid choice" "$(python3 "$NS" --env prod2 "SELECT 1" 2>&1)"
ck "--from-config sans --setup refusé" "only applies to --setup" \
   "$(python3 "$NS" --from-config "SELECT 1 FROM dual" 2>&1)"

echo
echo "=== --setup --from-config (source app-config, sans déchiffrer pour de vrai) ==="
out="$(MALT_APP_CONFIG="$TMP/absent" python3 "$NS" --setup prod --from-config 2>&1)"
ck "checkout app-config introuvable -> message actionnable" "MALT_APP_CONFIG" "$out"
ck "chemin du fichier de secrets cité" "spring-secrets.production.enc.yaml" "$out"
# Un fichier présent mais non déchiffrable doit échouer explicitement, pas écrire un keychain vide.
mkdir -p "$TMP/fake/helm/spring-apps-template/configurations/netsuite-connector"
echo "appSecrets: {}" > "$TMP/fake/helm/spring-apps-template/configurations/netsuite-connector/spring-secrets.production.enc.yaml"
out="$(MALT_APP_CONFIG="$TMP/fake" python3 "$NS" --setup prod --from-config 2>&1)"; rc=$?
ck "fichier non chiffré/incomplet -> échec explicite" "1" "$rc"
ck_not "aucun keychain écrit à vide" "stored 0 fields" "$out"

echo
echo "=== hook netsuite-write-guard ==="
guard 'curl -X POST https://5025154.suitetalk.api.netsuite.com/services/rest/record/v1/invoice'
ck "curl direct bloqué" "BLOCKED by netsuite-write-guard" "$GOUT"
ck "curl direct -> exit 2" "2" "$GRC"

guard 'SOME=1 sudo curl https://5025154.suitetalk.api.netsuite.com/x'
ck "client masqué par sudo/env bloqué" "BLOCKED" "$GOUT"

guard 'python3 -c "import urllib.request; urllib.request.urlopen(\"https://x.netsuite.com\")"'
ck "python inline bloqué" "BLOCKED" "$GOUT"

guard 'security find-generic-password -s malt-netsuite-prod -w'
ck "lecture du token bloquée" "must not be read" "$GOUT"
ck "lecture du token -> exit 2" "2" "$GRC"

guard 'security delete-generic-password -s malt-netsuite-sandbox'
ck "suppression du token bloquée" "BLOCKED" "$GOUT"

guard 'python3 ~/.claude/scripts/malt-netsuite.py "SELECT 1 FROM dual"'
ck "wrapper autorisé -> exit 0" "0" "$GRC"

guard 'python3 ~/.claude/scripts/malt-netsuite.py --setup prod'
ck "--setup autorisé -> exit 0" "0" "$GRC"

guard 'sops -d helm/spring-apps-template/configurations/netsuite-connector/spring-secrets.production.enc.yaml'
ck "déchiffrement manuel des secrets bloqué" "do not decrypt" "$GOUT"

guard 'sops -d helm/spring-apps-template/configurations/admin-backend/spring-secrets.production.enc.yaml'
ck "sops sur un autre service autorisé" "0" "$GRC"

guard 'python3 ~/.claude/scripts/malt-netsuite.py --setup prod --from-config'
ck "--setup --from-config autorisé -> exit 0" "0" "$GRC"

guard 'grep -rn netsuite.com erp/'
ck "grep du host autorisé (pas un client réseau)" "0" "$GRC"

guard 'git commit -m "netsuite: fix"'
ck "commande sans rapport -> exit 0" "0" "$GRC"

guard 'echo not-json-at-all'
ck "payload illisible -> pas de crash" "0" "$GRC"

echo
if [[ $fail -eq 0 ]]; then echo "TOUS LES TESTS PASSENT"; else echo "ÉCHECS DÉTECTÉS"; fi
exit $fail
