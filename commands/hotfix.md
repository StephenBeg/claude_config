---
description: WORKFLOW DE HOTFIX — corriger un bug de bout en bout. Phase 1 DIAGNOSTIC (analyser le bug, trouver la cause racine, vérifier contre le réel). Phase 2 : créer soi-même le ticket bug (demander OÙ), puis basculer dans le flow d'implémentation complet de /dev (worktree → tests → MR → /end → suivi pipeline → statuts JIRA). Déclenché quand l'utilisateur signale un bug à corriger (pas de ticket en entrée).
---

## Input

$ARGUMENTS

La description du bug (symptôme observé, contexte, éventuel lien Datadog/Sentry/MR/log). **Pas de ticket JIRA en entrée** — ce workflow crée lui-même son ticket bug après diagnostic. Si un numéro de ticket bug est déjà fourni → utiliser `/dev` à la place (le ticket existe).

`/hotfix` = **mix de `/plan` et `/dev`** : il **diagnostique** d'abord comme un plan (analyse, sources vérifiées, cause racine), **crée son propre ticket** (comme un plan crée ses tickets), puis **implémente de bout en bout** comme un `/dev`.

### QUESTIONS À CHOIX DE RÉPONSES — RÈGLE ABSOLUE

Quand ce workflow pose une question à l'utilisateur **avec des choix de réponses** (où créer le ticket, arbitrage de correction, `AskUserQuestion`) :

- **Explication détaillée AVANT les choix — obligatoire.** Exposer le problème point par point : contexte, ce qui est en jeu, pourquoi la décision se pose, et pour chaque option ses implications / tradeoffs.
- **INTERDICTION D'UTILISER CAVEMAN dans ce cas précis.** L'explication ET les libellés/descriptions des choix sont rédigés en prose normale, complète et claire. Caveman reste actif pour le reste de la session.

### ACCÈS JIRA — MCP ou fallback API REST (RÈGLE ABSOLUE)

Toute interaction JIRA (création ticket bug, transitions, commentaires) passe par le skill `/jira`. **Si le MCP Atlassian n'est PAS connecté** → **NE PAS bloquer** : fallback API REST v3 documenté dans `/jira` (curl + Basic auth). Vérifier au besoin : `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/myself"` → 200.

## WORKFLOW DE HOTFIX — RÈGLE ABSOLUE

**TOUTES les étapes sont OBLIGATOIRES, dans l'ordre. Deux phases : DIAGNOSTIC puis IMPLÉMENTATION.**

---

## PHASE 1 — DIAGNOSTIC (trouver la cause racine AVANT de coder)

Cette phase est le cœur qui distingue `/hotfix` d'un `/dev`. **Aucune correction ne démarre avant que la cause racine soit identifiée ET vérifiée contre le réel.** Invoquer le skill `superpowers:systematic-debugging` et le suivre.

**HEADER CMUX** : ce workflow utilise la **table unifiée des préfixes** (voir `/dev`, section « PRÉFIXES DE HEADER CMUX — TABLE UNIFIÉE » : `[PLAN] [IMPL] [PIPE (num)] [MR (num)] [ASK] [BLOCK] [WAIT] [CLEAN] [END]`, plus `[MAIN]` pour un orchestrateur). Dès qu'une MR existe, son numéro figure dans le header **aussi bien en `[PIPE (num)]` qu'en `[MR (num)]`**. La session **DOIT** mettre à jour le header dès qu'elle fait quelque chose, et peut revenir en arrière.

