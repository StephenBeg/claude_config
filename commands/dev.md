---
description: WORKFLOW DE DEV — implémenter un ticket JIRA de bout en bout (worktree → tests → MR → suivi pipeline → statuts JIRA → /end). Déclenché quand un ticket JIRA est fourni en entrée.
---

## Input

$ARGUMENTS

Le ticket JIRA à implémenter (numéro). La consigne d'implémentation vit dans le **champ JIRA "Prompt"** (`customfield_11956`), PAS dans la description. Si le prompt d'entrée est un lien `Lis $WF/<T>.md et exécute` dont le header (écrit par l'orchestrateur) contient `[ORCHESTRATION]` → **MODE ORCHESTRÉ** : lire ce fichier EN PREMIER (il porte le STATUS_DIR, les chemins d'inbox et la consigne), puis suivre le WORKFLOW (voir ci-dessous).

**RÈGLES COMMUNES — invoquer le skill `malt-workflow-commons` EN PREMIER.** Il porte les règles partagées par `/dev` `/plan` `/hotfix` (source de vérité unique) : **§ QUESTIONS À CHOIX DE RÉPONSES**, **§ DÉCISIONS D'ARCHI & TRADEOFFS — ESCALADE OBLIGATOIRE**, **§ ACCÈS JIRA**, **§ PRÉFIXES DE HEADER CMUX**, **§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL**, **§ VÉRIFICATION & BOUCLES DE CONTRÔLE**, **§ SMOKE-RUN LOCAL**, **§ /end AVEC MR — VÉRIF PIPELINE**, **§ TRAVAIL DÉCOUVERT EN COURS DE ROUTE**, **§ LIVRABLE FINAL**. Ce workflow y renvoie par le nom de section. **Suivi de pipeline (steps 7, 9, 10)** : skill `malt-pipeline-followup` (source de vérité unique dédiée).

**ESCALADE ARCHI — RÈGLE ABSOLUE POUR CE DEV.** Même avec un `Prompt` détaillé, dès que l'implémentation fait surgir une **décision d'archi** non tranchée par le ticket (nouveau pattern/abstraction, forme de contrat, nouvelle table vs colonne, event vs appel direct, dépendance ajoutée, frontière de domaine) OU un **tradeoff différenciant** (deux options → résultat observablement différent) → **STOPPER et escalader à l'utilisateur** (§ DÉCISIONS D'ARCHI & TRADEOFFS), **avant** de coder cette partie. Ne jamais trancher un choix d'archi seul puis le révéler en Tradeoffs. Doute → demander.

## WORKFLOW DE DEV — RÈGLE ABSOLUE

**TOUTES les étapes sont OBLIGATOIRES, dans l'ordre. Aucune n'est optionnelle.**

### MODE ORCHESTRÉ — report de statut (OBLIGATOIRE si lancé par un orchestrateur de plan)

Si le header de MON inbox (lu via le lien du spawn) contient `[ORCHESTRATION]` avec `STATUS_DIR=<dir> TICKET=<ticket> ORCH_SURFACE=<uuid>`, un orchestrateur supervise ce ticket. **Il ne me surveille PAS : c'est MOI qui le réveille** (skill `malt-surface-exchange` § RÉVEIL). Sans mon `--notify`, le DAG n'avance pas. Reporter à **chaque transition de phase** :
```
~/.claude/scripts/cmux-tab.sh report --notify <ORCH_SURFACE> <STATUS_DIR> <TICKET> <STATE> "<detail>"
```
`--notify` écrit le statut **et** injecte le réveil dans la surface de l'orchestrateur (mis en file s'il est occupé, pas envoyé en heures calmes — jamais bloquant, jamais fatal). `ORCH_SURFACE` absent du header → omettre `--notify`.
`STATE` ∈ `IN_PROGRESS` (worktree créé) | `MR_OPEN` (MR créée, lien MR en detail) | `MERGED` (MR mergée par l'humain, lien MR en detail) | `BLOCKED` (blocage nécessitant l'humain, raison en detail). **Ne jamais clore la tâche sans avoir reporté `MERGED` ou `BLOCKED`** — l'orchestrateur en dépend. (Hors mode orchestré : ignorer les `report`.)

