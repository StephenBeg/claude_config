---
description: WORKFLOW D'ETUDE — repondre a une question statistique sur les donnees reelles (comptages, repartitions, volumes) en LECTURE SEULE sur la base de prod. Aucun code, aucun ticket, aucune MR. Declenche par /scan suivi de la question.
---

## Input

$ARGUMENTS

La question d'étude (ex. « combien de freelances FR micro-entrepreneurs par subsidiary »).

## Périmètre

`/scan` produit des **chiffres**, pas du code : ni worktree, ni commit, ni ticket JIRA, ni MR. Une étude qui révèle un bug → proposer `/hotfix` ; une évolution à construire → `/plan` ou `/dev`.

Le gate `prod-db` ouvre la prod à ce workflow. Tout le reste de `malt-prod-sql` s'applique, en particulier **LECTURE SEULE, SANS EXCEPTION**.

## Étapes

1. **Sujet** : `cmux-tab.sh topic "<3-4 mots>"` puis `cmux-tab.sh phase PLAN`.
2. **Modèle de données depuis le code** : localiser tables, colonnes, enums et jointures (sous-agent `explorer`, pré-analyse `malt-accounting-domain` ou Obsidian). Une donnée qui vit dans Mongo est hors de portée de `malt-sql.sh` : le dire.
3. **Définition à arbitrer** : si la question admet plusieurs définitions (population, période, critère d'éligibilité), charger `asking-the-user` et faire trancher avant de requêter.
4. **Requête validée sur integ** : `malt-sql.sh --env integ` d'abord (syntaxe, jointures, libellés réels des valeurs filtrées).
5. **Exécution prod** : charger `malt-prod-sql`, lancer via `malt-sql.sh`. Toujours borner (`LIMIT`, fenêtre de dates) avant un agrégat lourd.
6. **Livrable** : tableau de résultats, requête exacte, définition retenue, limites (population exclue, proxy utilisé, double comptage). Un document destiné à d'autres → `writing-for-humans`.

## Données personnelles — RÈGLE ABSOLUE

Seuls des **agrégats** sortent de la base : `count`, `sum`, `avg`, `group by`. Jamais de liste nominative (nom, email, adresse, IBAN, SIREN individuel) dans la réponse, un fichier ou un document. Un échantillon de contrôle se limite à des identifiants techniques, et il n'est pas recopié dans le livrable.
