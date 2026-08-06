---
description: WORKFLOW DE PLAN — analyser un besoin large, produire un plan + DAG de dépendances, créer les tickets JIRA parallélisables, puis (sur GO) superviser le fan-out CMUX (un /dev par ticket) jusqu'au drainage du DAG. Si le besoin est trop gros → découper en sous-plans par domaine fonctionnel (une surface /plan par domaine) et les orchestrer. Déclenché quand l'utilisateur décrit un besoin large sans ticket en entrée.
---

## Input

$ARGUMENTS

Le besoin large à découper (pas de ticket JIRA en entrée).

**Invoquer le skill `malt-workflow-commons` EN PREMIER** — source de vérité unique des règles partagées : questions à choix, escalade archi & tradeoffs, accès JIRA, préfixes CMUX, vérification des sources contre le réel, vérification & boucles de contrôle, travail découvert. Ce workflow y renvoie par nom de section et ne les recopie pas. (`/plan` n'a ni smoke-run ni MR ni livrable de dev.)

**Décisions d'archi = escalade (commons § DÉCISIONS D'ARCHI & TRADEOFFS).** Le découpage en tickets, la forme des contrats d'API, le choix des patterns et les frontières de domaine sont des décisions d'architecture : le plan ne fige aucun choix structurant seul, il escalade à l'utilisateur (`AskUserQuestion`, recommandation en 1er) **avant** de créer les tickets. Un tradeoff différenciant se pose à l'utilisateur, jamais tranché en silence puis révélé.

## DÉCISION D'ÉCHELLE — avant tout

Trancher : **plan simple** ou **multi-plans** ?

- **Plan simple** (défaut) : le besoin tient dans **un seul domaine fonctionnel** → suivre le WORKFLOW ci-dessous.
- **Multi-plans** : le besoin traverse **plusieurs domaines** (ex : chantier monorepo entier, ou accounting + billing + payments + front). Ne pas tout planifier soi-même → **un sous-plan par domaine**, chacun dans sa surface CMUX, orchestrés comme le GO orchestre les `/dev`. → voir **MODE MULTI-PLANS**.

Signal « trop gros » : > ~8-10 tâches parallélisables, ou le découpage naturel se fait d'abord **par domaine** avant de se faire par tâche. Doute → proposer le multi-plans à l'utilisateur.

## WORKFLOW DE PLAN

**HEADER CMUX** (commons § PRÉFIXES) : `[PLAN]` en analyse, `[ASK]` en attente du `GO`, **`[MAIN]` pendant tout le GO IMPLEMENTATION** (supervision DAG/sous-plans), `[WAIT]` pour un `await` en vol.

Étapes dans l'ordre :

