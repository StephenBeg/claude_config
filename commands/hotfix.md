---
description: WORKFLOW DE HOTFIX — corriger un bug de bout en bout. Phase 1 DIAGNOSTIC (analyser le bug, trouver la cause racine, vérifier contre le réel). Phase 2 : créer soi-même le ticket bug (demander OÙ), puis implémenter de bout en bout (worktree → tests → MR au plus tôt → /end → suivi pipeline → statuts JIRA). Déclenché quand l'utilisateur signale un bug à corriger (pas de ticket en entrée).
---

## Input

$ARGUMENTS

La description du bug (symptôme observé, contexte, éventuel lien Datadog/Sentry/MR/log). **Pas de ticket JIRA en entrée** — ce workflow crée lui-même son ticket bug après diagnostic. Si un numéro de ticket bug est déjà fourni → lancer `/dev` à la place (le ticket existe).

`/hotfix` **diagnostique d'abord** (analyse, sources vérifiées, cause racine), **crée son propre ticket bug**, puis **implémente de bout en bout** — avec un réordonnancement propre au hotfix : **la MR part au plus tôt** pour lancer la pipeline distante sans attendre la vérif locale lourde.

**RÈGLES COMMUNES — invoquer le skill `malt-workflow-commons` EN PREMIER.** Il porte les règles partagées : **§ QUESTIONS À CHOIX DE RÉPONSES**, **§ DÉCISIONS D'ARCHI & TRADEOFFS — ESCALADE OBLIGATOIRE**, **§ ACCÈS JIRA**, **§ PRÉFIXES DE HEADER CMUX**, **§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL**, **§ VÉRIFICATION & BOUCLES DE CONTRÔLE**, **§ SMOKE-RUN LOCAL**, **§ /end AVEC MR — VÉRIF PIPELINE**, **§ TRAVAIL DÉCOUVERT**, **§ LIVRABLE FINAL**. Ce workflow y renvoie par le nom de section. **Suivi de pipeline (step 7)** : skill `malt-pipeline-followup` (source de vérité unique dédiée).