1. **Titre onglet** → `[PLAN] <résumé 3-4 mots du bug>` (diagnostic = phase d'analyse, rien de commencé). Le résumé décrit le bug réel, jamais "diag ticket X".

2. **Reproduire / cerner le symptôme** — à partir du `$ARGUMENTS` : quel est le comportement observé vs attendu ? Périmètre exact (un sous-ensemble qui plante = data/state, cf. `[[feedback_bug_diagnosis_before_fix]]`). Si un lien Datadog/Sentry/log est fourni → l'exploiter.

3. **Analyse — DÉLÉGUER à des sous-agents (ORCHESTRATION).** Localiser le code fautif, comprendre le chemin réellement emprunté. Sur repo Malt : note Obsidian `[[Monorepo Malt - Carte technique]]` d'abord (`/obsidian` recherche), sous-agent si insuffisant. Les sous-agents retournent une **CONCLUSION** (cause racine candidate + `path:line`), pas des dumps. **Dimensionner le model** (cf. DOSAGE DU MODÈLE, `/dev`) : `sonnet` (ou `haiku`) pour la **localisation** du code fautif ; réserver `opus` au sous-agent qui **raisonne la cause racine** d'un bug tordu (invariants, concurrence, chemin non évident).

4. **VÉRIFICATION DES SOURCES CONTRE LE RÉEL — RÈGLE ABSOLUE.** La mémoire (notes Obsidian, mémoire persistante) est un point de départ, jamais une vérité (drift fréquent). Avant d'ancrer un diagnostic :
   - **Code** : lire le fichier/symbole réel **sur `master` à jour** (`git fetch origin master` depuis `~/Documents/projects/malt`, ne rien éditer sur master — cf. GIT WORKFLOW). Toute citation = `path:line` vu dans le code courant.
   - **Runtime / prod** : pour tout fait sur le comportement en prod (état d'un FF, volumétrie, erreurs, chemin emprunté) → **vérifier via Datadog** (`/datadog`) ou **Sentry** (`/sentry-analyzer`) plutôt que supposer.
   - **JIRA / FF / config** : lire la source vivante (fichiers ff4j, app-config), pas la mémoire.
   - **Drift** : si le réel contredit une note Obsidian → corriger la note (`/obsidian` capture) dans la foulée.

5. **Cause racine confirmée — GATE.** Formuler explicitement : **le bug** (symptôme), **la cause racine** (`path:line` + pourquoi), **le fix envisagé** (borné, minimal — un hotfix corrige LE bug, pas de refacto opportuniste). Si plusieurs causes candidates ou fix non trivial → poser une question à choix à l'utilisateur (prose normale, cf. règle ci-dessus). **Ne pas passer en Phase 2 tant que la cause racine n'est pas tenue.**

---

## PHASE 2 — CRÉATION DU TICKET BUG + IMPLÉMENTATION

6. **Créer le ticket BUG — demander OÙ (RÈGLE ABSOLUE).** `/hotfix` crée lui-même son ticket (comme `/plan`), mais l'emplacement est une décision utilisateur :
   - **Demander à l'utilisateur** (question à choix, prose normale) : sous quelle **EPIC / User Story parapluie** rattacher le bug, ou projet + type par défaut. Proposer un défaut sensé si le contexte le suggère (ex : EPIC du domaine touché), l'utilisateur tranche.
   - **Type `Bug`** si disponible dans le projet, sinon `Task` avec titre préfixé `[BUG]`.
   - **Titre + Description en ANGLAIS**, point de vue métier/reproductible : symptôme observé, étapes de repro, comportement attendu, cause racine identifiée (résumé), impact. Mise en forme propre (jamais un paragraphe brut), lisible par un non-technique.
   - **Champ "Prompt" (`customfield_11956`) = la consigne de fix, EN FRANÇAIS** (cf. `[[reference_jira_prompt_field]]`) : cause racine avec `path:line`, fix exact à appliquer, cas de test attendus (dont un test qui reproduit le bug d'abord), pièges connus. Écriture ADF via API REST (cf. `/jira`).
   - **Label `Accounting/Bookkeeping` OBLIGATOIRE à la création** (`"labels":["Accounting/Bookkeeping"]` dans le payload).
   - **NE PAS assigner le ticket à la création.** L'assignation à `stephen.begot` intervient plus tard, au step "Statut JIRA → In Progress / Dev" hérité de `/dev` (étape 7), quand le dev démarre réellement.
   - Récupérer le **numéro de ticket** créé — il pilote tout le reste (titre de session, MR, statuts).

7. **Basculer dans le FLOW D'IMPLÉMENTATION complet de `/dev`.** À partir d'ici, **suivre le workflow `/dev` étapes 2→15 à la lettre** (le ticket bug créé à l'étape 6 EST le ticket d'entrée de `/dev`), avec un **RÉORDONNANCEMENT SPÉCIFIQUE HOTFIX : la MR est créée le plus tôt possible, dès le fix appliqué, AVANT toute vérification locale lourde (suite de tests complète, build, smoke-run).** But : lancer la pipeline distante au plus vite pour voir si le fix suffit, sans attendre la validation locale.

   **7a — MR AU PLUS TÔT (avant tests/build locaux) :**
   - Worktree + branche (base `origin/master`, hors repo) — GIT WORKFLOW.
   - **TDD sur le bug** : écrire d'abord un test qui **reproduit le bug** (rouge), puis appliquer le fix. **Confirmer localement le passage rouge→vert du SEUL test qui cible le bug** (pas la suite complète). Recouvre COUVERTURE DE CODE — toute ligne touchée exercée par un test. Utiliser des sous-agents (ORCHESTRATION).
   - **Dès le fix appliqué et ce test ciblé au vert** → Statut JIRA → "In Progress / Dev" (**c'est ICI qu'on s'auto-assigne le ticket à `stephen.begot`**, `PUT /issue/<TICKET>/assignee`, pas avant), puis **Push + MR IMMÉDIATEMENT** (`/gitlab-resume`, reviewer `@stephen.begot`, label `squad-accounting`, **titre PRÉFIXÉ `[hotfix]`** — ex `[hotfix] Fix invoice rounding` — anglais ; ce préfixe hotfix prime sur le format `[<TICKET>]` de `/dev`). Onglet `[MR (<numMR>)] <résumé>`. **La pipeline distante tourne dès maintenant.**

   **7b — VÉRIFICATION LOCALE LOURDE, EN PARALLÈLE DE LA PIPELINE (après la MR) :**
   - Pendant que la pipeline tourne, lancer la **suite de tests complète des modules touchés + le build** localement, et la **SMOKE-RUN LOCAL** des services applicatifs touchés (bootRun via sous-agent + background + boucle `until` sur `Started …Application in`, jamais `Monitor`).
   - **Vérification `/goal` borné + revue adverse en contexte frais** (VÉRIFICATION & BOUCLES de `/dev`, leviers 2-3) : `/goal` sur 0 test en échec + service qui boote + scope = LE bug et rien d'autre, borne ~6 tours ; revue adverse déléguée au subagent `reviewer` (contexte frais, `opus`) qui ne voit QUE le diff + la consigne du fix et cherche à réfuter (le fix corrige-t-il vraiment la cause racine ? cas limite ? effet de bord ?). Traiter correctness/scope, ne pas sur-corriger. Ne JAMAIS juger dans le contexte qui a écrit le fix.
   - Validation Sonar (le pré-push est devenu un post-push ici — c'est assumé : la MR existe déjà, on valide en parallèle).
   - **Si une vérif locale échoue** (test, build, smoke-run, judge, Sonar) → fixer, commit + **repush sur la branche de la MR** (jamais master), la pipeline se relance. Onglet `[IMPL]`/`[PIPE (<numMR>)]`.

   **7c — CLÔTURE (inchangé) :**
   - `/end` (avec vérif pipeline), suivi MR jusqu'au vert, statut JIRA → "Review".
   - Suivi pipeline / attente `Approved` : boucle `until` en background ou `/loop` auto-cadencé (VÉRIFICATION & BOUCLES levier 4 ; **`Monitor` interdit**).
   - Lecture des commentaires `@stephen.begot` (jamais par supposition). **Request changes** : tant que pas de `Approved`, ses commentaires = demandes de changement → fixer (`[IMPL]`/`[PIPE (<numMR>)]`) ou répondre, puis **LUI REDEMANDER un `Approved`** (les changements ne valent jamais approbation). Merge UNIQUEMENT après commentaire `Approved` **postérieur au dernier repush** + pipeline verte (rebase `skip_ci=true` puis `--squash`, **message de squash préfixé `[hotfix]`**).
   - Statut JIRA → "To Validate". Livrable final (tableau `/dev` étape 15).

   **Onglet CMUX** : suivre la table unifiée — diagnostic `[PLAN]` → correctif + MR au plus tôt `[IMPL]`→`[MR (<numMR>)]` → vérif locale en parallèle `[IMPL]`/`[PIPE (<numMR>)]` → attente approval `[MR (<numMR>)]` → clean `[CLEAN]` → `[END]`. Retours arrière autorisés (échec vérif locale ou request changes → `[IMPL]` → `[PIPE (<numMR>)]` → `[MR (<numMR>)]`).

## URGENCE — un hotfix reste borné (RÈGLE ABSOLUE)

Un `/hotfix` corrige **LE bug diagnostiqué, rien d'autre**. Ne pas élargir : pas de refacto, pas de nettoyage opportuniste, pas de correction de bugs annexes découverts en route. Si un autre bug / dette est découvert → créer un ticket dédié sous le même parapluie et le signaler (cf. `/dev` section « TRAVAIL DÉCOUVERT EN COURS DE ROUTE »), jamais l'enfouir dans le commit du hotfix.

## Rappels transverses (voir CLAUDE.md et /dev)

- **systematic-debugging AVANT tout fix** : cause racine identifiée + vérifiée contre le réel (code `master` à jour, Datadog/Sentry pour le runtime) avant de coder.
- **ORCHESTRATION PAR SOUS-AGENTS** : thread principal = orchestrateur ; déléguer exploration/diagnostic/analyse de gros outputs ; les sous-agents retournent une CONCLUSION, pas des dumps. **Dimensionner le model de chaque sous-agent** (cf. section DOSAGE DU MODÈLE DES SOUS-AGENTS de `/dev`) : `haiku` mécanique, `sonnet` exploration/localisation/impl cadrée/tests, `opus` réservé au raisonnement de cause racine et à l'implémentation piégeuse — jamais `opus` par réflexe.
- **COUVERTURE DE CODE** : un test qui reproduit le bug (rouge→vert) ; toute ligne touchée couverte ; vert obligatoire avant de déclarer terminé.
- **VÉRIFICATION & BOUCLES** (section de `/dev`) : preuve jamais affirmation ; `/goal` borné (0 test échec + boot + scope = LE bug) ; revue adverse en contexte frais (sous-agent `opus` / `/code-review`) qui vérifie que le fix règle la cause racine sans effet de bord ; `/loop` option d'attente (jamais `Monitor`).
- **GIT WORKFLOW** : jamais toucher master ; worktree hors repo (base `origin/master`) + branche + MR ; reviewer `@stephen.begot` ; merge seulement après commentaire `Approved` (fetch les notes, ne jamais supposer) ; rebase `skip_ci=true` + merge `--squash` ; jamais co-author ; jamais lancer les linters (hook husky) ; **titre MR PRÉFIXÉ `[hotfix]`** anglais (prime sur le format `[<TICKET>]` de `/dev`) ; label `squad-accounting` ; bloc de clôture obligatoire après push.
- **LANGUE** : toute écriture JIRA/GitLab/Notion en **ANGLAIS** ; seul le champ `Prompt` (`customfield_11956`) en français.
- **TITRE DE SESSION** : dès le ticket bug créé, commence par son numéro (`TICKET-123 description`).
- **/end AVEC MR** : vérif pipeline verte avant de clore (child pipeline job-factory ; Sonar via `/sonar` ; `Monitor` interdit — boucle `until` en background).
