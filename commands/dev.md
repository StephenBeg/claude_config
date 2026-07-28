---
description: WORKFLOW DE DEV — implémenter un ticket JIRA de bout en bout (worktree → tests → MR → /end → suivi pipeline → statuts JIRA). Déclenché quand un ticket JIRA est fourni en entrée.
---

## Input

$ARGUMENTS

Le ticket JIRA à implémenter (numéro). La consigne d'implémentation vit dans le **champ JIRA "Prompt"** (`customfield_11956`), PAS dans la description. Si un préambule `[ORCHESTRATION CMUX]` est présent → **MODE ORCHESTRÉ** (voir ci-dessous).

**RÈGLES COMMUNES — invoquer le skill `malt-workflow-commons` EN PREMIER.** Il porte les règles partagées par `/dev` `/plan` `/hotfix` (source de vérité unique) : **§ QUESTIONS À CHOIX DE RÉPONSES**, **§ ACCÈS JIRA**, **§ PRÉFIXES DE HEADER CMUX**, **§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL**, **§ VÉRIFICATION & BOUCLES DE CONTRÔLE**, **§ SMOKE-RUN LOCAL**, **§ /end AVEC MR — VÉRIF PIPELINE**, **§ TRAVAIL DÉCOUVERT EN COURS DE ROUTE**, **§ LIVRABLE FINAL**. Ce workflow y renvoie par le nom de section.

## WORKFLOW DE DEV — RÈGLE ABSOLUE

**TOUTES les étapes sont OBLIGATOIRES, dans l'ordre. Aucune n'est optionnelle.**

### MODE ORCHESTRÉ — report de statut (OBLIGATOIRE si lancé par un orchestrateur de plan)

Si le prompt d'entrée contient un préambule `[ORCHESTRATION CMUX]` avec `STATUS_DIR=<dir> TICKET=<ticket>`, un orchestrateur supervise ce ticket et **attend les statuts** pour déclencher les tickets dépendants. Reporter à **chaque transition de phase** :
```
~/.claude/scripts/cmux-tab.sh report <STATUS_DIR> <TICKET> <STATE> "<detail>"
```
`STATE` ∈ `IN_PROGRESS` (worktree créé) | `MR_OPEN` (MR créée, lien MR en detail) | `MERGED` (MR mergée par l'humain, lien MR en detail) | `BLOCKED` (blocage nécessitant l'humain, raison en detail). **Ne jamais clore la tâche sans avoir reporté `MERGED` ou `BLOCKED`** — l'orchestrateur en dépend. (Hors mode orchestré : ignorer les `report`.)

### TITRE D'ONGLET CMUX — suivi visuel (OBLIGATOIRE)

Suivre le skill `malt-workflow-commons` **§ PRÉFIXES DE HEADER CMUX** (table unifiée). La session met à jour le header **dès qu'elle fait quelque chose** (changement de phase) et peut **revenir en arrière**. Dès qu'une MR existe, son numéro figure dans le header aussi bien en `[PIPE (num)]` qu'en `[MR (num)]`.
Correspondance étapes : lecture ticket/étude → `[PLAN]` ; implémentation → `[IMPL]` ; suivi pipeline verte → `[PIPE (num)]` ; MR en attente d'approval → `[MR (num)]` ; clean worktree → `[CLEAN]` ; fin (MR mergée + `/end`) → `[END]`.

### Étapes

1. **Lire le ticket JIRA** fourni (skill `/jira`) : titre, description métier (contexte), et surtout le **champ "Prompt" (`customfield_11956`)** = consigne d'implémentation détaillée à suivre. → onglet `[PLAN] <résumé>` puis étudier le plan.
   - **Lecture du champ Prompt** : `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET>?fields=summary,description,customfield_11956"` — le champ est un doc ADF ; en extraire le texte. C'est LUI la consigne d'implémentation, pas la description.
   - **Fallback** : si `customfield_11956` est vide (ancien ticket), retomber sur un éventuel bloc `PROMPT` en fin de description.
   - **Si aucun ticket fourni** (demande directe) : demander le numéro de ticket JIRA ; sinon demander l'**EPIC** puis créer soi-même le ticket (skill `/jira`).
2. **Worktree + branche** — créer worktree + branche selon GIT WORKFLOW (base `origin/master`, hors repo). *(Mode orchestré : `report … IN_PROGRESS`.)*
3. **Explore → Plan → Code** (skill commons § VÉRIFICATION & BOUCLES, levier 5) — avant de coder, **vérifier le plan contre le code réel** via le subagent **`explorer`**. Le champ `Prompt` est déjà le plan mâché ; l'explore le CONFIRME (`path:line` réels, patterns jumeaux, contrats partagés), pas tout re-découvrir. À **sauter** si le diff tient en une phrase. Puis implémenter en **utilisant obligatoirement des sous-agents** (ORCHESTRATION, CLAUDE.md — **dimensionner le model** cf. CLAUDE.md § DOSAGE DU MODÈLE). Couverture de tests obligatoire (COUVERTURE DE CODE). Poser les **questions MÉTIER** nécessaires (jamais de demande de droits). → onglet `[IMPL] <résumé>`.
4. **Vérification avant livraison — `/goal` borné + revue adverse en contexte frais** (skill commons § VÉRIFICATION & BOUCLES, leviers 2-3). Ne PAS juger "à l'œil" dans le contexte qui a écrit le code.
   - **Poser un `/goal` borné** : 0 test en échec sur les modules touchés, service(s) touché(s) qui bootent (step 5), 0 violation Sonar new-code + coverage new-code ≥ 80 %, scope = besoin du ticket et rien de plus. **Borne dure : ~6 tours** — si la condition ne tient pas, surfacer (`[BLOCK]`), jamais d'acharnement.
   - **Revue adverse déléguée au subagent `reviewer`** (contexte frais, `opus`) : ne voit QUE le diff (`git diff origin/master...`) + la consigne (`Prompt`) + les critères, cherche à **réfuter**. Retourne des **GAPS**. Traiter correctness/scope ; **ne pas sur-corriger** le reste.
