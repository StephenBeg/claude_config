---
description: WORKFLOW DE PLAN — analyser un besoin large, produire un plan + DAG de dépendances, créer les tickets JIRA parallélisables, puis (sur GO) superviser le fan-out CMUX (un /dev par ticket) jusqu'au drainage du DAG. Si le besoin est trop gros → découper en sous-plans par domaine fonctionnel (une surface /plan par domaine) et les orchestrer. Déclenché quand l'utilisateur décrit un besoin large sans ticket en entrée.
---

## Input

$ARGUMENTS

Le besoin large à découper (pas de ticket JIRA en entrée).

**RÈGLES COMMUNES — invoquer le skill `malt-workflow-commons` EN PREMIER.** Il porte les règles partagées par `/dev` `/plan` `/hotfix` (source de vérité unique) : **§ QUESTIONS À CHOIX DE RÉPONSES**, **§ ACCÈS JIRA**, **§ PRÉFIXES DE HEADER CMUX**, **§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL**, **§ VÉRIFICATION & BOUCLES DE CONTRÔLE**, **§ TRAVAIL DÉCOUVERT EN COURS DE ROUTE**. Ce workflow y renvoie par le nom de section. (Le `/plan` n'a ni smoke-run ni MR ni livrable de dev.)

## DÉCISION D'ÉCHELLE — AVANT TOUT

Avant de planifier, trancher : **plan simple** ou **multi-plans** ?

- **Plan simple** (défaut) : le besoin tient dans **un seul domaine fonctionnel** → suivre le WORKFLOW ci-dessous tel quel.
- **Multi-plans** : le besoin est **trop gros pour un seul plan** — il traverse **plusieurs domaines fonctionnels** (ex : chantier sur tout le monorepo Malt, ou touchant accounting + billing + payments + front). Dans ce cas, **NE PAS tout planifier soi-même** : faire **un sous-plan par domaine fonctionnel**, chacun dans sa propre surface CMUX, et les **orchestrer** comme le GO IMPLEMENTATION orchestre les `/dev`. → voir **MODE MULTI-PLANS**.

Signal « trop gros » : > ~8-10 tâches parallélisables, ou le découpage naturel se fait d'abord **par domaine** avant de se faire par tâche. En cas de doute, proposer le mode multi-plans à l'utilisateur.

## WORKFLOW DE PLAN — RÈGLE ABSOLUE

**HEADER CMUX** : suivre le skill `malt-workflow-commons` **§ PRÉFIXES DE HEADER CMUX**. Spécificité `/plan` : il reste en **`[MAIN]`** pendant tout le GO IMPLEMENTATION (il orchestre le DAG / les sous-plans) ; `[ASK]` pour l'attente du `GO`, `[WAIT]` pour expliciter un `await` en vol.

### Étapes

TOUTES les étapes sont OBLIGATOIRES, dans l'ordre :

1. **Titre onglet** → `[PLAN] <résumé 3-4 mots>` (phase d'analyse/planification).
2. **Sync master — OBLIGATOIRE AVANT toute analyse.** L'étude DOIT partir de la dernière version de `master`. Depuis le repo principal (`cd ~/Documents/projects/malt`) :
   ```
   git fetch origin master
   git checkout master
   git pull --ff-only origin master
   ```
   - **Vérifier `git branch --show-current` == `master` et `git status` propre** avant le `pull`. Si le working tree est sale (cf. GIT WORKFLOW) → **STOPPER**, porter les modifs vers un worktree puis `git checkout -- .`, reprendre une fois master vierge.
   - `--ff-only` : si le pull n'est pas fast-forward → **STOPPER** et surfacer (master local divergent = anomalie, jamais de merge/rebase silencieux).
   - **Ne rien éditer/committer sur master** : cette étape met juste master à jour pour que l'analyse et la base des worktrees (`origin/master`) soient à jour.
3. **EPIC** — demander l'**EPIC** sous laquelle rattacher le travail (le plus tôt possible : le SPIKE et la User Story en ont besoin). En **mode multi-plans**, c'est cette EPIC que chaque sous-plan recevra pour savoir **où pousser ses tickets**.
4. **Ticket SPIKE de recherche — OBLIGATOIRE (skill `/jira`).** Créer **UN ticket SPIKE** sous l'EPIC représentant **LA recherche/étude DE CE PLAN** (l'effort de planification : exploration, cadrage, découpage, DAG).
   - Type `Spike` si disponible, sinon `Task` avec titre préfixé `[SPIKE]`.
   - **Titre + Description en ANGLAIS**, décrivant le périmètre étudié et le livrable (plan + tickets + DAG).
   - Le passer en **In Progress** au début de l'analyse.
   - **En mode multi-plans** : ce SPIKE couvre la recherche de **décomposition** (identifier les domaines) ; **chaque sous-plan créera SON PROPRE SPIKE** pour son domaine.
5. **Analyse** — étudier le prompt, le code, les sources fournies. **Déléguer l'exploration à des sous-agents** (ORCHESTRATION, CLAUDE.md — **dimensionner le model** cf. CLAUDE.md § DOSAGE DU MODÈLE : exploration/localisation en `sonnet`, `haiku` pour un simple grep/lookup, `opus` seulement pour raisonner un cadrage architectural difficile). Sur repo Malt : note Obsidian `[[Monorepo Malt - Carte technique]]` d'abord (`/obsidian` recherche), sous-agent si insuffisant.
   - **VÉRIFIER LES SOURCES CONTRE LE RÉEL** : suivre le skill commons **§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL** — la mémoire (Obsidian, souvenirs) est un point de départ jamais une vérité ; confirmer code (`path:line` sur `master` frais), runtime (Datadog/Sentry), JIRA/FF/config (source vivante) ; corriger la note Obsidian en cas de drift. Chaque fait structurant du plan = traçable à une source vérifiée cette session ; hypothèse non vérifiée marquée explicitement.
6. **Plan complet + DAG de dépendances** — plan découpé en **tâches parallélisables** (1 tâche parallélisable = 1 tâche JIRA). **Identifier explicitement les dépendances** (B ne démarre qu'après merge de A) → **DAG** : tâches **racines** (sans dépendance) vs **dépendantes** (déclenchées après merge de leur(s) parent(s)).
7. **User Story unique** (skill `/jira`) — créer **UNE SEULE User Story** sous l'EPIC. Elle **décrit le besoin métier global** (le QUOI, pas le COMMENT). But : ne pas polluer le board de l'EPIC — toutes les tâches vivent **à l'intérieur** de cette story.
   - **Titre + Description OBLIGATOIREMENT en ANGLAIS**, point de vue **MÉTIER**.
   - **DESCRIPTION DU PARAPLUIE = complète, belle, remise à jour après étude — RÈGLE ABSOLUE.** Le ticket parapluie porte **la description de référence du besoin**. Après l'analyse (étape 5-6), **réécrire/mettre à jour cette description** : mise en forme propre et professionnelle — résumé du besoin, contexte, objectif métier, périmètre, découpage en tâches (liste des sous-tickets et leur rôle), definition of done globale. Lisible de bout en bout par une personne non technique. C'est LA source de vérité du chantier.
   - **La User Story = le ticket parapluie dont le statut suit l'avancée** (cf. CYCLE DE VIE DU TICKET PARAPLUIE). La laisser en `To Do` / `Open` à la création (tant que le GO n'a pas été donné).
8. **Création des tâches JIRA DANS la User Story** (skill `/jira`) — une tâche par tâche parallélisable, chacune **enfant de la User Story** via le champ **parent** (Epic → Story → Task). Chaque tâche :
   - **Titre + Description OBLIGATOIREMENT en ANGLAIS**, point de vue **MÉTIER** (le QUOI). Pas de préfixe : la User Story parente assure le regroupement.
   - **DESCRIPTION = lisible par un non-technique produit — RÈGLE ABSOLUE.** La description N'EST PAS le prompt. Mise en forme proprement (titre/résumé, sections contexte/objectif/critères d'acceptation, bullets, gras). **AUCUN bloc `PROMPT`, aucun détail d'implémentation technique dans la description.**
   - **Champ "Prompt" (`customfield_11956`) = la consigne d'implémentation, EN FRANÇAIS — RÈGLE ABSOLUE.** Le prompt exact qui lancera la tâche va dans CE CHAMP, jamais dans la description. Y inclure une ligne `DEPENDS_ON: TICKET-A, TICKET-B` (ou `DEPENDS_ON: -` si racine).
     - **Le prompt doit être LE PLUS COMPLET POSSIBLE** : travail **mâché** pour le `/dev` (focus + économie de tokens, pas de re-exploration). Périmètre exact, fichiers/symboles avec `path:line`, pattern jumeau à copier, contrats/interfaces partagés, cas de test attendus, pièges connus.
     - **Écriture du champ** (doc ADF) via API REST :
       ```
       curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -X PUT -H "Content-Type: application/json" \
         "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET>" \
         -d '{"fields":{"customfield_11956":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"<PROMPT complet>"}]}]}}}'
       ```
   - **Label `Accounting/Bookkeeping` OBLIGATOIRE** sur CHAQUE tâche (`"labels":["Accounting/Bookkeeping"]`). Idem User Story parapluie (étape 7) et EPIC.
   - **NE JAMAIS assigner à la création — RÈGLE ABSOLUE.** Les tickets restent **non assignés**. L'assignation à `stephen.begot` est faite **par le `/dev` lui-même** au passage `In Progress` (step 6 de `/dev`).
   - **Liens de dépendance JIRA** : pour chaque dépendance du DAG, lien **"is blocked by"** (dépendant → parent).
   - **MODE DE LANCEMENT selon le TYPE — RÈGLE ABSOLUE** : le champ `Prompt` dit explicitement quel workflow lancer :
     - **Ticket d'implémentation** (code) → `lance /dev`.
     - **Ticket SPIKE / recherche** (dans le DAG, distinct du SPIKE de planification de l'étape 4) → **`lance /plan`**, PAS `/dev` (mini-mission qui peut découvrir du travail, créer ses tickets et orchestrer son sous-ensemble — cf. **SPIKE = SOUS-PLAN RÉCURSIF**).
9. **SPIKE → DONE (GATE avant GO).** Une fois le plan terminé (User Story + toutes les tâches + DAG + liens) : d'abord **revue adverse du plan en contexte frais** (skill commons § VÉRIFICATION & BOUCLES levier 3 — subagent `reviewer` `opus` cherchant domaine/tâche/dépendance/contrat oublié), intégrer les GAPS ; puis **finaliser la description du ticket parapluie** (étape 7) ; PUIS **passer le ticket SPIKE de l'étape 4 en `DONE`**. **Le SPIKE DOIT être DONE avant tout `GO IMPLEMENTATION`.** (Multi-plans : chaque sous-plan met SON spike DONE quand SON domaine est planifié ; le plan racine met son spike de décomposition DONE quand tous les domaines sont dispatchés.)
10. **Attendre le `GO IMPLEMENTATION`** de l'utilisateur. Ne rien lancer avant. → onglet `[ASK] <résumé>`.
11. **GO IMPLEMENTATION — orchestrateur superviseur.** → onglet **`[MAIN]` <résumé>** dès le GO et **pendant toute la supervision**. Superviser le DAG jusqu'au bout :
    - **Passer le ticket parapluie (User Story) en `In Progress`** (skill `/jira`) — première action du GO.
    - **Créer le dossier de statuts partagé** : `STATUS_DIR=/tmp/claude_plan_<EPIC>_status` (header `TMP_INDEX`).
    - **Spawn les tickets racines uniquement** (`DEPENDS_ON` vide), chacun dans **une nouvelle surface DANS LE MÊME WORKSPACE CMUX que le process qui lance**, en passant `status_dir` + `ticket`. Le workflow lancé dépend du TYPE (`/dev` pour l'implémentation, **`/plan` pour un SPIKE**) :
      ```
      ~/.claude/scripts/cmux-tab.sh spawn "<contenu du champ Prompt du ticket + numéro JIRA + consigne: lance /dev OU /plan selon le type>" "<TICKET-XXX résumé>" ~/Documents/projects/malt "$STATUS_DIR" TICKET-XXX
      ```
      `spawn` injecte le préambule "report ton statut" et écrit `SPAWNED`. Cible `$CMUX_SURFACE_ID` (jamais `$CMUX_WORKSPACE_ID`). **cwd OBLIGATOIRE = `~/Documents/projects/malt`** (repo principal ; l'agent lancé crée son propre worktree).
    - **Écouter chaque ticket en vol** : `~/.claude/scripts/cmux-tab.sh await "$STATUS_DIR" TICKET-XXX` **EN BACKGROUND** (`run_in_background: true`) — jamais en foreground (cap 10 min). Le harness re-réveille l'orchestrateur à la sortie.
    - **SPAWN IDEMPOTENT — un timeout/erreur du spawn ≠ échec (RÈGLE ABSOLUE).** Le tool Bash cape à 120s ; un spawn qui « timeout » a pu quand même créer la surface + lancer l'agent. Donc : (1) `spawn` lents en `run_in_background: true` ; (2) **AVANT de re-spawn un ticket, vérifier que `<ticket>.status` est VIDE** (`[ -s <dir>/<ticket>.status ]`) — un re-spawn crée un **worker DOUBLON sur le même worktree/branche** (incident BILL-2909). Flakiness workspace persistante → `new-surface --workspace <shortref>` en dur (cf. `[[reference_cmux_tab_workspace_resolution]]`).
    - **RESCAN DES ENFANTS DE L'UMBRELLA — À CHAQUE RÉVEIL (RÈGLE ABSOLUE).** Un ticket lancé peut **créer de nouveaux tickets** sous le parapluie (invisibles des status files). À chaque réveil, **re-lister les enfants de la User Story via `/jira`** (`parent = <umbrella>`), comparer au DAG connu, **intégrer tout orphelin** (liens, mode `/dev` vs `/plan`, spawn+await quand débloqué). Le JIRA est la source de vérité du périmètre, pas le `STATUS_DIR`.
    - **HEURES CALMES 20h–7h (RÈGLE ABSOLUE, cf. CLAUDE.md) :** à chaque réveil, vérifier `date +%H%M` AVANT tout spawn ou relance d'`await`. Si ∈ [2000,0659] → **STOPPER NET** : ne PAS spawn, ne PAS relancer d'`await`, ne PAS programmer de réveil. Consigner l'état du DAG et le point de reprise, onglet `[WAIT]` « paused — quiet hours ». **Relance manuelle le matin.**
    - **Déclencher les dépendants** : à chaque réveil, recalculer les tickets dont **tous** les `DEPENDS_ON` sont dans un état terminal *satisfaisant* (**`MERGED`** pour un `/dev`, **`DONE`** pour un SPIKE lancé en `/plan`), les spawn, lancer leur `await` en background. Répéter jusqu'au **drainage complet du DAG**.
    - **Gestion `BLOCKED`** : si un `await` sort en **code 3** (ticket `BLOCKED`), surfacer (onglet `[ASK]`) et **ne pas spawn** les dépendants tant que non résolu.
12. **Fin du Claude de plan** — une fois le DAG drainé (**toutes les tâches `MERGED`**). → onglet `[END] <résumé>` :
    - **Passer le ticket parapluie (User Story) en `To Validate`** (skill `/jira`). Ne **jamais** passer en `Done` soi-même (validation humaine).
    - S'arrêter en **laissant le terminal CMUX ouvert**. (Blocage explicité au lieu du drainage → laisser la User Story en `In Progress` et surfacer.)

## CYCLE DE VIE DU TICKET PARAPLUIE (User Story) — RÈGLE ABSOLUE

Le ticket parapluie (la **User Story** de l'étape 7) DOIT refléter l'état réel du chantier. Transitions (skill `/jira`) :

- **`To Do` / `Open`** — à la création (étape 7), tant que le GO n'a pas été donné.
- **`In Progress`** — dès le `GO IMPLEMENTATION` (étape 11, première action).
- **`To Validate`** — quand **toutes** les tâches enfants sont `MERGED` (étape 12).
- **`Done`** — **jamais par Claude** : transition humaine après validation.

En **multi-plans** : chaque sous-plan gère le cycle de vie de SA User Story de domaine ; le plan racine gère la User Story racine si elle existe (sinon l'EPIC fait office de parapluie, non transitionné par Claude).

## MODE MULTI-PLANS — découper en sous-plans par domaine

Quand le besoin est **trop gros pour un seul plan** (cf. DÉCISION D'ÉCHELLE), le plan racine ne planifie PAS les tâches lui-même : il **découpe par domaine fonctionnel** et **délègue chaque domaine à un sous-plan** dans sa propre surface CMUX, puis les **orchestre exactement comme le GO IMPLEMENTATION orchestre les `/dev`** (spawn + await background + réveil).

Étapes du plan **racine** :

1. **Titre onglet** + **Sync master** (comme ci-dessus).
2. **EPIC** — demander l'EPIC parapluie du chantier.
3. **SPIKE de décomposition** (skill `/jira`, sous l'EPIC) — représente **la recherche du plan racine** : identifier les domaines fonctionnels impactés et leurs interfaces. Le passer **In Progress**.
4. **Analyse de décomposition** (sous-agents) — identifier les **domaines fonctionnels** (accounting, billing, payments, front, ...) et les **dépendances inter-domaines** (DAG de domaines).
5. **Créer le dossier de statuts** : `STATUS_DIR=/tmp/claude_plan_<EPIC>_status` (header `TMP_INDEX`).
6. **Spawn un `/plan` par domaine racine** (domaines sans dépendance inter-domaine), chacun dans **une nouvelle surface du MÊME workspace CMUX** (`$CMUX_SURFACE_ID`), cwd `~/Documents/projects/malt` :
   ```
   ~/.claude/scripts/cmux-tab.sh spawn "<prompt de sous-plan : périmètre du domaine + 'lance /plan' + ORIENTATION>" "<DOMAINE résumé>" ~/Documents/projects/malt "$STATUS_DIR" DOMAIN-<domaine>
   ```
   **ORIENTATION OBLIGATOIRE dans le prompt de chaque sous-plan** :
   - **l'EPIC** parapluie à utiliser (le sous-plan crée SA User Story de domaine sous cette EPIC) ;
   - le **périmètre exact** du domaine (ce qui est à lui, ce qui appartient aux autres) ;
   - les **interfaces/contrats** partagés avec les autres domaines (éviter les collisions) ;
   - la consigne : **le sous-plan crée son PROPRE SPIKE**, planifie SON domaine, met son spike DONE, puis **attend le GO** ;
   - le `STATUS_DIR` + son identifiant `DOMAIN-<domaine>` pour reporter.
7. **Orchestrer les sous-plans** — pour chaque domaine en vol : `await "$STATUS_DIR" DOMAIN-<domaine>` **EN BACKGROUND**. À chaque réveil (un sous-plan reporte `PLANNED` = domaine planifié + spike DONE), déclencher les **sous-plans dépendants**. Répéter jusqu'à ce que **tous les domaines soient planifiés**.
   - États reportés par un sous-plan : `IN_PROGRESS` (analyse) → `PLANNED` (tickets créés, spike domaine DONE, attente GO) → `DONE` (DAG du domaine drainé) | `BLOCKED`.
8. **SPIKE racine → DONE** une fois **tous les domaines dispatchés et planifiés** (tous `PLANNED`).
9. **GO IMPLEMENTATION en multi-plans** — deux niveaux :
   - **Chaque sous-plan supervise le GO de SON domaine** (il spawn les `/dev` de son domaine et draine son propre DAG). Relayer le `GO` de l'utilisateur à chaque sous-plan ; le sous-plan reporte `DONE` quand son domaine est drainé.
   - **Le plan racine supervise les sous-plans** : déclenche les domaines dépendants au fur et à mesure des `DONE`/`PLANNED`, jusqu'au drainage du **DAG de domaines**.
10. **Fin** — le plan racine s'arrête seulement quand **tous les sous-plans sont `DONE`** (ou blocage explicité), terminal CMUX laissé ouvert.

## SPIKE = SOUS-PLAN RÉCURSIF — RÈGLE ABSOLUE

Un **ticket SPIKE présent dans le DAG** (recherche/investigation/cadrage — à NE PAS confondre avec le SPIKE de planification du plan lui-même, étape 4) n'est **jamais lancé en `/dev`**. Il est lancé en **`/plan`**, car une investigation débouche presque toujours sur du travail à créer et orchestrer. Conséquences :

- **Un SPIKE lancé en `/plan` est un plan complet** : sa propre analyse, peut **créer ses propres tickets** (sous la même EPIC / un sous-parapluie qu'il crée), construire **son sous-DAG**, **superviser son fan-out** (spawn `/dev` et/ou `/plan` enfants, await, réveils). Comme le MODE MULTI-PLANS, mais déclenché par un SPIKE.
- **RÉCURSIVITÉ SUR N NIVEAUX** : un plan lance un SPIKE-plan, qui lance un SPIKE-plan… Pas de profondeur fixe. Chaque niveau orchestre son sous-arbre.
- **REMONTÉE DE STATUT (chaque niveau → son parent)** : un SPIKE-plan reporte dans le `STATUS_DIR` de SON parent : `IN_PROGRESS` → `PLANNED` (sous-tickets créés + son SPIKE de planif DONE) → `DONE` (**son sous-DAG entièrement drainé**) | `BLOCKED`. Le parent traite `DONE` (pas `MERGED`) comme signal de déblocage des dépendants d'un SPIKE.
- **CONSCIENCE GLOBALE DE L'ORCHESTRATEUR MAÎTRE** : le `/plan` racine reste **responsable de tout l'arbre** : (1) **RESCAN DES ENFANTS DE L'UMBRELLA** à chaque réveil ; (2) propage les `BLOCKED` d'un sous-niveau jusqu'à l'utilisateur ; (3) chantier `To Validate` seulement quand **tout l'arbre** est drainé. Chaque orchestrateur intermédiaire fait de même pour son sous-arbre.
- **PROMPT de spawn d'un SPIKE** : donner l'EPIC/parapluie où pousser ses tickets, le périmètre de l'investigation, le `STATUS_DIR` + son identifiant, et la consigne « **lance /plan** ; si tu découvres du travail, crée les tickets sous l'umbrella et orchestre-les ; reporte `PLANNED` puis `DONE`/`BLOCKED` ».

## Rappels transverses (voir CLAUDE.md et skill `malt-workflow-commons`)

- **ORCHESTRATION PAR SOUS-AGENTS** (CLAUDE.md) : thread principal = orchestrateur ; déléguer exploration/analyse ; sous-agents retournent une CONCLUSION, pas des dumps ; sous-tâches indépendantes → plusieurs sous-agents dans le même message ; **dimensionner le model** (§ DOSAGE DU MODÈLE, CLAUDE.md).
- **VÉRIFICATION & BOUCLES** (skill commons) : preuve jamais affirmation ; `/goal` = drainage complet du DAG ; revue adverse du plan (subagent `reviewer` `opus`) avant le GATE SPIKE→DONE ; `/loop` option de supervision (jamais `Monitor`).
- **SPIKE de recherche OBLIGATOIRE** : tout `/plan` (racine ou sous-plan) crée un ticket SPIKE pour SA propre recherche et le passe **DONE avant le GO IMPLEMENTATION**.
- **SPIKE du DAG = `/plan`, jamais `/dev`** : un ticket SPIKE parallélisable se lance en `/plan` (sous-plan récursif) ; l'orchestrateur maître garde la conscience globale de l'arbre et rescanne les enfants de l'umbrella à chaque réveil.
- **LANGUE** (CLAUDE.md) : titres/descriptions/liens JIRA en **ANGLAIS** ; seuls le champ `Prompt` (`customfield_11956`) / prompts de spawn en français.
- **LABEL `Accounting/Bookkeeping` — RÈGLE ABSOLUE** : **TOUT** ticket créé par un `/plan` (EPIC, User Story parapluie, SPIKE, tâches, sous-plans) porte le label dès sa création.
- **ASSIGNATION — RÈGLE ABSOLUE** : le plan ne s'assigne **AUCUN** ticket. Assignation à `stephen.begot` posée **uniquement au démarrage du dev** par le `/dev` correspondant.
- **cmux-tab** : résolution workspace via `$CMUX_SURFACE_ID` (piège : `identify --surface` cassé, suit le focus).
