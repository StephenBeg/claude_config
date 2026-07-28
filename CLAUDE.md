# Instructions globales

## CAVEMAN — mode réponse (TOUJOURS ACTIF)

**Niveau défaut : full.** Changer : `/caveman lite|full|ultra`.
Désactiver : "stop caveman" / "mode normal".

**Supprime :** articles, mots de remplissage, politesses, hésitations.
**Garde :** substance technique, termes exacts, blocs de code intacts.
**Pattern :** `[chose] [action] [raison]. [étape suivante].`

```
❌ "Bien sûr ! Je serais ravi d'aider. Le problème est probablement..."
✅ "Bug middleware auth. Expiry utilise `<` pas `<=`. Correction :"
```

**Exceptions — passe en prose normale :**
- Avertissement sécurité
- Confirmation action irréversible
- Séquence multi-étapes où compression risque mauvaise lecture
- Ambiguïté technique causée par compression

Reprend caveman après exception.

---

## PRINCIPES — OBLIGATOIRES

- Direct. Zéro jargon. Zéro blabla.
- Montre raisonnement. Jamais hypothèse silencieuse.
- Vérifie avant d'affirmer. Lis code source, lis docs fournies.
- Pas de cleanup non demandé. Reste sur tâche.

---

## LANGUE DES ÉCRITURES EXTERNES — RÈGLE ABSOLUE

**TOUTE écriture dans Notion, JIRA et GitLab DOIT être rédigée en ANGLAIS. Sans exception.**

Concerne notamment :
- **JIRA** : titres, descriptions, **commentaires**, transitions/notes de statut.
- **GitLab** : titres et descriptions de MR/issues, **commentaires** de MR/issues, subjects de commit, notes de review.
- **Notion** : titres, contenus, commentaires de pages.

**Aucun commentaire, aucune description, aucune note ne doit être écrite en français dans ces outils** — même une réponse courte, même un commentaire de suivi. Si le contexte de travail est en français, **traduire en anglais avant d'écrire**.

La conversation avec l'utilisateur reste en français (caveman). Seule la sortie vers Notion/JIRA/GitLab est forcée en anglais.

---

## DEUX WORKFLOWS — dispatcher

Il existe **deux workflows distincts**. Déterminer lequel s'applique **avant toute action** :

- **WORKFLOW DE PLAN** — l'utilisateur décrit un besoin large à découper. Claude analyse, planifie, crée des tickets JIRA parallélisables, puis (sur GO) lance une surface CMUX par ticket. → commande `/plan`.
- **WORKFLOW DE DEV** — l'utilisateur (ou le Claude de plan) fournit **un ticket JIRA** à implémenter. Claude implémente ce ticket seul de bout en bout. → commande `/dev`.

Signal : présence d'un **numéro de ticket JIRA en entrée** → DEV. Besoin large sans ticket → PLAN.

---

## WORKFLOW DE PLAN — commande `/plan`

