---
description: WORKFLOW DE DEV — implémenter un ticket JIRA de bout en bout (worktree → tests → MR → /end → suivi pipeline → statuts JIRA). Déclenché quand un ticket JIRA est fourni en entrée.
---

## Input

$ARGUMENTS

Le ticket JIRA à implémenter (numéro). La consigne d'implémentation vit dans le **champ JIRA "Prompt"** (`customfield_11956`), PAS dans la description. Si un préambule `[ORCHESTRATION CMUX]` est présent → **MODE ORCHESTRÉ** (voir ci-dessous).

### QUESTIONS À CHOIX DE RÉPONSES — RÈGLE ABSOLUE

Quand ce workflow pose une question à l'utilisateur **avec des choix de réponses** (options prédéfinies, arbitrage, `AskUserQuestion`) :

- **Explication détaillée AVANT les choix — obligatoire.** Avant de présenter les options, exposer le problème **point par point** : contexte, ce qui est en jeu, pourquoi la décision se pose, et pour **chaque option** ses implications / tradeoffs. But : que l'utilisateur comprenne réellement l'issue et les solutions, pas qu'il tranche à l'aveugle.
- **INTERDICTION D'UTILISER CAVEMAN dans ce cas précis.** L'explication du problème ET les libellés/descriptions des choix sont rédigés en **prose normale, complète et claire**. Caveman reste actif pour tout le reste de la session — on ne le suspend QUE pour la formulation de la question et de ses options.

### ACCÈS JIRA — MCP ou fallback API REST (RÈGLE ABSOLUE)

Toute interaction JIRA de ce workflow (lecture ticket, création, transitions de statut, commentaires) passe par le skill `/jira`. **Si le MCP Atlassian n'est PAS connecté** (auth échoue / tools `jira_*` indisponibles) → **NE PAS bloquer** : utiliser le **fallback API REST v3** documenté dans le skill `/jira` (curl + Basic auth, env `.zshrc`). Le skill `/jira` gère les deux : MCP si dispo, sinon REST. Vérifier au besoin : `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/myself"` → 200.

## WORKFLOW DE DEV — RÈGLE ABSOLUE

**TOUTES les étapes sont OBLIGATOIRES, dans l'ordre. Aucune n'est optionnelle.**

### MODE ORCHESTRÉ — report de statut (OBLIGATOIRE si lancé par un orchestrateur de plan)

Si le prompt d'entrée contient un préambule `[ORCHESTRATION CMUX]` avec `STATUS_DIR=<dir> TICKET=<ticket>`, un orchestrateur supervise ce ticket et **attend les statuts** pour déclencher les tickets dépendants. Reporter à **chaque transition de phase** :
```
~/.claude/scripts/cmux-tab.sh report <STATUS_DIR> <TICKET> <STATE> "<detail>"
```
`STATE` ∈ `IN_PROGRESS` (worktree créé) | `MR_OPEN` (MR créée, lien MR en detail) | `MERGED` (MR mergée par l'humain, lien MR en detail) | `BLOCKED` (blocage nécessitant l'humain, raison en detail). **Ne jamais clore la tâche sans avoir reporté `MERGED` ou `BLOCKED`** — l'orchestrateur en dépend. (Hors mode orchestré : ignorer les `report`.)

### TITRE D'ONGLET CMUX — suivi visuel (OBLIGATOIRE, MISE À JOUR À CHAQUE ACTION)

Voir **PRÉFIXES DE HEADER CMUX — TABLE UNIFIÉE** ci-dessous : la session DOIT mettre à jour le header **dès qu'elle fait quelque chose** (changement de phase), et peut **revenir en arrière** (ex : `[MR (1234)]` → `[PIPE (1234)]` si la pipeline repart après un fix demandé, puis `[MR (1234)]` à nouveau). Dès qu'une MR existe, son numéro figure dans le header **aussi bien en `[PIPE (num)]` qu'en `[MR (num)]`**.