5. **SMOKE-RUN LOCAL des services modifiés (OBLIGATOIRE)** — suivre le skill commons **§ SMOKE-RUN LOCAL** : mapper le diff vers les projets applicatifs touchés, déléguer au subagent `smoke-runner`, ne pas pousser un service cassé par le diff (bug bloquant), env local indispo = non bloquant (consigner en Tradeoffs).
6. **Statut JIRA → "In Progress / Dev"** (skill `/jira`) — **c'est ICI que le dev commence : s'auto-assigner le ticket à `stephen.begot` MAINTENANT** (pas avant), via `PUT /rest/api/3/issue/<TICKET>/assignee` avec l'`accountId` résolu par `/rest/api/3/user/search?query=stephen.begot@malt.com`. Le passage `In Progress` et l'assignation vont de pair.
7. **Validation Sonar PRÉ-PUSH (OBLIGATOIRE, avant tout push)** — auto-relire le code produit contre les règles du quality gate Sonar et **corriger localement** avant de pousser (une pipeline rouge sur `*-sonar` = un cycle repush complet).
   - Règles actives + seuils du gate : note Obsidian `[[SonarQube Malt - Règles actives]]` (`/obsidian` recherche). Réutiliser cette pré-analyse plutôt que deviner.
   - Points de contrôle sur le diff : **Coverage new code ≥ 80 %** (chaque ligne main ajoutée/modifiée exercée par un test — recouvre COUVERTURE DE CODE) ; **0 violation new code** (littéraux dupliqués S1192, `when` > 30 branches S1479, params > 7 S107, duplication, etc.).
   - Ne pousser qu'une fois cette relecture passée. La vérif pipeline du `/end` (skill commons § /end AVEC MR) reste le filet de sécurité, pas le premier rempart.
8. **Push + MR** — pusher la branche puis **créer la MR** avec description respectant `/gitlab-resume`. **TITRE DE MR (GIT WORKFLOW)** : `[<TICKET>] Titre` (ex `[BILL-2854] Fix invoice rounding`), en anglais ; si aucun ticket → `[devscoot]`. Le subject du 1er commit suit ce format (il préremplit le titre de MR). **Mettre `@stephen.begot` en reviewer** (obligatoire), label `squad-accounting`. → onglet `[MR (<numMR>)] <résumé>`. *(Mode orchestré : `report … MR_OPEN "<lien MR>"`.)*
9. **`/end`** — lancer le `/end` soi-même (skill `end`, avec vérif pipeline si MR — skill commons **§ /end AVEC MR**). → onglet `[END] <résumé>` une fois MR mergée + `/end` fait.
10. **Suivi MR jusqu'au vert** — → onglet `[PIPE (<numMR>)] <résumé>` tant que la pipeline n'est pas verte. Suivre jusqu'à pipeline verte (attente : boucle `until` en background ou `/loop` auto-cadencé — skill commons § VÉRIFICATION & BOUCLES levier 4 ; **`Monitor` interdit** ; **HEURES CALMES 20h–7h : STOPPER NET — CLAUDE.md**). Corriger automatiquement : problème de **pipeline** (skill commons § /end AVEC MR) ; **rebase impossible par GitLab** (conflits) → résoudre, repush. Pipeline verte + MR en attente d'approval → revenir à `[MR (<numMR>)]`.
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
15. **Livrable final** — retourner le tableau du skill commons **§ LIVRABLE FINAL** (JIRA / Statut / MR / `/end` / Obsidian / Tradeoffs / Résumé). Le point **Tradeoffs** est OBLIGATOIRE.

**TRAVAIL DÉCOUVERT EN COURS DE ROUTE** — si ce `/dev` découvre du travail annexe : suivre le skill commons **§ TRAVAIL DÉCOUVERT** (créer un ticket dédié sous le parapluie, ne pas élargir son scope en douce, signaler à l'orchestrateur, ne pas l'orchestrer soi-même).

## Rappels transverses (voir CLAUDE.md et skill `malt-workflow-commons`)

- **ORCHESTRATION PAR SOUS-AGENTS** (CLAUDE.md) : thread principal = orchestrateur ; déléguer exploration/recherche/analyse ; les sous-agents retournent une CONCLUSION, pas des dumps ; **dimensionner le model** (§ DOSAGE DU MODÈLE, CLAUDE.md).
- **COUVERTURE DE CODE** : toute ligne ajoutée/modifiée couverte par un test ; TDD (`malt-backend-tdd`) pour nouveau comportement, `malt-test-coverage` sur code existant ; vert obligatoire avant de déclarer terminé.
- **GIT WORKFLOW** (CLAUDE.md) : jamais push/modif sur master ; worktree hors repo (base `origin/master`) + branche + MR ; merge UNIQUEMENT après un commentaire `Approved` de `@stephen.begot` (fetch les notes, ne jamais supposer, step 12) ; reviewer `@stephen.begot` obligatoire ; merge TOUJOURS `--squash` ; rebase TOUJOURS `skip_ci=true` ; jamais co-author ; jamais lancer les linters (hook husky) ; titre MR anglais `[<TICKET>]` sinon `[devscoot]` ; label `squad-accounting` ; bloc de clôture obligatoire après push.
- **LANGUE** (CLAUDE.md) : toute écriture JIRA/GitLab/Notion en **ANGLAIS**.
- **TITRE DE SESSION** (CLAUDE.md) : commence par le numéro de ticket (`TICKET-123 description`).
