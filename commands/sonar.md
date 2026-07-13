---
description: Interroge SonarQube (Malt) via l'API web — récupère les conditions du quality gate en échec et les issues exactes (règle, fichier:ligne, message) sur une branche. À utiliser dès qu'une pipeline casse sur Sonar.
---

## Objectif

Quand une pipeline GitLab casse sur le job Sonar (`erp-sonar`, `*-sonar`), le log CI ne donne QUE `QUALITY GATE STATUS: FAILED` + un lien dashboard — jamais les conditions précises. Cette commande récupère **par l'API web SonarQube** les conditions du gate en échec ET les issues exactes (règle, fichier, ligne, message), pour **fixer sans deviner**.

Ne JAMAIS deviner la cause d'un fail Sonar depuis le log CI. Toujours interroger l'API.

## Prérequis — credentials

Le token + l'URL SonarQube sont dans la config MCP de `~/.claude.json` (env `SONARQUBE_TOKEN` / `SONARQUBE_URL`). Les extraire :

```bash
eval $(python3 -c "
import json,os
d=json.load(open(os.path.expanduser('~/.claude.json')))
def find(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k=='SONARQUBE_TOKEN' and isinstance(v,str): print(f'SONAR_TOKEN={v}')
            if k=='SONARQUBE_URL' and isinstance(v,str): print(f'SONAR_URL={v}')
            find(v)
    elif isinstance(o,list):
        for i in o: find(i)
find(d)
")
echo "URL=$SONAR_URL"
```

Auth API = **basic auth, token en username, password vide** : `curl -s -u "$SONAR_TOKEN:" ...`

## Paramètres à déterminer

- **projectKey** : clé du projet Sonar (ex `malt:erp`). Lisible dans le log du job Sonar (`dashboard?id=malt%3Aerp` → `malt:erp`) ou via `/api/projects/search`.
- **branch** : la branche de la MR (ex `BILL-1234-truc`). = `git -C <worktree> rev-parse --abbrev-ref HEAD`.

## Étape 1 — Conditions du quality gate en échec

```bash
curl -s -u "$SONAR_TOKEN:" \
  "$SONAR_URL/api/qualitygates/project_status?projectKey=$PROJECT_KEY&branch=$BRANCH" \
  | python3 -c "
import sys,json
ps=json.load(sys.stdin).get('projectStatus',{})
print('GATE:', ps.get('status'))
for c in ps.get('conditions',[]):
    if c.get('status')!='OK':
        print('FAIL:', c['metricKey'], '| actual=',c.get('actualValue'),
              '| op=',c.get('comparator'), '| threshold=',c.get('errorThreshold'))
"
```

Métriques fréquentes : `new_violations`, `new_coverage`, `new_duplicated_lines_density`, `new_bugs`, `new_code_smells`, `new_security_hotspots_reviewed`.

## Étape 2 — Issues exactes sur le NEW CODE

Pour `new_violations` / `new_bugs` / `new_code_smells` — lister les issues introduites par la MR (règle + fichier:ligne + message) :

```bash
curl -s -u "$SONAR_TOKEN:" \
  "$SONAR_URL/api/issues/search?componentKeys=$PROJECT_KEY&branch=$BRANCH&resolved=false&inNewCodePeriod=true&ps=100" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('total new-code issues:', d.get('total'))
for i in d.get('issues',[]):
    print('---')
    print('sev:', i.get('severity'), '| type:', i.get('type'), '| rule:', i.get('rule'))
    print('comp:', i.get('component'), ':', i.get('line'))
    print('msg:', i.get('message'))
"
```

## Étape 3 — Détails complémentaires (selon la métrique)

- **Duplication** (`new_duplicated_lines_density`) : voir memory `[[reference_sonar_duplication_nested_composition]]` — collapser via composition imbriquée (`val common: XxxCommonFields`), pas helper à args plats.
- **Coverage** (`new_coverage`) : couvrir les lignes ajoutées par un test (règle COUVERTURE DE CODE).
- **Règle inconnue** : `curl -s -u "$SONAR_TOKEN:" "$SONAR_URL/api/rules/show?key=<rule>"` pour le rationale + exemples.
- **Security hotspots** : `.../api/hotspots/search?projectKey=$PROJECT_KEY&branch=$BRANCH&status=TO_REVIEW`.

## Étape 4 — Fixer

Fixer la cause exacte remontée (jamais deviner), commit + repush sur la branche de la MR (jamais master, cf. GIT WORKFLOW), puis re-vérifier la pipeline jusqu'au vert.

## Notes

- Endpoints alternatifs : `/api/measures/component?component=$PROJECT_KEY&branch=$BRANCH&metricKeys=new_violations,new_coverage,...` pour les valeurs brutes.
- Si l'API est injoignable / token invalide → fallback : ouvrir le dashboard (lien dans le log CI) et demander à l'utilisateur de coller les erreurs (exception "Sonar illisible" du `/dev`).
- Ne pas logger le token en clair dans un fichier partagé du repo.