### PRÉFIXES DE HEADER CMUX — TABLE UNIFIÉE (RÈGLE ABSOLUE, commune à `/plan` `/dev` `/hotfix`)

Mettre à jour le titre de l'onglet cmux **de Claude** (jamais celui de l'utilisateur ; cible via `CMUX_SURFACE_ID`) **dès qu'un changement d'état survient** :
```
~/.claude/scripts/cmux-tab.sh phase <PREFIX> "<résumé 3-4 mots>"
```

| Préfixe | Signification |
|---|---|
| `[MAIN]` | Processus qui en **orchestre d'autres** — reste en `[MAIN]` en permanence (orchestrateur de plan / GO IMPLEMENTATION). |
| `[PLAN]` | En **réflexion / analyse**, rien de commencé (diagnostic, cadrage, étude du prompt). |
| `[IMPL]` | En **cours d'implémentation** (code + tests). |
| `[PIPE (numMR)]` | Implémentation terminée, **en attente / en fix de pipeline verte**. Dès qu'une MR existe, **inclure son numéro** comme pour `[MR]` : `[PIPE (1234)]`. Tant qu'aucune MR n'existe encore, `[PIPE]` seul. |
| `[MR (numMR)]` | En **attente d'approval sur une MR** (mettre le numéro de MR : `[MR (1234)]`). |
| `[ASK]` | Une **question a été posée à l'utilisateur**, on attend sa réponse. |
| `[BLOCK]` | Processus **bloqué** pour une raison diverse (**pas** une question à poser à l'utilisateur). |
| `[WAIT]` | En **attente d'un autre processus** ou attente diverse (autre qu'une question utilisateur). |
| `[CLEAN]` | En **cours de clean** (worktree, artefacts). |
| `[END]` | **Tout est terminé** — dernier état avant de fermer le processus (worktree cleané, `/end` exécuté, MR mergée). |

**Règles :**
- La session **DOIT** mettre à jour le header **dès qu'elle fait quelque chose** — jamais laisser un header périmé.
- Le header peut **revenir en arrière** : ex `[MR (1234)]` → `[PIPE (1234)]` (fix demandé qui relance la pipeline) → `[MR (1234)]` ; ou `[MR (1234)]` → `[IMPL]` (request changes) → `[PIPE (1234)]` → `[MR (1234)]`.
- **Le résumé décrit CE QU'ON FAIT — jamais "impl du ticket X".** 3-4 mots sur le contenu réel, pas le mot "impl" ni le numéro de ticket seul. Le résumé reste **identique** entre phases ; seul le préfixe change.
  - ❌ `[IMPL] BILL-2607 impl`
  - ✅ `[IMPL] TRY PAR EVENTID`
