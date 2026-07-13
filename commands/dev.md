---
description: WORKFLOW DE DEV — implémenter un ticket JIRA de bout en bout (worktree → tests → MR → /end → suivi pipeline → statuts JIRA). Déclenché quand un ticket JIRA est fourni en entrée.
---

## Input

$ARGUMENTS

Le ticket JIRA à implémenter (numéro + éventuel bloc `PROMPT`). Si un préambule `[ORCHESTRATION CMUX]` est présent → **MODE ORCHESTRÉ** (voir ci-dessous).

## WORKFLOW DE DEV — RÈGLE ABSOLUE

**TOUTES les étapes sont OBLIGATOIRES, dans l'ordre. Aucune n'est optionnelle.**

### MODE ORCHESTRÉ — report de statut (OBLIGATOIRE si lancé par un orchestrateur de plan)

Si le prompt d'entrée contient un préambule `[ORCHESTRATION CMUX]` avec `STATUS_DIR=<dir> TICKET=<ticket>`, un orchestrateur supervise ce ticket et **attend les statuts** pour déclencher les tickets dépendants. Reporter à **chaque transition de phase** :
```
~/.claude/scripts/cmux-tab.sh report <STATUS_DIR> <TICKET> <STATE> "<detail>"
```
`STATE` ∈ `IN_PROGRESS` (worktree créé) | `MR_OPEN` (MR créée, lien MR en detail) | `MERGED` (MR mergée par l'humain, lien MR en detail) | `BLOCKED` (blocage nécessitant l'humain, raison en detail). **Ne jamais clore la tâche sans avoir reporté `MERGED` ou `BLOCKED`** — l'orchestrateur en dépend. (Hors mode orchestré : ignorer les `report`.)

### TITRE D'ONGLET CMUX — suivi visuel (OBLIGATOIRE à chaque phase)

Mettre à jour le titre de l'onglet cmux **de Claude** à chaque changement de phase (cible toujours l'onglet de Claude via `CMUX_SURFACE_ID`) :
```
~/.claude/scripts/cmux-tab.sh phase <PREFIX> "<résumé 3-4 mots>"
```
- **Plan** → `[PLAN] <résumé court>` (3-4 mots, compréhensible).
- **Implémentation** → `[IMPL] <même résumé>`.
- **MR prête à review** (après push + création MR) → `[MR] <résumé>`.
- **MR mergée + `/end` fait** → `[END] <résumé>`.
- **En attente réponse utilisateur** (question métier, blocage) → `[ASK] <résumé>`. Repasser au préfixe de la phase en cours dès réponse reçue.
- **En attente d'un événement externe** (dépendance en vol à merger, pipeline d'un autre process, signal attendu de l'utilisateur) → `[WAIT] <résumé>`. Distinct de `[ASK]` : ici aucune question n'est posée, on attend un signal/merge/événement pour reprendre. Repasser au préfixe de la phase en cours dès le signal reçu.

**Le résumé décrit CE QU'ON FAIT — jamais "impl du ticket X".** 3-4 mots sur le contenu réel, pas le mot "impl" ni le numéro de ticket seul.
- ❌ `[IMPL] BILL-2607 impl`
- ✅ `[IMPL] TRY PAR EVENTID`

Le résumé reste identique entre PLAN et IMPL ; seul le préfixe change.

### Étapes

1. **Lire le ticket JIRA** fourni (skill `/jira`) : titre, description métier, et **bloc `PROMPT`** = consigne d'implémentation. → onglet `[PLAN] <résumé>` puis étudier le plan.
   - **Si aucun ticket fourni** (demande directe) : demander le numéro de ticket JIRA ; sinon demander l'**EPIC** puis créer soi-même le ticket (skill `/jira`).
2. **Worktree + branche** — créer worktree + branche selon GIT WORKFLOW (base `origin/master`, hors repo). *(Mode orchestré : `report … IN_PROGRESS`.)*
3. **Implémentation** — implémenter en **utilisant obligatoirement des sous-agents** (ORCHESTRATION). Couverture de tests obligatoire (COUVERTURE DE CODE). Poser à l'utilisateur les **questions MÉTIER** nécessaires (jamais de demande de droits). → onglet `[IMPL] <résumé>`.
4. **LLM-as-a-Judge — avant de livrer** — agir en juge et vérifier :
   - implémentation cohérente au besoin,
   - aucun effet de bord, aucun bug introduit,
   - scope complet, rien d'oublié.
   Corriger avant de continuer si le juge relève quoi que ce soit.