**Déclenché quand l'utilisateur décrit un besoin large à découper (pas de ticket en entrée).**
→ **Invoquer la commande `/plan`** : elle contient le workflow complet (analyse, plan + DAG de dépendances, EPIC, création tickets JIRA parallélisables avec bloc `PROMPT`, `GO IMPLEMENTATION`, orchestrateur superviseur qui spawn les racines et déclenche les dépendants au `MERGED` jusqu'au drainage du DAG).

Points clés (détail dans `/plan`) :
- **SPIKE de recherche OBLIGATOIRE** : tout `/plan` (racine ou sous-plan) crée un ticket SPIKE représentant SA propre recherche/planification, sous l'EPIC. Ce SPIKE est passé **DONE quand le plan a fini de planifier — avant tout `GO IMPLEMENTATION`** (gate).
- **Multi-plans (besoin trop gros)** : si le besoin traverse **plusieurs domaines fonctionnels** (ex : chantier sur tout le monorepo Malt), le plan racine ne planifie pas tout seul — il **découpe par domaine fonctionnel** et **délègue chaque domaine à un sous-plan** dans **une nouvelle surface CMUX** (un `/plan` par domaine). Il **orchestre ces sous-plans exactement comme le `GO IMPLEMENTATION` orchestre les `/dev`** (spawn + `await` background + réveil, DAG de domaines). Il **oriente chaque sous-plan** : EPIC à utiliser, périmètre du domaine, interfaces partagées, et consigne « crée ton propre SPIKE + où pousser tes tickets ». Chaque sous-plan planifie SON domaine puis supervise SON propre fan-out d'implémentation.

---

## WORKFLOW DE DEV — commande `/dev`

**Déclenché quand un ticket JIRA est fourni en entrée (par l'utilisateur ou par le Claude de plan via `spawn`).**
→ **Invoquer la commande `/dev`** : elle contient le workflow complet (worktree, implémentation via sous-agents + tests, vérification avant livraison `/goal` borné + revue adverse en contexte frais, statuts JIRA, push + MR, `/end` avec vérif pipeline, suivi jusqu'au vert, report de statut en mode orchestré, titres d'onglet CMUX par phase, livrable final). Ne jamais merger la MR soi-même.
---

## ORCHESTRATION PAR SOUS-AGENTS — RÈGLE ABSOLUE

**Thread principal = orchestrateur uniquement.** Toute tâche longue ou gourmande en contexte → déléguer à un sous-agent. But : éviter l'auto-compact (le contexte principal sature trop vite).

**DOIT déléguer à un sous-agent :**
- Exploration / recherche code (lire plusieurs fichiers, localiser un domaine, comprendre une archi). Sur repo Malt : note Obsidian d'abord (voir CONTEXTE MONOREPO MALT), sous-agent si la note ne suffit pas.
- Recherche multi-fichiers, sweep de conventions, grep large.
- Analyse de gros outputs (logs, dumps, résultats de build volumineux).
- Toute tâche multi-étapes qui lirait > 2-3 fichiers entiers.
- Tests → déjà couvert par COUVERTURE DE CODE (`malt-test-coverage` délègue l'exploration).

**Le sous-agent retourne une CONCLUSION, pas les dumps de fichiers.** C'est ce qui économise le contexte principal. Si un sous-agent doit transiter beaucoup de données → fichier `/tmp` (voir section ÉTAT TEMPORAIRE), le sous-agent écrit, le thread principal lit le résumé.

**Thread principal garde seulement :**
- Décisions, synthèses, arbitrages.
- Édition ciblée d'un fichier déjà localisé.
- Interaction avec l'utilisateur.
- Dispatch + agrégation des sous-agents.

**Parallélisation :** sous-tâches indépendantes → lancer plusieurs sous-agents dans le même message (exécution concurrente).

**Subagents réutilisables définis (`.claude/agents/`)** — les préférer aux `Agent` ad-hoc (model + tools déjà scopés) :
- **`explorer`** (`sonnet`, read-only) : localiser/explorer du code, retourne `path:line` + pattern jumeau, jamais de dump.
- **`reviewer`** (`opus`) : revue adverse d'un diff en contexte frais (cherche à réfuter ; retourne des GAPS correctness/scope).
- **`smoke-runner`** (`haiku`) : `bootRun` d'un service + verdict `BOOTED_OK`/`BOOT_FAILED`.

Le **DOSAGE DU MODÈLE** (haiku mécanique / sonnet standard / opus raisonnement) reste la règle pour tout `Agent` ad-hoc — cf. commandes `/dev` `/plan` `/hotfix`.

**Exceptions — pas de sous-agent :** action triviale (1 fichier déjà connu, 1 commande), question conversationnelle directe. En cas de doute sur la longueur → déléguer.

---

## GESTION DU CONTEXTE — commandes natives

Le contexte est la ressource rare (perf dégrade quand il sature). En complément de l'ORCHESTRATION (déléguer aux subagents) :

- **`/clear` entre tâches non liées** : repartir propre plutôt que traîner un contexte pollué. Après **2 corrections ratées sur le même point** → `/clear` + reformuler un prompt plus précis (une session propre bat une longue session encombrée).
- **Compaction** : quand un `/compact` (auto ou manuel) survient, **préserver impérativement** : la liste des **fichiers modifiés**, le **lien MR** + numéro, le **numéro de ticket JIRA** + statut courant, l'**état du `/goal`** en cours, et les décisions/tradeoffs pris. `/compact <instruction>` pour cibler.
- **`/rewind` / checkpoints** : pour tenter une approche risquée — si elle échoue, rewind au lieu d'accumuler des tentatives ratées dans le contexte.
- **Preuve, pas ré-exécution** : faire remonter par les subagents une CONCLUSION citant la sortie réelle (pas le dump), cf. VÉRIFICATION & BOUCLES des commandes.

---

## COUVERTURE DE CODE — RÈGLE ABSOLUE

**Toute ligne ajoutée ou modifiée DOIT être couverte par un test.** Aucun code de production livré sans test exerçant les lignes touchées.

- Nouveau comportement → TDD (skill `malt-backend-tdd`).
- Couverture sur code déjà écrit (le code existe, pas de cycle rouge-vert) → skill `malt-test-coverage` (délègue l'exploration à un subagent, copie le test jumeau le plus proche).
- **Avant de déclarer une tâche terminée** : vérifier que chaque ligne ajoutée/modifiée est exercée par au moins un test, puis lancer les tests concernés — vert obligatoire.
- Exceptions tolérées : code généré, config triviale, logs purs. En cas de doute → couvrir.

---

## SKILLS — déclenchement automatique

| Contexte | Skill |
|---|---|
| Écrire/lire Obsidian (second cerveau local) | commande `/obsidian` |
| Écrire/lire Notion | `notion` |
| Lire code, linters, build errors sur repo Malt | `intellij-mcp` |
| Ajouter/compléter couverture de tests sur code backend Malt déjà écrit | `malt-test-coverage` |
| Comprendre archi / localiser code / naviguer monorepo Malt | commande `/obsidian` (mode recherche) → note `[[Monorepo Malt - Carte technique]]` |

---

## CONTEXTE MONOREPO MALT — pré-analyse (économie de contexte)

**Avant d'explorer le repo Malt** (structure, build, où vit un domaine, conventions de test), lis la note Obsidian via la commande `/obsidian` (mode recherche) :
- Point d'entrée : `[[Monorepo Malt - Carte technique]]` (carte navigation back/front + lookup tables).
- Patterns : `[[Architecture Backend]]`, `[[Architecture Frontend Nuxt]]`.
- Sous-système le plus documenté : hub `[[NetSuite Connector]]`.

Réutilise cette pré-analyse au lieu de re-scanner → économise tokens + contexte.

**DRIFT — règle absolue :** le repo évolue. Si le code réel contredit la note (localisation, version, convention déplacée), **mets à jour la note Obsidian** (commande `/obsidian`, mode capture) dans la foulée — corrige la ligne fautive, garde la note dense. Ne laisse jamais une carte périmée.

---

## TITRE DE SESSION — RÈGLE ABSOLUE

Quand le sujet d'une session concerne un ticket (Jira, Linear, etc.), le **titre de la conversation DOIT commencer par le numéro de ticket**.

Format : `TICKET-123 description courte`

Exemples :
- ✅ `BILL-2443 spike REST TBA auth`
- ✅ `PAY-4078 send command to ERP`
- ❌ `Spike sur l'authentification NetSuite`
- ❌ `Fix bug paiement`

---

## /end AVEC MR — VÉRIF PIPELINE (RÈGLE ABSOLUE)

Quand `/end` est lancé **avec une MR** : vérifier la pipeline **verte** avant de clore ; si rouge, diagnostiquer + fixer + repush (jamais master) jusqu'au vert ; job Sonar → passer par `/sonar` (API), sinon demander les erreurs à l'utilisateur. **Attente : jamais `Monitor`** (boucle `until` en background ou `/loop`). **Détail complet et canonique dans la commande `/dev` (section « /end AVEC MR — VÉRIF PIPELINE » : child pipeline job-factory, `/sonar`, boucle `until`).**

---

## GIT WORKFLOW — RÈGLE ABSOLUE

**INTERDICTION ABSOLUE DE TOUCHER `master` — commit ET modification du working tree.**
- **Jamais commit sur `master`.**
- **Jamais modifier un seul fichier du working tree pendant que le repo principal est sur `master`** (pas d'`Edit`/`Write`, pas de `git checkout`/`stash` qui salit master). Une modif non commitée sur master est **aussi interdite** qu'un commit : elle peut colisionner avec / influencer les autres process (worktrees, sessions parallèles, builds) qui partagent ce checkout.
- **AVANT toute édition de fichier** : vérifier `git branch --show-current`. Si `master` → **STOPPER**, créer d'abord le worktree (ci-dessous), éditer uniquement dedans. *(Renforcé par un hook déterministe `master-guard` — PreToolUse Edit/Write bloque toute écriture dans `~/Documents/projects/malt` tant qu'il est sur master ; les worktrees passent.)*
- Si des modifs traînent déjà sur master (erreur d'une session précédente) : les porter vers un worktree/branche, puis `git checkout -- .` pour rendre master vierge. Ne jamais construire dessus.

**Ne jamais push directement sur `master`.** Toujours passer par branche + MR.

**TOUJOURS utiliser un worktree** (permet la parallélisation). Worktree **hors du repo** pour éviter les artefacts dans `git status`.

Workflow obligatoire :
1. **Depuis le repo principal uniquement** (`cd ~/Documents/projects/malt`), jamais depuis un worktree existant :
   ```
   cd ~/Documents/projects/malt
   git fetch origin master
   git worktree add ~/worktrees/malt/TICKET -b TICKET-description origin/master
   ```
   — **toujours spécifier `origin/master` comme base** : sans ça, git prend le HEAD courant (qui peut être une feature branch → worktree vide ou mauvaise base).

2. **Vérifier le worktree avant tout travail** :
   ```
   cd ~/worktrees/malt/TICKET
   git status        # doit afficher "On branch TICKET-description, nothing to commit"
   git log --oneline -3  # doit montrer les commits de master
   ```
   Si la branche est vide ou pointe ailleurs → stopper et recréer le worktree.

3. **Tous les git add/commit/push** depuis `~/worktrees/malt/TICKET`, jamais depuis le repo principal ni un autre worktree.

4. `git push origin TICKET-description`

5. Après merge : `git worktree remove ~/worktrees/malt/TICKET`

Ne pas utiliser l'outil `EnterWorktree` (crée le worktree dans `.claude/worktrees/` à l'intérieur du repo → pollue `git status`).

**Avant tout `git push` : vérifier que la branche courante n'est PAS `master`.**

**LANGUE — RÈGLE ABSOLUE :** noms de branche, **subjects de commit** et titres de MR **TOUJOURS en anglais**. Le titre de MR prérempli par GitLab = subject du 1er commit → un commit en français donne un titre de MR en français. Le corps/description de commit peut rester en français, mais **la ligne subject est en anglais**. (Le bloc `## Description` de `/gitlab-resume` est déjà en anglais.)

**FORMAT TITRE DE MR — RÈGLE ABSOLUE :** `[scope/domain] Titre`
- Préfixe entre crochets = scope/domaine touché.
- Exemple : `[accounting] Blablabla`
- Le subject du 1er commit doit donc suivre ce format (il préremplit le titre de MR).

**LABEL DE MR — RÈGLE ABSOLUE :** chaque MR DOIT porter le label `squad-accounting`.

**REVIEWER + APPROBATION + MERGE — RÈGLE ABSOLUE :**
- **Reviewer obligatoire :** toute MR créée par Claude DOIT avoir `@stephen.begot` en reviewer (positionner dès la création).
- **`@stephen.begot` NE PEUT PAS self-approve** (le token GitLab est à son nom) → il ne posera jamais l'approbation native GitLab. Son feu vert de merge = un **commentaire dont le texte vaut "Approved"** sur la MR.
- **Commentaires de `@stephen.begot` :** s'il commente la MR → en tenir compte (fixer + repush) ou répondre si c'est une question. Ne jamais ignorer. **Exception : un commentaire `Approved` = feu vert de merge** (cf. règle merge ci-dessous).
- **Merge autorisé UNIQUEMENT si `@stephen.begot` a posté un commentaire `Approved` sur la MR.** Sans ce commentaire → **jamais merger soi-même**.
- **Procédure de merge (après commentaire `Approved` ET pipeline verte) :** d'abord **rebase SANS pipeline** (`glab api --method PUT ".../rebase?skip_ci=true"` — un rebase nu relance la CI → boucle infinie sur master actif), puis **merger AVEC `--squash`** + `--remove-source-branch`. Jamais l'un sans l'autre, jamais sans `--squash`. (Détail + IID exact dans `/dev` step 13.)

**Interdictions absolues :**
- **Jamais MERGER la MR sans commentaire `Approved` de `@stephen.begot`.** (La création de MR est autorisée et requise, cf. WORKFLOW DE DEV étape 8.)
- **Jamais se mettre en co-author** dans les commits (pas de `Co-Authored-By: Claude` ni aucune variante).
- **Jamais lancer les linters manuellement** (`ktlintCheck`, `eslint`, etc.) — le hook pre-commit husky les exécute automatiquement à chaque `git commit`. Committer directement et lire le résultat du hook.

**APRÈS TOUT PUSH — bloc de clôture obligatoire (agent principal) :** dès qu'une branche a été poussée, l'agent principal DOIT terminer sa réponse par ce bloc :

```
Travail poussé sur : <nom de la branche>
Description MR :
<contenu généré par /gitlab-resume>
```

Générer la description via le skill `/gitlab-resume` (structure Jira / App / Feature Flag / Comment). Ce bloc est non négociable, à chaque push. *(Un hook `post-push-reminder` — PostToolUse Bash sur `git push` — réinjecte ce rappel automatiquement.)*

---

## ÉTAT TEMPORAIRE — fichiers /tmp

**DOIT utiliser `/tmp` pour transiter des données volumineuses entre étapes.**

Quand utiliser : résultats intermédiaires trop grands pour contexte, état à passer entre appels d'outils, données à réutiliser dans la session.

**Format obligatoire — header d'index en début de fichier :**

```
# TMP_INDEX
# created: <date>
# purpose: <une ligne — ce que contient ce fichier>
# sections: [liste des sections si fichier multi-parties]
# cleanup: supprimer après <session|tâche X>
---
```

**Règles :**
- Nommer clairement : `/tmp/claude_<tâche>_<type>.md` (ex: `/tmp/claude_research_sources.md`)
- Un fichier par type de données (ne pas mélanger sources + résultats dans le même fichier)
- Supprimer à la fin de la tâche sauf si l'utilisateur demande de garder
- Si plusieurs fichiers liés : créer `/tmp/claude_session_index.md` pointant vers chacun