- **Correspondance avec les étapes ci-dessous** : lecture ticket/étude → `[PLAN]` ; implémentation → `[IMPL]` ; suivi pipeline verte → `[PIPE (num)]` (numéro de MR inclus dès qu'elle existe) ; MR en attente d'approval → `[MR (num)]` ; clean worktree → `[CLEAN]` ; fin (MR mergée + `/end`) → `[END]`.

### Étapes

1. **Lire le ticket JIRA** fourni (skill `/jira`) : titre, description métier (contexte), et surtout le **champ "Prompt" (`customfield_11956`)** = consigne d'implémentation détaillée à suivre. → onglet `[PLAN] <résumé>` puis étudier le plan.
   - **Lecture du champ Prompt** : `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET>?fields=summary,description,customfield_11956"` — le champ est un doc ADF ; en extraire le texte. C'est LUI la consigne d'implémentation, pas la description.
   - **Fallback** : si `customfield_11956` est vide (ancien ticket créé avant la migration), retomber sur un éventuel bloc `PROMPT` en fin de description.
   - **Si aucun ticket fourni** (demande directe) : demander le numéro de ticket JIRA ; sinon demander l'**EPIC** puis créer soi-même le ticket (skill `/jira`).
2. **Worktree + branche** — créer worktree + branche selon GIT WORKFLOW (base `origin/master`, hors repo). *(Mode orchestré : `report … IN_PROGRESS`.)*
3. **Explore → Plan → Code** (VÉRIFICATION & BOUCLES, levier 5) — avant de coder, **vérifier le plan contre le code réel** via le subagent **`explorer`**. Le champ `Prompt` du ticket est déjà le plan mâché ; l'explore sert à le CONFIRMER (`path:line` réels, patterns jumeaux, contrats partagés), pas à tout re-découvrir. À **sauter** si le diff tient en une phrase (typo, log, renommage). Puis implémenter en **utilisant obligatoirement des sous-agents** (ORCHESTRATION). Couverture de tests obligatoire (COUVERTURE DE CODE). Poser à l'utilisateur les **questions MÉTIER** nécessaires (jamais de demande de droits). → onglet `[IMPL] <résumé>`. **Dimensionner le model de chaque sous-agent** (cf. DOSAGE DU MODÈLE) : `sonnet` pour localiser/implémenter/tester du code bien cadré, `haiku` pour du mécanique (grep, extraction), `opus` réservé à l'implémentation piégeuse.
4. **Vérification avant livraison — `/goal` borné + revue adverse en contexte frais (VÉRIFICATION & BOUCLES, leviers 2-3).** Ne PAS juger "à l'œil" dans le contexte qui a écrit le code.
   - **Poser un `/goal` borné** dont la condition tient les critères mesurables : 0 test en échec sur les modules touchés, service(s) touché(s) qui bootent (step 5), 0 violation Sonar new-code + coverage new-code ≥ 80 %, scope = besoin du ticket et rien de plus. **Borne dure : s'arrêter à ~6 tours** — si la condition ne tient pas, surfacer (`[BLOCK]`), jamais d'acharnement.
   - **Revue adverse déléguée au subagent `reviewer`** (contexte frais, `opus`) qui ne voit QUE le diff (`git diff origin/master...`) + la consigne (champ `Prompt`) + les critères, et cherche à **réfuter** : requirement non couvert, cas limite sans test, effet de bord hors scope, bug introduit. Il retourne une liste de **GAPS** (pas des préférences de style). Alternative outillée : skill `/code-review`.
   - Traiter les gaps de correctness/scope ; **ne pas sur-corriger** le reste (un reviewer trouve toujours quelque chose → over-engineering à éviter). Corriger avant de continuer.
5. **SMOKE-RUN LOCAL des services modifiés (OBLIGATOIRE) — attraper les casses au runtime.** Les tests verts ne prouvent PAS que le service boote : contexte Spring cassé (bean manquant/ambigu, `@Bean` dépendance non câblée, `NoResourceFoundException` 404 au boot, FF absent, migration Liquibase invalide, conflit de scan infra) ne sort qu'au démarrage. Pour **chaque service applicatif dont une ligne a été touchée** (ex : `netsuite-connector`, `accounting-backend` — les projets `*-application` / porteurs d'un `bootRun`) :
   - **Déterminer les services impactés** : mapper les fichiers du diff (`git diff --name-only origin/master...`) vers leur projet Gradle applicatif. Ne lancer QUE ceux réellement touchés (directement ou via un module dont ils dépendent au boot).
   - **Déléguer au subagent `smoke-runner`** (`haiku`, encapsule la procédure : lancer `./gradlew :<application-project>:bootRun` en `run_in_background: true`, boucle `until` sur `Started …Application in` vs `APPLICATION FAILED TO START`/`BUILD FAILED`/`BeanCreationException`/`UnsatisfiedDependency`/`NoResourceFoundException`, jamais `Monitor`, timeout ~5 min, `pkill -f bootRun` après verdict).
   - **Le sous-agent retourne une CONCLUSION** : `BOOTED_OK` ou `BOOT_FAILED` + la cause racine extraite du log (pas le dump).
   - **Si `BOOT_FAILED` par la faute du diff** → **c'est un bug à corriger** (systematic-debugging), fix + re-smoke-run jusqu'au boot vert. Ne pas pousser un service qui ne boote pas.
   - **Si le boot échoue pour une raison d'ENVIRONNEMENT local** (devbox DB down, secret/creds manquant, dépendance externe indisponible — pas causé par le diff) → **ne pas bloquer** : consigner la raison dans le livrable final (Tradeoffs), et se rabattre sur la vérif pipeline du `/end`. Distinguer clairement « cassé par mon code » (bloquant) de « env local indispo » (non bloquant).

   **TIPS bootRun local (gagnés sur le terrain, éprouvés sur `accounting-backend`) :**
   - **Nom de projet Gradle = basename du module, PAS le chemin.** `accounting-backend` vit dans `erp/accounting-backend` mais la task est `:accounting-backend:bootRun` — **jamais** `:erp:accounting-backend` (le segment `erp` fait échouer/ambiguïser la résolution). En doute : `./gradlew :<basename>:bootRun`.
   - **Toujours le profil `dev`** : `./gradlew :<module>:bootRun --args='--spring.profiles.active=dev'`.
   - **Le crash de WIRING Spring (bean manquant/ambigu, `@ConditionalOnProperty`/`@Primary` oublié, dépendance non câblée) sort AVANT toute connexion DB/rabbit**, pendant le refresh du contexte. Donc un boot cassé par le code se détecte **même sans devbox up**. C'est le signal le plus rentable à guetter.
   - **Frontière wiring vs env** : dès que le log atteint `HikariPool` / `Liquibase` / `Connection refused` / `jdbc` / un log applicatif tardif → **le wiring est OK** ; un échec après ce point = env local (non bloquant). Le succès total = `Started <App>Application in Ns` (accounting-backend boote ~90 s avec devbox up).
   - **Ne pas laisser tourner** : `pkill -f bootRun` après le verdict (le `illegal byte sequence` de pkill est bénin).