5. **Statut JIRA → "In Progress / Dev"** (skill `/jira`).
6. **Push + MR** — pusher la branche puis **créer la MR** avec description respectant `/gitlab-resume`. **Mettre `@stephen.begot` en reviewer de la MR** (obligatoire). → onglet `[MR] <résumé>`. *(Mode orchestré : `report … MR_OPEN "<lien MR>"`.)*
7. **`/end`** — lancer le `/end` soi-même (skill `end`, avec vérif pipeline si MR — voir `/end AVEC MR`). → onglet `[END] <résumé>` une fois MR mergée + `/end` fait.
8. **Suivi MR jusqu'au vert** — suivre la MR jusqu'à pipeline verte. Corriger automatiquement :
   - problème de **pipeline** (voir /end AVEC MR),
   - **rebase impossible par GitLab** (conflits) → résoudre, repush.
9. **Statut JIRA → "Review"** (skill `/jira`).
10. **Commentaires de `@stephen.begot` — LECTURE OBLIGATOIRE, JAMAIS PAR SUPPOSITION.** Avant toute attente ou tout `[WAIT]`, **fetch explicitement les notes de la MR** et inspecte-les. Ne jamais conclure « pas de commentaire » sans avoir lancé la commande :
    ```
    glab api "projects/maltcommunity%2Fmalt%2Fapps%2Fmalt/merge_requests/<IID>/notes?per_page=100&sort=desc" \
      | python3 -c "import sys,json;[print(n['author']['username'],'|',repr(n['body'])) for n in json.load(sys.stdin) if not n.get('system')]"
    ```
    - S'il a commenté (question / demande de changement) : en tenir compte (fixer + repush) ou répondre. Ne jamais ignorer.
    - **Détection du feu vert** : chercher une note **non-system** de `stephen.begot` dont le body, une fois `trim()` + minuscule, vaut **`approved`** (match insensible à la casse/espaces). C'est CE commentaire qui autorise le merge.
    - **AVANT de programmer un `ScheduleWakeup`/poll d'attente d'approbation : lancer cette commande une fois immédiatement.** Ne planifier une attente QUE si le commentaire `Approved` est réellement absent à cet instant. À chaque réveil, re-lancer la commande (relire, jamais supposer).