1. **Titre onglet** → `[PLAN] <résumé 3-4 mots>`.
2. **Sync master — AVANT toute analyse** (l'étude part de la dernière version de `master`). Depuis le repo principal (`cd ~/Documents/projects/malt`) :
   ```
   git fetch origin master && git checkout master && git pull --ff-only origin master
   ```
   Vérifier `git branch --show-current == master` et `git status` propre avant le `pull`. Working tree sale → STOPPER, porter vers un worktree puis `git checkout -- .` (GIT WORKFLOW). Pull non fast-forward → STOPPER (master local divergent = anomalie). Ne rien éditer/committer sur master.
3. **EPIC** — demander l'EPIC de rattachement le plus tôt possible (le SPIKE et la User Story en ont besoin). En multi-plans, c'est cette EPIC que reçoit chaque sous-plan.
4. **SPIKE de planification** (skill `/jira`, sous l'EPIC) — UN ticket représentant **la recherche/étude DE CE PLAN** (exploration, cadrage, découpage, DAG). Type `Spike` sinon `Task` titre `[SPIKE]`. Titre + description **en anglais**. Le passer **In Progress** au début. (Multi-plans : ce SPIKE couvre la recherche de décomposition ; chaque sous-plan crée SON propre SPIKE.)
5. **Analyse** — étudier prompt, code, sources. Déléguer l'exploration à des sous-agents (skill `malt-orchestration` : délégation + dosage model). Sur repo Malt : note `[[Monorepo Malt - Carte technique]]` d'abord (`/obsidian`), sous-agent si insuffisant. **Vérifier les sources contre le réel** (commons § VÉRIFICATION DES SOURCES) : chaque fait structurant du plan traçable à une source vérifiée cette session ; hypothèse non vérifiée marquée comme telle.
6. **Plan + DAG** — découper en **tâches parallélisables** (1 tâche = 1 ticket JIRA), identifier les dépendances (B démarre après merge de A) → DAG : **racines** (sans dépendance) vs **dépendantes**. **Appliquer `## DÉCOUPAGE DES TÂCHES` (R1→R5) AVANT de figer le DAG** — le découpage naïf (1 ligne = 1 ticket) est interdit (conflits, contrats affaiblis, MR illisibles).
7. **User Story unique** (skill `/jira`, sous l'EPIC) — UNE SEULE, décrit le **besoin métier global** (le QUOI). Toutes les tâches vivent à l'intérieur (ne pas polluer le board EPIC). Titre + description **en anglais**, point de vue métier.
   - **Description du parapluie = complète et remise à jour après étude** : c'est LA source de vérité du chantier. Après analyse (5-6), réécrire : résumé, contexte, objectif métier, périmètre, découpage en tâches, definition of done. Lisible par un non-technique.
   - Laisser en `To Do`/`Open` à la création (tant que pas de GO). Cycle de vie → section dédiée.
8. **Tâches JIRA dans la User Story** (skill `/jira`) — une par tâche parallélisable, **enfant de la User Story** (champ parent : Epic → Story → Task). Chaque tâche :
   - Titre + description **en anglais**, point de vue métier (le QUOI), lisible par un non-technique. **La description N'EST PAS le prompt** : aucun bloc `PROMPT`, aucun détail d'implémentation technique dedans.
   - **Champ "Prompt" (`customfield_11956`) = la consigne d'implémentation, en français** — écrite via `/jira` (ADF). C'est le travail **mâché** pour le `/dev` : périmètre exact, fichiers/symboles `path:line`, pattern jumeau à copier, contrats partagés, cas de test attendus, pièges. Inclure `DEPENDS_ON: TICKET-A, TICKET-B` (ou `DEPENDS_ON: -` si racine).
   - **MODE DE LANCEMENT selon le TYPE** (dans le champ Prompt) : ticket d'implémentation → `lance /dev` ; ticket SPIKE/recherche du DAG → **`lance /plan`** (sous-plan récursif, cf. section dédiée), jamais `/dev`.
   - **Liens de dépendance JIRA** : lien **"is blocked by"** (dépendant → parent) pour chaque arête du DAG.
   - **NE JAMAIS assigner à la création (RÈGLE ABSOLUE).** L'assignation à `stephen.begot` est faite par le `/dev` lui-même au passage `In Progress`.
9. **SPIKE → DONE (GATE avant GO)** — une fois plan + tâches + DAG + liens prêts : (a) **revue adverse en contexte frais** (commons § VÉRIFICATION & BOUCLES levier 3 — subagent `reviewer` `opus` cherchant domaine/tâche/dépendance/contrat oublié **et contrôlant R1→R5** : slices back/front à recoller, confettis à fusionner, zones chaudes multi-tickets, dépendances croisées/manquantes), intégrer les GAPS ; (b) finaliser la description du parapluie (étape 7) ; (c) passer le SPIKE de l'étape 4 en `DONE`. **Le SPIKE DOIT être DONE avant tout GO IMPLEMENTATION.**
10. **Attendre le `GO IMPLEMENTATION`.** Ne rien lancer avant. → `[ASK]`.
11. **GO IMPLEMENTATION — orchestrateur superviseur.** → `[MAIN]` dès le GO et pendant toute la supervision.
    - **User Story → `In Progress`** (première action du GO).
    - **Dossier de statuts** : `STATUS_DIR=/tmp/claude_plan_<EPIC>_status` (header `TMP_INDEX`).
    - **Spawn les racines uniquement** (`DEPENDS_ON` vide), chacune dans une nouvelle surface **du même workspace CMUX** que le process courant, cwd `~/Documents/projects/malt` (l'agent crée son propre worktree). Workflow selon le TYPE (`/dev` ou `/plan`) :
      ```
      ~/.claude/scripts/cmux-tab.sh spawn "<contenu du champ Prompt + numéro JIRA + consigne: lance /dev OU /plan selon le type>" "<TICKET-XXX résumé>" ~/Documents/projects/malt "$STATUS_DIR" TICKET-XXX
      ```
      `spawn` injecte le préambule "report ton statut" et écrit `SPAWNED`. Cible `$CMUX_SURFACE_ID` (jamais `$CMUX_WORKSPACE_ID`).
    - **Écouter chaque ticket en vol** : `cmux-tab.sh await "$STATUS_DIR" TICKET-XXX` **EN BACKGROUND** (`run_in_background: true`) — jamais foreground (cap 10 min). Le harness re-réveille l'orchestrateur à la sortie.
    - **SPAWN IDEMPOTENT — un timeout/erreur du spawn ≠ échec (RÈGLE ABSOLUE).** Bash cape à 120s ; un spawn qui « timeout » a pu créer la surface + lancer l'agent. Donc : spawns lents en `run_in_background: true` ; **avant de re-spawn, vérifier que `<ticket>.status` est VIDE** (`[ -s <dir>/<ticket>.status ]`) — un re-spawn crée un **worker doublon sur le même worktree/branche** (incident BILL-2909). Flakiness persistante → `new-surface --workspace <shortref>` en dur (`[[reference_cmux_tab_workspace_resolution]]`).
    - **RESCAN DES ENFANTS DE L'UMBRELLA — À CHAQUE RÉVEIL (RÈGLE ABSOLUE).** Un ticket lancé peut créer de nouveaux tickets sous le parapluie (invisibles des status files). À chaque réveil : re-lister les enfants de la User Story (`/jira`, `parent = <umbrella>`), comparer au DAG connu, intégrer tout orphelin (liens, mode `/dev` vs `/plan`, spawn+await quand débloqué). **Le JIRA est la source de vérité du périmètre, pas le `STATUS_DIR`.**
    - **HEURES CALMES 20h–7h (RÈGLE ABSOLUE, CLAUDE.md).** À chaque réveil, `date +%H%M` AVANT tout spawn/await. Si ∈ [2000,0659] → STOPPER NET (pas de spawn, pas d'await, pas de réveil programmé), consigner l'état du DAG + point de reprise, `[WAIT]` « paused — quiet hours ». Relance manuelle le matin.
    - **Déclencher les dépendants** : à chaque réveil, recalculer les tickets dont **tous** les `DEPENDS_ON` sont terminaux satisfaisants (**`MERGED`** pour `/dev`, **`DONE`** pour un SPIKE lancé en `/plan`), les spawn, lancer leur `await`. Répéter jusqu'au **drainage complet du DAG**.
    - **`BLOCKED`** : un `await` sort en code 3 → surfacer (`[ASK]`), ne pas spawn les dépendants tant que non résolu.
12. **Fin** — DAG drainé (toutes tâches `MERGED`) → `[END]` : **User Story → `To Validate`** (jamais `Done` soi-même — validation humaine). S'arrêter en laissant le terminal CMUX ouvert. (Blocage → laisser en `In Progress` et surfacer.)

## DÉCOUPAGE DES TÂCHES — JUSTE MILIEU (RÈGLE ABSOLUE)

Des tickets **ni trop petits ni trop gros**, découpés par **unité de valeur logique**, peu de collisions, ordre de dépendances propre. Le sur-découpage coûte plus qu'il ne rapporte. Appliquer R1→R5 dans l'ordre.

**R1 — Slice VERTICAL par défaut (une micro-feature = UN ticket back+front).** Back ET front couplés par un contrat neuf → un seul ticket. Sinon on livre un contrat avec des champs facultatifs (le front n'existe pas encore) puis on les repasse en requis → dette + deux MR. *Exception (back/front séparés)* : back volumineux en soi (nouvelle table, migration, logique non triviale) OU contrat déjà stable et partagé → back racine, front dépendant, contrat requis dès le back. Bon slice = comportement observable de bout en bout, testable seul, MR relisable en une passe.

**R2 — REGROUPER les petites modifs de même nature et même zone.** Plusieurs petites modifs (front OU back) sur la même zone/module/flux → un seul ticket. Repère indicatif : une modif qui seule donnerait une MR de ~30 lignes sans logique propre est trop petite → la fusionner vers le ticket cohérent le plus proche. **Ce seuil sert UNIQUEMENT à fusionner vers le haut, jamais à scinder** un ticket cohérent qui dépasse (60, 120 lignes cohérentes = un seul ticket). Critère qui prime : cohérence fonctionnelle, pas le compte de lignes. Ne pas regrouper des modifs sans lien fonctionnel juste pour la taille.

**R3 — SINGLE-OWNER par fichier / zone chaude (anti-conflit).** Deux tickets parallèles ne doivent pas éditer lourdement le même fichier (1re cause de conflits en boucle). Repérer les zones chaudes (routeur, config Spring, barrel front, fichier de contrat, mapper central, `application.yml`, registration). Chaque zone chaude → un seul ticket propriétaire ; les autres deviennent **dépendants** (sérialisés). N tickets ajoutant tous une entrée au même registre → un ticket "socle" d'extensibilité + N dépendants légers, ou fusionner si trivial.

**R4 — ORDONNER pour éviter le rework (contrats & socles d'abord).** Le DAG reflète le flux réel de prod. **Socles d'abord** (racines) : contrat d'API figé, schéma/migration, port/interface partagé, DTO commun — tout ce que plusieurs tickets consomment. **Consommateurs ensuite** (dépendants) : partent d'une base déjà mergée → zéro champ facultatif transitoire, zéro re-travail. Éviter les dépendances croisées (A↔B = mauvais découpage → fusionner). Un ticket ne dépend que de ce qui change une interface qu'il consomme.

**R5 — TEST DE VÉRIFICATION (avant de figer le DAG).** Pour chaque ticket : (1) **Autonomie** — livre une valeur observable/testable seul ? sinon fusionner. (2) **Contrat** — force un champ facultatif transitoire (slice back/front) ? oui → fusionner vertical (R1). (3) **Collision** — édite lourdement un fichier qu'un ticket parallèle édite aussi ? oui → sérialiser ou fusionner (R3). (4) **Taille MR** — relisable en une passe (~100-400 lignes utiles) ? trop petit → fusionner ; trop gros/multi-sujets → scinder par sous-comportement. (5) **Ordre** — ses dépendances reflètent un vrai besoin d'interface amont ? sinon paralléliser.

La revue adverse du plan (étape 9) contrôle explicitement R1→R5.

## CYCLE DE VIE DU TICKET PARAPLUIE (User Story)

Le parapluie reflète l'état réel du chantier (skill `/jira`) : **`To Do`/`Open`** à la création (tant que pas de GO) → **`In Progress`** dès le GO (étape 11) → **`To Validate`** quand toutes les tâches enfants sont `MERGED` (étape 12) → **`Done` jamais par Claude** (transition humaine).

Multi-plans : chaque sous-plan gère le cycle de SA User Story de domaine ; le plan racine gère la User Story racine si elle existe (sinon l'EPIC fait office de parapluie, non transitionné par Claude).

## MODE MULTI-PLANS — découper en sous-plans par domaine

Besoin trop gros (cf. DÉCISION D'ÉCHELLE) : le plan racine ne planifie PAS les tâches, il découpe par **domaine fonctionnel** et délègue chaque domaine à un sous-plan dans sa propre surface CMUX, puis les orchestre **exactement comme le GO orchestre les `/dev`** (spawn + await background + réveil).

Étapes du plan **racine** :

1. **Titre onglet** + **Sync master** (comme ci-dessus).
2. **EPIC** parapluie du chantier.
3. **SPIKE de décomposition** (sous l'EPIC) — recherche du plan racine : identifier les domaines impactés et leurs interfaces. **In Progress**.
4. **Analyse de décomposition** (sous-agents) — identifier les domaines (accounting, billing, payments, front...) et les dépendances inter-domaines (DAG de domaines).
5. **Dossier de statuts** : `STATUS_DIR=/tmp/claude_plan_<EPIC>_status`.
6. **Spawn un `/plan` par domaine racine**, cwd `~/Documents/projects/malt`, cible `$CMUX_SURFACE_ID` :
   ```
   ~/.claude/scripts/cmux-tab.sh spawn "<prompt de sous-plan : périmètre + 'lance /plan' + ORIENTATION>" "<DOMAINE résumé>" ~/Documents/projects/malt "$STATUS_DIR" DOMAIN-<domaine>
   ```
   **ORIENTATION dans chaque prompt** : l'EPIC à utiliser (le sous-plan crée SA User Story de domaine dessous) ; le périmètre exact du domaine (à lui / aux autres) ; les interfaces/contrats partagés (éviter collisions) ; consigne « crée ton PROPRE SPIKE, planifie ton domaine, mets ton spike DONE, puis attends le GO » ; le `STATUS_DIR` + son id `DOMAIN-<domaine>`.
7. **Orchestrer les sous-plans** — `await "$STATUS_DIR" DOMAIN-<domaine>` en background pour chaque domaine en vol. À chaque réveil (un sous-plan reporte `PLANNED`), déclencher les sous-plans dépendants. Répéter jusqu'à ce que tous soient planifiés. États reportés : `IN_PROGRESS` (analyse) → `PLANNED` (tickets créés, spike domaine DONE, attente GO) → `DONE` (DAG du domaine drainé) | `BLOCKED`.
8. **SPIKE racine → DONE** quand tous les domaines sont dispatchés et `PLANNED`.
9. **GO IMPLEMENTATION multi-plans — deux niveaux** : chaque sous-plan supervise le GO de SON domaine (spawn ses `/dev`, draine son DAG, reporte `DONE`) ; le plan racine relaie le `GO` à chaque sous-plan et déclenche les domaines dépendants au fil des `DONE`, jusqu'au drainage du DAG de domaines.
10. **Fin** — plan racine s'arrête quand tous les sous-plans sont `DONE` (ou blocage explicité), terminal laissé ouvert.

## SPIKE = SOUS-PLAN RÉCURSIF

Un **ticket SPIKE présent dans le DAG** (recherche/investigation/cadrage — à distinguer du SPIKE de planification de l'étape 4) n'est jamais lancé en `/dev` mais en **`/plan`** : une investigation débouche presque toujours sur du travail à créer et orchestrer.

- **Un SPIKE lancé en `/plan` est un plan complet** : sa propre analyse, peut créer ses tickets (sous la même EPIC / un sous-parapluie qu'il crée), construire son sous-DAG, superviser son fan-out (spawn `/dev` et/ou `/plan` enfants, await, réveils).
- **Récursivité sur N niveaux** : un plan lance un SPIKE-plan qui lance un SPIKE-plan… Chaque niveau orchestre son sous-arbre.
- **Remontée de statut** : un SPIKE-plan reporte dans le `STATUS_DIR` de SON parent : `IN_PROGRESS` → `PLANNED` (sous-tickets créés + son SPIKE de planif DONE) → `DONE` (son sous-DAG entièrement drainé) | `BLOCKED`. Le parent traite `DONE` (pas `MERGED`) comme signal de déblocage des dépendants d'un SPIKE.
- **Conscience globale de l'orchestrateur maître** : le `/plan` racine reste responsable de tout l'arbre — RESCAN des enfants de l'umbrella à chaque réveil, propagation des `BLOCKED` jusqu'à l'utilisateur, `To Validate` seulement quand tout l'arbre est drainé. Chaque orchestrateur intermédiaire fait de même pour son sous-arbre.
- **Prompt de spawn d'un SPIKE** : EPIC/parapluie où pousser ses tickets, périmètre de l'investigation, `STATUS_DIR` + son id, consigne « lance /plan ; si tu découvres du travail, crée les tickets sous l'umbrella et orchestre-les ; reporte `PLANNED` puis `DONE`/`BLOCKED` ».

## Rappels spécifiques `/plan`

- **Labels de squad** : TOUT ticket créé par un `/plan` (EPIC, User Story, SPIKE, tâches, sous-plans) porte le label JIRA de squad dès sa création (skill `malt-squad-conventions`).
- **Langue** : JIRA en anglais ; seuls le champ `Prompt` et les prompts de spawn en français.
- Le reste (orchestration sous-agents & dosage model, git workflow, escalade archi, vérification & boucles) vit dans CLAUDE.md et `malt-workflow-commons` — ne pas le recopier ici.