**ESCALADE ARCHI — RÈGLE ABSOLUE POUR CE HOTFIX.** Un hotfix corrige LE bug, borné et minimal (pas de refacto). Si le fix « propre » exige une **décision d'archi** (nouveau pattern, changement de contrat/schéma, dépendance) ou expose un **tradeoff différenciant** (ex : fix minimal qui masque vs fix structurel qui change le comportement) → **STOPPER et escalader à l'utilisateur** (§ DÉCISIONS D'ARCHI & TRADEOFFS) avant de coder. Ne jamais choisir seul l'ampleur du fix quand elle change le résultat.

## WORKFLOW DE HOTFIX — RÈGLE ABSOLUE

**TOUTES les étapes sont OBLIGATOIRES, dans l'ordre. Deux phases : DIAGNOSTIC puis IMPLÉMENTATION.**

**HEADER CMUX — PROTOCOLE DE PHASE OBLIGATOIRE EN SOLO ET EN ORCHESTRÉ (RÈGLE ABSOLUE).** Le header et le suivi pipeline ne sont PAS réservés au mode orchestré : `/hotfix` étant presque toujours lancé en solo, la discipline s'applique intégralement. À **chaque** transition, exécuter immédiatement `~/.claude/scripts/cmux-tab.sh phase <PREFIX> "<résumé>"` :

| Phase hotfix | Préfixe |
|---|---|
| Diagnostic (Phase 1) | `PLAN` |
| Cause racine à arbitrer / question (step 5-6) | `ASK` |
| Correctif + push MR au plus tôt (step 7a) | `IMPL` puis `MR` (numéro : `[MR (1234)]`) |
| Vérif locale lourde en parallèle (step 7b) | `IMPL` / `PIPE` selon repush |
| Attente approval (step 7c) | `MR (<numMR>)` |
| Clean worktree | `CLEAN` |
| Fin (MR mergée + `/end`) | `END` |

Sémantique, retours arrière et table unifiée : skill commons **§ PRÉFIXES DE HEADER CMUX** (source de vérité). Le résumé décrit CE QU'ON FAIT (le bug réel), jamais "diag ticket X". **Suivi pipeline (`malt-pipeline-followup`) + lecture des notes / attente `Approved` (step 7c) = dus en solo aussi**, jamais « lâchés » faute d'orchestrateur qui attend.

---

## PHASE 1 — DIAGNOSTIC (trouver la cause racine AVANT de coder)

Cœur qui distingue `/hotfix` d'un `/dev`. **Aucune correction ne démarre avant que la cause racine soit identifiée ET vérifiée contre le réel.** Invoquer le skill `superpowers:systematic-debugging` et le suivre.

1. **Titre onglet** → `[PLAN] <résumé 3-4 mots du bug>` (diagnostic = analyse). Le résumé décrit le bug réel, jamais "diag ticket X".
2. **Reproduire / cerner le symptôme** — à partir du `$ARGUMENTS` : comportement observé vs attendu ? Périmètre exact (un sous-ensemble qui plante = data/state, cf. `[[feedback_bug_diagnosis_before_fix]]`). Lien Datadog/Sentry/log fourni → l'exploiter.
3. **Analyse — DÉLÉGUER à des sous-agents (skill `malt-orchestration`).** Localiser le code fautif, comprendre le chemin réellement emprunté. Sur repo Malt : skill `malt-accounting-domain` (si accounting/NetSuite) ou note Obsidian `[[Monorepo Malt - Carte technique]]` d'abord (`/obsidian` recherche), sous-agent si insuffisant. Les sous-agents retournent une **CONCLUSION** (cause racine candidate + `path:line`), pas des dumps. **Dimensionner le model** (skill `malt-orchestration`) : `sonnet`/`haiku` pour la **localisation** ; `opus` réservé au sous-agent qui **raisonne la cause racine** d'un bug tordu (invariants, concurrence, chemin non évident).
4. **VÉRIFIER LES SOURCES CONTRE LE RÉEL** — suivre le skill commons **§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL** : code réel sur `master` à jour (`git fetch origin master` depuis `~/Documents/projects/malt`, ne rien éditer sur master — GIT WORKFLOW) avec `path:line` du code courant ; runtime via Datadog (`/datadog`) ou Sentry (`/sentry-analyzer`) ; JIRA/FF/config = source vivante ; corriger la note Obsidian en cas de drift.
5. **Cause racine confirmée — GATE.** Formuler explicitement : **le bug** (symptôme), **la cause racine** (`path:line` + pourquoi), **le fix envisagé** (borné, minimal — un hotfix corrige LE bug, pas de refacto). Plusieurs causes candidates ou fix non trivial → question à choix (skill commons § QUESTIONS À CHOIX). **Ne pas passer en Phase 2 tant que la cause racine n'est pas tenue.**

---

## PHASE 2 — CRÉATION DU TICKET BUG + IMPLÉMENTATION

6. **Créer le ticket BUG — demander OÙ (RÈGLE ABSOLUE).** `/hotfix` crée lui-même son ticket, mais l'emplacement est une décision utilisateur :
   - **Demander à l'utilisateur** (question à choix, skill commons § QUESTIONS À CHOIX) : sous quelle **EPIC / User Story parapluie** rattacher le bug, ou projet + type par défaut. Proposer un défaut sensé (ex : EPIC du domaine touché), l'utilisateur tranche.
   - **Type `Bug`** si disponible, sinon `Task` avec titre préfixé `[BUG]`.
   - **Titre + Description en ANGLAIS**, point de vue métier/reproductible : symptôme, étapes de repro, comportement attendu, cause racine (résumé), impact. Mise en forme propre, lisible par un non-technique.
   - **Champ "Prompt" (`customfield_11956`) = la consigne de fix, EN FRANÇAIS** (cf. `[[reference_jira_prompt_field]]`) : cause racine avec `path:line`, fix exact, cas de test attendus (dont un test qui reproduit le bug d'abord), pièges. Écriture ADF via API REST (skill `/jira`).
   - **Label JIRA de squad obligatoire à la création** (skill `malt-squad-conventions`).
   - **NE PAS assigner à la création.** L'assignation à `stephen.begot` intervient au step 7a (passage `In Progress`), quand le dev démarre.
   - Récupérer le **numéro de ticket** créé — il pilote tout le reste (titre de session, MR, statuts).

7. **IMPLÉMENTATION — MR au plus tôt.** Le ticket bug créé à l'étape 6 est le ticket de travail.

   **7a — MR AU PLUS TÔT (avant tests/build locaux lourds) :**
   - Worktree + branche (base `origin/master`, hors repo) — GIT WORKFLOW (CLAUDE.md).
   - **TDD sur le bug** : écrire d'abord un test qui **reproduit le bug** (rouge), puis appliquer le fix. **Confirmer localement le passage rouge→vert du SEUL test qui cible le bug** (pas la suite complète). Recouvre COUVERTURE DE CODE.
   - **DÉLÉGATION OBLIGATOIRE (skill `malt-orchestration` § DÉLÉGATION DE L'IMPLÉMENTATION).** La cause racine et le plan de fix (arrêtés en Phase 1) restent sur Opus ; l'**écriture du test de repro + du fix** part en sous-agent `sonnet` via un plan précis (fichier `path:line`, forme exacte du fix, test attendu, pattern jumeau), qui exécute rouge→vert et retourne la CONCLUSION (sortie verte citée). Opus ne tape pas le code inline. **Exception** — fix réellement piégeux (invariant/concurrence) reste sur Opus. Consommation 100 % Opus = anti-pattern.
   - **Dès le fix appliqué et ce test ciblé au vert** → Statut JIRA → "In Progress / Dev" (**c'est ICI qu'on s'auto-assigne le ticket à `stephen.begot`**, `PUT /issue/<TICKET>/assignee`, pas avant), puis **Push + MR IMMÉDIATEMENT** (`/gitlab-resume`, reviewer `@stephen.begot`, labels de squad — skill `malt-squad-conventions`, **titre `[<TICKET>] …`** en anglais — le ticket bug existe, on utilise son numéro comme tout `/dev` ; cf. GIT WORKFLOW). Onglet `[MR (<numMR>)] <résumé>`. **La pipeline distante tourne dès maintenant.**

   **7b — VÉRIFICATION LOCALE LOURDE, EN PARALLÈLE DE LA PIPELINE (après la MR) :**
   - Pendant que la pipeline tourne : lancer la **suite de tests complète des modules touchés + le build** localement, et le **SMOKE-RUN LOCAL** des services touchés (skill commons § SMOKE-RUN LOCAL).
   - **`/goal` borné + LOOP JUGE** (skill commons § VÉRIFICATION & BOUCLES, leviers 2-3) : `/goal` sur 0 test en échec + service qui boote + scope = LE bug et rien d'autre, borne ~6 tours ; puis **LOOP JUGE — obligatoire, solo comme orchestré** (skill `malt-surface-exchange` § LOOP JUGE) : lancer un sous-agent **`judge`** frais (`CHECKPOINT=hotfix-verify`, `ROUND=N`, worktree/branche, `REPORT_FILE=<SURFACE_FILE>` — en solo `/Users/stephenbegot/claude-exchange-llm/_solo/<TICKET>.md`, consigne du fix + cause racine, ce que je prétends avoir fait). Le juge contrôle : le fix corrige-t-il vraiment la cause racine ? test qui reproduit le bug ? cas limite ? effet de bord ? **Un juge NEUF par round**, jusqu'à `OK` (4 rounds max → `[ASK]`). Traiter correctness/scope, ne pas sur-corriger. Ne JAMAIS juger dans le contexte qui a écrit le fix.
   - **Validation Sonar** (ici c'est un post-push assumé : la MR existe déjà, on valide en parallèle).
   - **Si une vérif locale échoue** (test, build, smoke-run, judge, Sonar) → fixer, commit + **repush sur la branche de la MR** (jamais master), la pipeline se relance. Onglet `[IMPL]`/`[PIPE (<numMR>)]`.

   **7c — CLÔTURE :**
   - `/end` (avec vérif pipeline — skill `malt-pipeline-followup`, invoqué via skill commons § /end AVEC MR), suivi MR jusqu'au vert, statut JIRA → "Review".
   - Attente `Approved` (hors suivi pipeline lui-même, déjà couvert par `malt-pipeline-followup`) : boucle `until` en background ou `/loop` (skill commons § VÉRIFICATION & BOUCLES levier 4 ; **`Monitor` interdit**). **HEURES CALMES 20h–7h (CLAUDE.md) : aucun suivi/poll/réveil programmé → STOPPER NET, consigner l'état, relance manuelle le matin.**
   - Lecture des commentaires `@stephen.begot` (jamais par supposition — fetch les notes). **Request changes** : tant que pas de `Approved`, ses commentaires = demandes → fixer (`[IMPL]`/`[PIPE (<numMR>)]`) ou répondre, puis **LUI REDEMANDER un `Approved`**. Merge UNIQUEMENT après commentaire `Approved` **postérieur au dernier repush** + pipeline verte (GIT WORKFLOW : rebase `skip_ci=true` puis merge `--squash`).
   - Statut JIRA → "To Validate". **Livrable final** = tableau du skill commons § LIVRABLE FINAL.

## URGENCE — un hotfix reste borné (RÈGLE ABSOLUE)

Un `/hotfix` corrige **LE bug diagnostiqué, rien d'autre**. Pas de refacto, pas de nettoyage opportuniste, pas de correction de bugs annexes. Autre bug / dette découvert → skill commons **§ TRAVAIL DÉCOUVERT** (ticket dédié sous le même parapluie, signalé, jamais enfoui dans le commit du hotfix).

## Rappels transverses (voir CLAUDE.md et skill `malt-workflow-commons`)

- **systematic-debugging AVANT tout fix** : cause racine identifiée + vérifiée contre le réel avant de coder.
- **ORCHESTRATION PAR SOUS-AGENTS** (skill `malt-orchestration`) : déléguer exploration/diagnostic ; CONCLUSION pas dumps ; dimensionner le model.
- **COUVERTURE DE CODE** : un test qui reproduit le bug (rouge→vert) ; toute ligne touchée couverte ; vert obligatoire avant de déclarer terminé.
- **GIT WORKFLOW** (CLAUDE.md) : jamais toucher master ; worktree hors repo (base `origin/master`) + branche + MR ; reviewer `@stephen.begot` ; merge seulement après commentaire `Approved` (fetch les notes) ; rebase `skip_ci=true` + merge `--squash` ; jamais co-author ; jamais lancer les linters (hook husky) ; titre MR anglais `[<TICKET>]` (le ticket bug existe) ; labels de squad (skill `malt-squad-conventions`) ; bloc de clôture obligatoire après push.
- **LANGUE** (CLAUDE.md) : écriture JIRA/GitLab/Notion en **ANGLAIS** ; seul le champ `Prompt` en français.
- **TITRE DE SESSION** (CLAUDE.md) : dès le ticket bug créé, commence par son numéro.