11. **MERGE — seulement si `@stephen.begot` a posté un commentaire `Approved` (voir détection step 10) ET pipeline verte.** `@stephen.begot` est reviewer mais NE PEUT PAS self-approve (token à son nom) → son feu vert = un **commentaire `Approved`**, pas l'approbation native GitLab. Tant que ce commentaire n'existe pas : **NE JAMAIS MERGER**. Une fois réuni (commentaire `Approved` + pipeline verte) :
    1. **Rebase SANS relancer de pipeline** — impératif : un rebase nu (`glab mr rebase`) relance une pipeline complète ; sur un `master` très actif la branche redevient « behind » avant la fin → **boucle infinie, jamais mergeable**. Toujours rebaser avec `skip_ci` :
       ```
       glab api --method PUT "projects/maltcommunity%2Fmalt%2Fapps%2Fmalt/merge_requests/<IID>/rebase?skip_ci=true"
       ```
       (ou merger directement sans rebaser si GitLab l'autorise déjà — ne jamais déclencher un rebase qui relance la CI).
    2. **Merger AVEC SQUASH** (obligatoire) — `--squash` + message de squash = titre de MR (`[scope/domain] …`), et supprimer la source branch :
       ```
       glab mr merge <IID> -R maltcommunity/malt/apps/malt --squash --remove-source-branch --yes \
         --message "[scope/domain] <titre MR>"
       ```
    Ne jamais merger sans `--squash`. Ne jamais merger sans le commentaire `Approved`.
12. **Après merge → Statut JIRA "To Validate"** (skill `/jira`). *(Mode orchestré : `report … MERGED "<lien MR>"` — c'est CE report qui débloque les dépendants. Ne pas l'oublier.)*
13. **Livrable final** — retourner un tableau :

    | | |
    |---|---|
    | **JIRA** | lien vers le ticket |
    | **Statut JIRA** | statut courant — doit être **"To Validate"** en fin (sinon expliquer pourquoi) |
    | **MR** | lien vers la MR |
    | **`/end`** | ✅ / ❌ |
    | **Obsidian** | ✅ / ❌ / N/A — nouvelles specs/savoir capturés (`/obsidian` capture) ; N/A si rien de nouveau |
    | **Tradeoffs** | liste des arbitrages pris **automatiquement** sans validation explicite de l'utilisateur (choix de design/scope/implémentation décidés seul). Ex : "idempotence laissée hors du moteur de règles car `evaluate` ne porte pas l'agrégat" ; "hook `rejectReason` supprimé car jamais overridé". Une ligne par tradeoff, avec la raison. Mettre **Aucun** si tout a été validé en amont. |
    | **Résumé** | synthèse du travail |

    Le point **Tradeoffs** est OBLIGATOIRE : lister explicitement toute décision non triviale prise sans accord de l'utilisateur, pour qu'il puisse la contester en review.

## /end AVEC MR — VÉRIF PIPELINE (RÈGLE ABSOLUE)

Quand `/end` est lancé **avec une MR**, avant de clore :
1. **Lookup pipeline** de la MR (`glab ci status` / `glab_mr_view` / `glab_ci_list`) → vérifier **verte**.
2. **Si rouge** : lire logs du job en échec (`glab_ci_trace` / `glab_ci_artifact`), **diagnostiquer et fixer automatiquement**, commit + **repush** sur la branche de la MR (jamais master), re-vérifier. Boucler jusqu'au vert.
   - **Pipeline parent-child (monorepo Malt)** : `glab ci status` / `glab ci get` ne montrent que les jobs du parent. Le vrai job en échec est souvent dans la **child pipeline** (job-factory). La récupérer via `glab api "projects/:id/pipelines/<PARENT_ID>/bridges"` → `downstream_pipeline.id`, puis `glab api "projects/:id/pipelines/<CHILD_ID>/jobs?per_page=100"` pour trouver le job `failed`.
3. **Job Sonar en échec** : NE PAS deviner depuis le log CI (il ne donne que `QUALITY GATE FAILED` + lien dashboard). **Utiliser la commande `/sonar`** pour interroger l'API SonarQube et récupérer les conditions du gate en échec + les issues exactes (règle, fichier:ligne, message), puis fixer précisément. **Exception** : si l'API Sonar est injoignable / token invalide et que le log reste illisible → **demander les erreurs Sonar à l'utilisateur**, puis fixer.
4. Ne clore le `/end` qu'une fois pipeline verte, ou après avoir demandé les erreurs Sonar.

**ATTENTE DE PIPELINE — OUTIL `Monitor` INTERDIT (RÈGLE ABSOLUE).** Ne JAMAIS utiliser l'outil `Monitor` pour surveiller une pipeline (chaque événement déclenche une demande d'accord qui bloque l'utilisateur). Pour attendre l'état terminal d'une pipeline, utiliser un `Bash` en **`run_in_background: true`** avec une boucle `until` qui sort quand le statut vaut `success|failed|canceled` → une seule notification à la fin, aucun accord par événement. Exemple :
```
until s=$(glab api "projects/:id/pipelines/<PID>" | python3 -c "import sys,json;print(json.load(sys.stdin)['status'])") \
  && [ "$s" = success -o "$s" = failed -o "$s" = canceled ]; do sleep 30; done; echo "DONE=$s"
```

## Rappels transverses (voir CLAUDE.md)

- **ORCHESTRATION PAR SOUS-AGENTS** : thread principal = orchestrateur ; déléguer exploration/recherche/analyse de gros outputs aux sous-agents ; ils retournent une CONCLUSION, pas des dumps.
- **COUVERTURE DE CODE** : toute ligne ajoutée/modifiée couverte par un test ; TDD (`malt-backend-tdd`) pour nouveau comportement, `malt-test-coverage` sur code existant ; vert obligatoire avant de déclarer terminé.
- **GIT WORKFLOW** : jamais push sur master ; toujours worktree hors repo (base `origin/master`) + branche + MR ; merge autorisé UNIQUEMENT après un commentaire `Approved` de `@stephen.begot` (il ne peut pas self-approve, son token est à son nom → feu vert = commentaire "Approved", pas l'approve natif — **fetch les notes, ne jamais supposer**, cf. step 10) — reviewer `@stephen.begot` obligatoire sur chaque MR ; **merge TOUJOURS avec `--squash`** ; **rebase TOUJOURS `skip_ci=true`** (un rebase nu relance la CI → boucle infinie sur master actif) ; jamais co-author ; jamais lancer les linters (hook husky) ; titre MR `[scope/domain] Titre` en anglais ; label `squad-accounting` ; bloc de clôture obligatoire après push.
- **LANGUE** : toute écriture JIRA/GitLab/Notion en **ANGLAIS**.
- **TITRE DE SESSION** : commence par le numéro de ticket (`TICKET-123 description`).