### PROTOCOLE DE PHASE — OBLIGATOIRE EN SOLO **ET** EN ORCHESTRÉ (RÈGLE ABSOLUE)

**Le header CMUX et le suivi de pipeline ne sont PAS réservés au mode orchestré.** En solo (lancé par l'utilisateur, sans header `[ORCHESTRATION]`), la même discipline s'applique intégralement — c'est le défaut historique de sous-application quand aucun orchestrateur n'attend.

**Poser le sujet UNE FOIS au démarrage**, il est persistant ensuite (survit aux phases et à la compaction) :
```
~/.claude/scripts/cmux-tab.sh topic "<3-4 mots sur CE QU'ON FAIT>"   # ex : "TRY PAR EVENTID"
```
Puis, à chaque transition, `cmux-tab.sh phase <PREFIX>` — **préfixe nu**, le script pose les crochets et refuse un préfixe inconnu. `[MR (n)]`, `[PIPE (n)]`, `[IMPL]` (worktree) et `[CLEAN]` (merge) sont posés **automatiquement par les hooks** ; restent à ta charge `[PLAN]`, `[ASK]`, `[BLOCK]`, `[WAIT]`, `[END]` et les retours arrière métier. Sémantique complète, règles et automatismes : skill `malt-workflow-commons` **§ PRÉFIXES DE HEADER CMUX** (source de vérité unique — ne pas la recopier ici).

**SUIVI PIPELINE + ATTENTE `Approved` = OBLIGATOIRES EN SOLO AUSSI.** Les steps 10 (skill `malt-pipeline-followup`) et 12 (lecture des notes / attente `Approved`) s'exécutent que le `/dev` soit orchestré ou non. Ne jamais « lâcher » le suivi parce que personne n'attend un `report` : la boucle de vérification (pipeline verte citée, commentaire `Approved` lu et non supposé) est due dans tous les cas.

### REPORT ORCHESTRÉ — ADDITIF (uniquement si header `[ORCHESTRATION]`)

Le `report` de statut (voir MODE ORCHESTRÉ ci-dessus) se **surajoute** au protocole de phase — il ne le remplace pas et n'en est pas la source. En solo, ignorer les `report` ; le protocole de phase et le suivi pipeline restent dus à l'identique.

### LOOP JUGE — DÛ EN SOLO **ET** EN ORCHESTRÉ

**Invoquer le skill `malt-surface-exchange` (§ LOOP JUGE).** Le juge est un **sous-agent `judge`** lancé par CETTE surface au step 4, en contexte frais, **un juge NEUF par round**, jusqu'à ce qu'un juge rende `OK` (4 rounds max → escalade `[ASK]`). Il **remplace** le subagent `reviewer`. Son compte rendu est écrit par lui-même dans le fichier de la surface : `$WF/<TICKET>.md` en orchestré, `/Users/stephenbegot/claude-exchange-llm/_solo/<TICKET>.md` en solo (créé si absent). Il n'y a **plus de surface juge, plus d'inbox juge, plus de `/judge`**.

### INBOX D'ÉCHANGE — ADDITIF (uniquement si le header liste des inbox)

En mode orchestré, le prompt de départ (header de MON inbox, lu au démarrage via le lien du spawn) liste mes inbox. Poser `MYIN="$WF/<TICKET>.md"` (MON inbox — je l'écoute, j'y reçois instructions/conflits, les juges y archivent leurs comptes rendus) et `OIN="$WF/_inbox/orchestrator.md"` (inbox orchestrateur — j'y poste STEP/DONE). Annoncer ces chemins (ABSOLUS) à l'utilisateur au démarrage (skill § ANNONCE DES CHEMINS). Alors :
- **Notification à chaque étape (OBLIGATOIRE, couplée au header)** : à chaque `cmux-tab.sh phase …` du protocole ci-dessus, poser aussi `cmux-tab.sh note --notify "$ORCH_SURFACE" "$OIN" "<TICKET>[dev]" "STEP:<nom>" "<ce qui est fait/prouvé>"` (skill § NOTIFICATION À CHAQUE ÉTAPE). Les jalons pipeline verte (cité), conflits GitLab, `/end` complet, verdict juge sont explicitement dus.
- **Coordination dev↔dev** : si un `CONFLICT` apparaît dans `$MYIN` (posté par l'orchestrateur ou un autre dev), coordonner en postant dans l'inbox de l'autre dev (`$WF/<autre>.md`) avant de toucher la zone chaude, et lire `$MYIN` pour la réponse (skill § COORDINATION DEV↔DEV).
- **Checklist `DONE`** en fin (skill § CHECKLIST DONE FINALE) : posée sur `$OIN` avant de clore.
En solo : cet additif est sans objet (seul le `SURFACE_FILE` du loop juge existe).

### Étapes

1. **Lire le ticket JIRA** fourni (skill `/jira`) : titre, description métier (contexte), et surtout le **champ "Prompt" (`customfield_11956`)** = consigne d'implémentation détaillée à suivre. → onglet `[PLAN] <résumé>` puis étudier le plan.
   - **Lecture du champ Prompt** : `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET>?fields=summary,description,customfield_11956"` — le champ est un doc ADF ; en extraire le texte. C'est LUI la consigne d'implémentation, pas la description.
   - **Fallback** : si `customfield_11956` est vide (ancien ticket), retomber sur un éventuel bloc `PROMPT` en fin de description.
   - **Si aucun ticket fourni** (demande directe) : demander le numéro de ticket JIRA ; sinon demander l'**EPIC** puis créer soi-même le ticket (skill `/jira`).
2. **Worktree + branche** — créer worktree + branche selon GIT WORKFLOW (base `origin/master`, hors repo). *(Mode orchestré : `report … IN_PROGRESS`.)*
3. **Explore → liste de tests métier (GATE) → TDD rouge→vert** — implémentation en sous-agents (skill `malt-orchestration` — délégation + dimensionner le model). → onglet `[IMPL] <résumé>` (sauf pendant le GATE 3b → `[ASK]`).

   **3a — Explore** (skill commons § VÉRIFICATION & BOUCLES, levier 5) : vérifier le plan contre le code réel via le subagent `explorer` (`path:line` réels, patterns jumeaux, contrats partagés). Le champ `Prompt` est le plan mâché → le CONFIRMER, pas tout re-découvrir. Ticket sur `erp/*` → skill `malt-accounting-domain`. À alléger si le diff tient en une phrase.

   **3b — Liste de tests métier — GATE UTILISATEUR (RÈGLE ABSOLUE).** AVANT d'écrire le moindre test ou ligne de code, réfléchir aux cas de test **métier** que le comportement visé doit couvrir, et **soumettre à l'utilisateur une simple liste de TITRES de tests** — une ligne chacun, en langage métier, sans implémentation (juste de quoi valider que le comportement métier ciblé est le bon). Onglet `[ASK]`, prose normale (commons § QUESTIONS À CHOIX). **Attendre la validation/correction de l'utilisateur avant de coder.** C'est SA validation du besoin métier. (Diff purement mécanique sans enjeu métier — renommage, déplacement — la liste peut se réduire à 1-2 titres, mais le gate reste posé.)

   **3c — TDD rouge → vert (systématique), DÉLÉGUÉE** — skills `superpowers:test-driven-development` + `malt-backend-tdd`. Pour chaque test de la liste validée : écrire d'abord le **test rouge**, puis le **code de prod minimal** qui le fait passer au **vert**. **Jamais de code de prod avant un test rouge qui l'exige.** Recouvre COUVERTURE DE CODE (chaque ligne touchée exercée).

   **DÉLÉGATION OBLIGATOIRE (skill `malt-orchestration` § DÉLÉGATION DE L'IMPLÉMENTATION).** La surface tourne en Opus : Opus **ne tape PAS le code inline**. Opus produit un **plan d'implémentation précis** (fichiers `path:line`, signatures, pattern jumeau à imiter, tests validés au GATE + ce que chacun exerce, pièges), puis **délègue tests + code à un sous-agent `sonnet`** qui exécute la boucle rouge→vert et retourne une CONCLUSION (fichiers, sortie verte citée). Découper en plusieurs sous-agents si zones indépendantes. Opus ne reprend la main que pour vérifier (step 4-5) et arbitrer. **Exception** — garder sur Opus uniquement l'implémentation réellement piégeuse (invariants, concurrence, event-sourcing non trivial) où un `sonnet` échouerait. Consommation 100 % Opus = anti-pattern (Opus a codé au lieu de déléguer).

   **Transverse à 3a-3c :** poser les **questions MÉTIER** nécessaires (jamais de demande de droits). **ESCALADE ARCHI** (commons § DÉCISIONS D'ARCHI & TRADEOFFS) : choix d'archi ou tradeoff différenciant non tranché par le `Prompt` → STOPPER, escalader (`[ASK]`), attendre l'accord avant de coder cette partie.
4. **Vérification avant livraison — `/goal` borné + revue adverse en contexte frais** (skill commons § VÉRIFICATION & BOUCLES, leviers 2-3). Ne PAS juger "à l'œil" dans le contexte qui a écrit le code.
   - **Poser un `/goal` borné** : 0 test en échec sur les modules touchés, service(s) touché(s) qui bootent (step 5), 0 violation Sonar new-code + coverage new-code ≥ 80 %, scope = besoin du ticket et rien de plus. **Borne dure : ~6 tours** — si la condition ne tient pas, surfacer (`[BLOCK]`), jamais d'acharnement.
   - **LOOP JUGE — OBLIGATOIRE, solo comme orchestré** (skill `malt-surface-exchange` § LOOP JUGE). Lancer un sous-agent **`judge`** frais (`CHECKPOINT=pre-push`, `ROUND=N`, worktree/branche, `REPORT_FILE=<SURFACE_FILE>`, consigne verbatim, ce que je prétends avoir fait, GAPS du round précédent + corrections). Verdict `NEEDS_WORK` → traiter chaque GAP (correctness/scope, **ne pas sur-corriger** le style) puis **round N+1 avec un juge NEUF**. **Ne pas pousser avant qu'un juge rende `OK`.** 4 rounds max → escalade `[ASK]` en citant les GAPS résiduels.
5. **SMOKE-RUN LOCAL des services modifiés (OBLIGATOIRE)** — suivre le skill commons **§ SMOKE-RUN LOCAL** : mapper le diff vers les projets applicatifs touchés, déléguer au subagent `smoke-runner`, ne pas pousser un service cassé par le diff (bug bloquant), env local indispo = non bloquant (consigner en Tradeoffs).
6. **Statut JIRA → "In Progress / Dev"** (skill `/jira`) — **c'est ICI que le dev commence : s'auto-assigner le ticket à `stephen.begot` MAINTENANT** (pas avant), via `PUT /rest/api/3/issue/<TICKET>/assignee` avec l'`accountId` résolu par `/rest/api/3/user/search?query=stephen.begot@malt.com`. Le passage `In Progress` et l'assignation vont de pair.
7. **Validation Sonar PRÉ-PUSH (OBLIGATOIRE, avant tout push)** — auto-relire le code produit contre les règles du quality gate Sonar et **corriger localement** avant de pousser (une pipeline rouge sur `*-sonar` = un cycle repush complet).
   - Règles actives + seuils du gate : note Obsidian `[[SonarQube Malt - Règles actives]]` (`/obsidian` recherche). Réutiliser cette pré-analyse plutôt que deviner.
   - Points de contrôle sur le diff : **Coverage new code ≥ 80 %** (chaque ligne main ajoutée/modifiée exercée par un test — recouvre COUVERTURE DE CODE) ; **0 violation new code** (littéraux dupliqués S1192, `when` > 30 branches S1479, params > 7 S107, duplication, etc.).
   - Ne pousser qu'une fois cette relecture passée. La vérif pipeline du `/end` (skill commons § /end AVEC MR) reste le filet de sécurité, pas le premier rempart.
8. **Push + MR** — pusher la branche puis **créer la MR** avec description respectant `/gitlab-resume`. **TITRE DE MR (GIT WORKFLOW)** : `[<TICKET>] Titre` (ex `[BILL-2854] Fix invoice rounding`), en anglais ; si aucun ticket → `[devscoot]`. Le subject du 1er commit suit ce format (il préremplit le titre de MR). **Mettre `@stephen.begot` en reviewer** (obligatoire), + labels de squad (skill `malt-squad-conventions`). Le header `[MR (<numMR>)]` est posé automatiquement par le hook. *(Mode orchestré : `report … MR_OPEN "<lien MR>"`.)*
9. **~~`/end`~~ → déplacé en step 15.** *(Le `/end` était historiquement ici, avant la pipeline et avant le merge : il devait « vérifier la pipeline » qui n'existait pas encore, était reporté, puis jamais refait. C'est la cause structurelle des `/end` manquants. Ne PAS le lancer ici. Numérotation conservée : les steps 10-16 sont référencés ailleurs.)*
10. **Suivi MR jusqu'au vert** — onglet `[PIPE (<numMR>)]` tant que la pipeline n'est pas verte. **Invoquer le skill `malt-pipeline-followup`** (source de vérité unique : lookup statut, pipelines parent-child, diagnostic + fix + repush, Sonar, conflits de rebase, boucle d'attente, heures calmes) et le suivre jusqu'à pipeline verte citée. Pipeline verte + MR en attente d'approval → revenir à `[MR (<numMR>)]`.
11. **Statut JIRA → "Review"** (skill `/jira`).
12. **Commentaires de `@stephen.begot` — LECTURE OBLIGATOIRE, JAMAIS PAR SUPPOSITION.** Avant toute attente ou tout `[WAIT]`, **fetch explicitement les notes de la MR** :
    ```
    glab api "projects/maltcommunity%2Fmalt%2Fapps%2Fmalt/merge_requests/<IID>/notes?per_page=100&sort=desc" \
      | python3 -c "import sys,json;[print(n['author']['username'],'|',repr(n['body'])) for n in json.load(sys.stdin) if not n.get('system')]"
    ```
    - **REQUEST CHANGES — RÈGLE ABSOLUE.** Tant que `@stephen.begot` n'a PAS posté `Approved`, ses commentaires sont des **demandes de changement** : pour chacun, **corriger** (fix + repush sur la branche, jamais master → `[IMPL]` puis `[PIPE (<numMR>)]`) **ou répondre** si c'est une question / un désaccord argumenté. **Après avoir traité TOUS les points, LUI REDEMANDER un `Approved`** : les changements ne valent jamais approbation. Reboucler jusqu'à un commentaire `Approved`.
    - **Détection du feu vert** : note **non-system** de `stephen.begot` dont le body `trim()` + minuscule vaut **`approved`**. **Un `Approved` ne vaut que s'il est POSTÉRIEUR au dernier repush.**
    - **AVANT de programmer un poll d'attente d'approbation : lancer cette commande une fois immédiatement.** Ne planifier une attente QUE si `Approved` est réellement absent. À chaque réveil, re-lancer (relire, jamais supposer). **HEURES CALMES 20h–7h (CLAUDE.md) : ne PAS programmer de poll d'approbation dans cette plage — STOPPER NET, relance manuelle le matin.**
13. **MERGE — seulement si `@stephen.begot` a posté un commentaire `Approved` (step 12) ET pipeline verte.** Il est reviewer mais NE PEUT PAS self-approve (token à son nom) → feu vert = **commentaire `Approved`**, pas l'approbation native. Tant qu'il n'existe pas : **NE JAMAIS MERGER.** Une fois réuni :
    1. **Rebase SANS relancer de pipeline** — un rebase nu relance une pipeline complète ; sur `master` très actif la branche redevient « behind » avant la fin → **boucle infinie**. Toujours `skip_ci` :
       ```
       glab api --method PUT "projects/maltcommunity%2Fmalt%2Fapps%2Fmalt/merge_requests/<IID>/rebase?skip_ci=true"
       ```
    2. **Merger AVEC SQUASH** (obligatoire) — `--squash` + message = titre de MR (`[<TICKET>] …`, sinon `[devscoot] …`), + supprimer la source branch :
       ```
       glab mr merge <IID> -R maltcommunity/malt/apps/malt --squash --remove-source-branch --yes \
         --message "[<TICKET>|devscoot] <titre MR>"
       ```
    Ne jamais merger sans `--squash`. Ne jamais merger sans le commentaire `Approved`.
14. **Après merge → Statut JIRA "To Validate"** (skill `/jira`). *(Mode orchestré : `report … MERGED "<lien MR>"` — c'est CE report qui débloque les dépendants. Ne pas l'oublier.)*
15. **`/end` — OBLIGATOIRE, une seule fois, ICI** (skill `end`, avec vérif pipeline — skill commons **§ /end AVEC MR**) : log du jour avec lien MR + lien JIRA + umbrella, et tradeoffs postés en commentaire JIRA **en anglais**. Puis clean du worktree (`git worktree remove`) et header `[END]`. **La fin de tour est BLOQUÉE par un hook tant que le `/end` d'une MR mergée n'est pas écrit dans le log du jour** — il est vérifié dans le fichier, pas sur déclaration.
16. **Livrable final** — retourner le tableau du skill commons **§ LIVRABLE FINAL** (JIRA / Statut / MR / `/end` / Obsidian / Tradeoffs / Résumé). Le point **Tradeoffs** est OBLIGATOIRE. *(Mode orchestré : poser la checklist `DONE` dans `$OIN` (inbox orchestrateur) — skill `malt-surface-exchange` § CHECKLIST DONE FINALE — prouvant pipeline verte citée, conflits résolus, `/end` complet, verdict juge `OK`.)*

**TRAVAIL DÉCOUVERT EN COURS DE ROUTE** — si ce `/dev` découvre du travail annexe : suivre le skill commons **§ TRAVAIL DÉCOUVERT** (créer un ticket dédié sous le parapluie, ne pas élargir son scope en douce, signaler à l'orchestrateur, ne pas l'orchestrer soi-même).

## Rappels transverses (voir CLAUDE.md et skill `malt-workflow-commons`)

- **ORCHESTRATION PAR SOUS-AGENTS** (skill `malt-orchestration`) : thread principal = orchestrateur ; déléguer exploration/recherche/analyse ; CONCLUSION pas dumps ; dimensionner le model.
- **TDD SYSTÉMATIQUE (step 3)** : liste de titres de tests métier soumise à l'utilisateur (GATE), puis rouge→vert (`superpowers:test-driven-development` + `malt-backend-tdd`). Jamais de code de prod avant un test rouge. Toute ligne touchée couverte ; vert obligatoire (sortie citée) avant de déclarer terminé.
- **GIT WORKFLOW** (CLAUDE.md) : jamais push/modif sur master ; worktree hors repo (base `origin/master`) + branche + MR ; merge UNIQUEMENT après un commentaire `Approved` de `@stephen.begot` (fetch les notes, ne jamais supposer, step 12) ; reviewer `@stephen.begot` obligatoire ; merge TOUJOURS `--squash` ; rebase TOUJOURS `skip_ci=true` ; jamais co-author ; jamais lancer les linters (hook husky) ; titre MR anglais `[<TICKET>]` sinon `[devscoot]` ; labels de squad (skill `malt-squad-conventions`) ; bloc de clôture obligatoire après push.
- **LANGUE** (CLAUDE.md) : toute écriture JIRA/GitLab/Notion en **ANGLAIS**.
- **TITRE DE SESSION** (CLAUDE.md) : commence par le numéro de ticket (`TICKET-123 description`).