6. **Statut JIRA → "In Progress / Dev"** (skill `/jira`) — **c'est ICI que le dev commence : s'auto-assigner le ticket à `stephen.begot` MAINTENANT** (pas avant), via `PUT /rest/api/3/issue/<TICKET>/assignee` avec l'`accountId` résolu par `/rest/api/3/user/search?query=stephen.begot@malt.com`. Le passage `In Progress` et l'assignation vont de pair.
7. **Validation Sonar PRÉ-PUSH (OBLIGATOIRE, avant tout push)** — auto-relire le code produit contre les règles du quality gate Sonar et **corriger localement** avant de pousser, pour éviter les allers-retours avec GitLab (une pipeline rouge sur `*-sonar` = un cycle repush complet).
   - Règles actives + seuils du gate : note Obsidian `[[SonarQube Malt - Règles actives]]` (commande `/obsidian`, mode recherche). Réutiliser cette pré-analyse plutôt que deviner.
   - Points de contrôle systématiques sur le diff produit :
     - **Coverage new code ≥ 80 %** : chaque ligne main ajoutée/modifiée exercée par un test (recouvre COUVERTURE DE CODE). Repérer les seams non testés (codec/repo DB, controllers, branches d'erreur).
     - **0 violation new code** : littéraux dupliqués (S1192 → constante), `when` > 30 branches (S1479 → extraire un helper), params > 7 (S107), duplication (`[[reference_sonar_duplication_nested_composition]]`), et autres règles de la note.
   - Ne pousser qu'une fois cette relecture passée. La vérif pipeline du `/end` reste le filet de sécurité (fallback), pas le premier rempart.
8. **Push + MR** — pusher la branche puis **créer la MR** avec description respectant `/gitlab-resume`. **TITRE DE MR (RÈGLE ABSOLUE)** : préfixe entre crochets =
   - **si un ticket JIRA est en entrée** → `[<TICKET>] Titre` (ex : `[BILL-2854] Fix invoice rounding`) ;
   - **si AUCUN ticket JIRA** → `[devscoot] Titre`.
   Le titre (donc le subject du 1er commit, qui préremplit le titre de MR) suit ce format, en anglais. **Mettre `@stephen.begot` en reviewer de la MR** (obligatoire). → onglet `[MR (<numMR>)] <résumé>`. *(Mode orchestré : `report … MR_OPEN "<lien MR>"`.)*
9. **`/end`** — lancer le `/end` soi-même (skill `end`, avec vérif pipeline si MR — voir `/end AVEC MR`). → onglet `[END] <résumé>` une fois MR mergée + `/end` fait.
10. **Suivi MR jusqu'au vert** — → onglet `[PIPE (<numMR>)] <résumé>` tant que la pipeline n'est pas verte. Suivre la MR jusqu'à pipeline verte (attente : boucle `until` en background ou `/loop` auto-cadencé — cf. VÉRIFICATION & BOUCLES levier 4 ; **`Monitor` reste interdit**, intervalle calé sur la vitesse réelle de la pipeline ~8 min). Corriger automatiquement :
   - problème de **pipeline** (voir /end AVEC MR),
   - **rebase impossible par GitLab** (conflits) → résoudre, repush.
   - Une fois la pipeline verte et la MR en attente d'approval → revenir à `[MR (<numMR>)] <résumé>`.
11. **Statut JIRA → "Review"** (skill `/jira`).
12. **Commentaires de `@stephen.begot` — LECTURE OBLIGATOIRE, JAMAIS PAR SUPPOSITION.** Avant toute attente ou tout `[WAIT]`, **fetch explicitement les notes de la MR** et inspecte-les. Ne jamais conclure « pas de commentaire » sans avoir lancé la commande :
    ```
    glab api "projects/maltcommunity%2Fmalt%2Fapps%2Fmalt/merge_requests/<IID>/notes?per_page=100&sort=desc" \
      | python3 -c "import sys,json;[print(n['author']['username'],'|',repr(n['body'])) for n in json.load(sys.stdin) if not n.get('system')]"
    ```
    - S'il a commenté (question / demande de changement) : en tenir compte (fixer + repush) ou répondre. Ne jamais ignorer.
    - **REQUEST CHANGES — RÈGLE ABSOLUE.** Tant que `@stephen.begot` n'a PAS posté `Approved`, ses commentaires de review sont des **demandes de changement** à traiter : pour chacun, **corriger** (fix + repush sur la branche, jamais master → onglet `[IMPL]` puis `[PIPE (<numMR>)]` le temps de la nouvelle pipeline) **ou répondre** si c'est une question / un désaccord argumenté. **Après avoir traité TOUS les points, il faut LUI REDEMANDER un `Approved`** : ne jamais considérer que les changements valent approbation. Reboucler : repush → pipeline verte (`[PIPE (<numMR>)]`) → attente d'un nouveau commentaire `Approved` (`[MR (<numMR>)]`). Un cycle request-changes → fix → re-demande peut se répéter plusieurs fois ; **le seul feu vert reste un commentaire `Approved`**.
    - **Détection du feu vert** : chercher une note **non-system** de `stephen.begot` dont le body, une fois `trim()` + minuscule, vaut **`approved`** (match insensible à la casse/espaces). C'est CE commentaire qui autorise le merge. **Un `Approved` ne vaut que s'il est POSTÉRIEUR au dernier repush** : si de nouveaux changements ont été poussés après le `Approved`, redemander une nouvelle approbation.
    - **AVANT de programmer un `ScheduleWakeup`/poll d'attente d'approbation : lancer cette commande une fois immédiatement.** Ne planifier une attente QUE si le commentaire `Approved` est réellement absent à cet instant. À chaque réveil, re-lancer la commande (relire, jamais supposer).
13. **MERGE — seulement si `@stephen.begot` a posté un commentaire `Approved` (voir détection step 12) ET pipeline verte.** `@stephen.begot` est reviewer mais NE PEUT PAS self-approve (token à son nom) → son feu vert = un **commentaire `Approved`**, pas l'approbation native GitLab. Tant que ce commentaire n'existe pas : **NE JAMAIS MERGER**. Une fois réuni (commentaire `Approved` + pipeline verte) :
    1. **Rebase SANS relancer de pipeline** — impératif : un rebase nu (`glab mr rebase`) relance une pipeline complète ; sur un `master` très actif la branche redevient « behind » avant la fin → **boucle infinie, jamais mergeable**. Toujours rebaser avec `skip_ci` :
       ```
       glab api --method PUT "projects/maltcommunity%2Fmalt%2Fapps%2Fmalt/merge_requests/<IID>/rebase?skip_ci=true"
       ```
       (ou merger directement sans rebaser si GitLab l'autorise déjà — ne jamais déclencher un rebase qui relance la CI).
    2. **Merger AVEC SQUASH** (obligatoire) — `--squash` + message de squash = titre de MR (`[<TICKET>] …` si ticket, sinon `[devscoot] …`), et supprimer la source branch :
       ```
       glab mr merge <IID> -R maltcommunity/malt/apps/malt --squash --remove-source-branch --yes \
         --message "[<TICKET>|devscoot] <titre MR>"
       ```
    Ne jamais merger sans `--squash`. Ne jamais merger sans le commentaire `Approved`.
14. **Après merge → Statut JIRA "To Validate"** (skill `/jira`). *(Mode orchestré : `report … MERGED "<lien MR>"` — c'est CE report qui débloque les dépendants. Ne pas l'oublier.)*
15. **Livrable final** — retourner un tableau :

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

## TRAVAIL DÉCOUVERT EN COURS DE ROUTE — RÈGLE ABSOLUE

Un `/dev` reste **focalisé sur SON ticket**. S'il découvre du travail annexe (bug hors scope, dette, champ à revoir, question de cadrage), il **ne l'implémente pas en douce** et ne l'enfouit pas dans son commit :

- **Créer un ticket JIRA dédié** (skill `/jira`) **sous le MÊME parapluie** (la User Story / umbrella parente de son propre ticket, ou l'EPIC), pour que l'**orchestrateur de plan le capte à son RESCAN des enfants de l'umbrella**. Poser les liens de dépendance pertinents (`is blocked by`). **Label `Accounting/Bookkeeping` OBLIGATOIRE à la création** (`"labels":["Accounting/Bookkeeping"]` dans le payload). **NE PAS assigner** le ticket à la création — l'assignation à `stephen.begot` n'a lieu qu'au démarrage du dev (step 6 du `/dev` qui l'implémentera).
- **CHOISIR LE TYPE correctement** : si le travail découvert est une **recherche / investigation / cadrage** (pas un fix mécanique) → le ticket est un **SPIKE**, destiné à être lancé en **`/plan`** (sous-plan récursif), PAS en `/dev`. Si c'est un fix d'implémentation clair et borné → ticket d'implémentation (`/dev`). Rédiger la consigne dans le **champ "Prompt" (`customfield_11956`)** (jamais dans la description, qui reste métier et lisible), en indiquant explicitement `lance /plan` ou `lance /dev`.
- **Signaler à l'orchestrateur** : en mode orchestré, mentionner le(s) ticket(s) créé(s) dans le `detail` du prochain `report` (et dans le livrable final). Ne jamais élargir silencieusement le périmètre de son propre ticket.
- **Ne PAS orchestrer soi-même** ces tickets depuis un `/dev` : le `/dev` crée et signale ; c'est l'orchestrateur de plan (ou le SPIKE-plan concerné) qui les intègre au DAG et les lance.

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

## DOSAGE DU MODÈLE DES SOUS-AGENTS — RÈGLE ABSOLUE (commune à `/plan` `/dev` `/hotfix`)

Chaque fois que le thread principal crée un sous-agent (outil `Agent`, param `model`), il **DOIT dimensionner le model à la difficulté réelle de la tâche** — jamais un model sur-dimensionné (plus cher pour rien). Le thread principal (orchestrateur) reste sur son propre model ; seul le sous-agent est calibré.

| Model | Quand l'utiliser | Exemples dans ce workflow |
|---|---|---|
| **`haiku`** | Tâche **mécanique / déterministe**, zéro raisonnement : grep, lister des fichiers, extraire un texte, tailer/grep un log de boot, lire un statut, appliquer un patch trivial déjà spécifié. | Smoke-run (boucle `until` qui grep `Started …Application in` sur le log bootRun) ; extraction du texte ADF d'un champ JIRA ; lookup `path:line` d'un symbole connu. |
| **`sonnet`** | Tâche **standard** : exploration/localisation de code, lecture multi-fichiers, écriture de tests jumeaux, implémentation bornée et bien cadrée, sweep de conventions, relecture Sonar. | Localiser le domaine touché ; copier le test sibling le plus proche ; implémenter une consigne `Prompt` déjà mâchée ; relecture pré-push Sonar. |
| **`opus`** | Tâche à **fort raisonnement** : diagnostic de cause racine, design/archi, arbitrage non trivial, revue adverse (subagent `reviewer`), implémentation piégeuse (invariants, concurrence, event-sourcing). | Cause racine d'un bug ; revue adverse avant livraison ; décision de design avec effets transverses. |

**Règle par défaut : commencer au model le PLUS BAS plausible**, remonter d'un cran seulement si la tâche l'exige. En cas de doute entre deux crans → prendre le plus bas et surveiller le résultat. Si le sous-agent échoue par manque de capacité (pas par manque de contexte) → relancer au cran au-dessus. **Ne jamais mettre `opus` par réflexe** sur une tâche d'exploration ou mécanique.

## VÉRIFICATION & BOUCLES DE CONTRÔLE — RÈGLE ABSOLUE (commune à `/plan` `/dev` `/hotfix`)

Principe Anthropic : **donner à l'agent un moyen de vérifier son propre travail** — un signal pass/fail qu'il lit et sur lequel il itère seul, au lieu que l'humain soit la boucle de vérification. Cinq leviers :

1. **Preuve, jamais affirmation.** Toute conclusion « c'est vert / c'est fixé / ça boote » DOIT citer une **sortie réelle** : output de test, exit code de build, log `Started …Application in`, ligne Sonar `règle fichier:ligne`, statut de pipeline. Jamais « les tests passent » sans la sortie. (superpowers:verification-before-completion.)
2. **`/goal` — ligne d'arrivée mesurable et bornée.** Pour la vérif pré-livraison, poser un `/goal` explicite plutôt que juger à l'œil : un évaluateur re-teste la condition à chaque tour, l'agent boucle jusqu'à ce qu'elle tienne. Conditions typiques : 0 test en échec (modules touchés) ; service(s) touché(s) qui bootent ; 0 violation Sonar new-code + coverage ≥ 80 % ; scope = besoin du ticket, rien de plus. **Borne dure : ~6 tours max** — atteinte sans vert → surfacer (`[BLOCK]`), jamais d'acharnement.
3. **Revue adverse en CONTEXTE FRAIS (subagent `reviewer`).** Le juge ne tourne JAMAIS dans le contexte qui a écrit le code (biais). Déléguer au subagent **`reviewer`** (`.claude/agents/`, `opus`) qui ne voit QUE le diff + la consigne (`Prompt`) + les critères, et cherche à **réfuter** : requirement non couvert, cas limite sans test, effet de bord hors scope, bug introduit. Retourne des **GAPS**, pas des préférences de style. Traiter correctness/scope ; **ne pas sur-corriger** le reste. Alternative outillée : skill `/code-review`. (Exploration : subagent **`explorer`** ; smoke-run : **`smoke-runner`**.)
4. **`/loop` — attente/polling auto-cadencé (option).** Pour surveiller un état externe qui évolue seul (pipeline CI, attente d'approbation `Approved`), `/loop` est l'alternative auto-cadencée aux réveils manuels. **Ne remplace PAS** la boucle `until` en background ni `ScheduleWakeup` : ce sont des mécanismes équivalents. **L'outil `Monitor` reste INTERDIT** (un accord par événement bloque l'utilisateur). Intervalle calé sur la vitesse réelle de l'état surveillé (pipeline ~8 min → un check ~480 s, pas 8 checks de 60 s).
5. **Explore → Plan → Code.** Séparer compréhension et exécution pour ne pas résoudre le mauvais problème. Utile quand l'approche est incertaine / multi-fichiers / code peu connu. **À sauter** si le diff tient en une phrase. Dans ces workflows, l'explore sert surtout à **vérifier le plan mâché (`Prompt`) contre le code réel**, pas à tout re-découvrir.

## Rappels transverses (voir CLAUDE.md)

- **ORCHESTRATION PAR SOUS-AGENTS** : thread principal = orchestrateur ; déléguer exploration/recherche/analyse de gros outputs aux sous-agents ; ils retournent une CONCLUSION, pas des dumps. **Dimensionner le model de chaque sous-agent** (haiku/sonnet/opus) selon la difficulté — cf. DOSAGE DU MODÈLE DES SOUS-AGENTS.
- **VÉRIFICATION & BOUCLES** : preuve jamais affirmation ; `/goal` borné pour la vérif pré-livraison ; revue adverse en contexte frais (sous-agent `opus` ou `/code-review`) ; `/loop` option d'attente (jamais `Monitor`) ; explore→plan avant de coder — cf. section dédiée.
- **COUVERTURE DE CODE** : toute ligne ajoutée/modifiée couverte par un test ; TDD (`malt-backend-tdd`) pour nouveau comportement, `malt-test-coverage` sur code existant ; vert obligatoire avant de déclarer terminé.
- **GIT WORKFLOW** : jamais push sur master ; toujours worktree hors repo (base `origin/master`) + branche + MR ; merge autorisé UNIQUEMENT après un commentaire `Approved` de `@stephen.begot` (il ne peut pas self-approve, son token est à son nom → feu vert = commentaire "Approved", pas l'approve natif — **fetch les notes, ne jamais supposer**, cf. step 12) — reviewer `@stephen.begot` obligatoire sur chaque MR ; **merge TOUJOURS avec `--squash`** ; **rebase TOUJOURS `skip_ci=true`** (un rebase nu relance la CI → boucle infinie sur master actif) ; jamais co-author ; jamais lancer les linters (hook husky) ; titre MR en anglais préfixé `[<TICKET>]` si ticket JIRA (ex `[BILL-2854]`) sinon `[devscoot]` ; label `squad-accounting` ; bloc de clôture obligatoire après push.
- **SMOKE-RUN LOCAL** : tout service applicatif dont une ligne est touchée DOIT booter en local (`bootRun`, sous-agent + background + boucle `until` sur `Started …Application in`, jamais `Monitor`) avant push ; boot cassé par le diff = bug bloquant à fixer ; env local indispo = non bloquant, consigner en Tradeoffs (cf. step 5).
- **LANGUE** : toute écriture JIRA/GitLab/Notion en **ANGLAIS**.
- **TITRE DE SESSION** : commence par le numéro de ticket (`TICKET-123 description`).
- **TRAVAIL DÉCOUVERT** : jamais implémenter hors-scope en douce ; créer un ticket sous le parapluie (SPIKE→`/plan`, fix→`/dev`), le signaler à l'orchestrateur, le laisser orchestrer (cf. section dédiée).
