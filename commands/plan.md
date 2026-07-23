---
description: WORKFLOW DE PLAN — analyser un besoin large, produire un plan + DAG de dépendances, créer les tickets JIRA parallélisables, puis (sur GO) superviser le fan-out CMUX (un /dev par ticket) jusqu'au drainage du DAG. Si le besoin est trop gros → découper en sous-plans par domaine fonctionnel (une surface /plan par domaine) et les orchestrer. Déclenché quand l'utilisateur décrit un besoin large sans ticket en entrée.
---

## Input

$ARGUMENTS

Le besoin large à découper (pas de ticket JIRA en entrée).

### QUESTIONS À CHOIX DE RÉPONSES — RÈGLE ABSOLUE

Quand ce workflow pose une question à l'utilisateur **avec des choix de réponses** (options prédéfinies, arbitrage de découpage/scope/design, `AskUserQuestion`) :

- **Explication détaillée AVANT les choix — obligatoire.** Avant de présenter les options, exposer le problème **point par point** : contexte, ce qui est en jeu, pourquoi la décision se pose, et pour **chaque option** ses implications / tradeoffs. But : que l'utilisateur comprenne réellement l'issue et les solutions, pas qu'il tranche à l'aveugle.
- **INTERDICTION D'UTILISER CAVEMAN dans ce cas précis.** L'explication du problème ET les libellés/descriptions des choix sont rédigés en **prose normale, complète et claire**. Caveman reste actif pour tout le reste de la session — on ne le suspend QUE pour la formulation de la question et de ses options.

### ACCÈS JIRA — MCP ou fallback API REST (RÈGLE ABSOLUE)

Toute écriture/lecture JIRA de ce workflow (EPIC, User Story, tâches, liens de dépendance, transitions de statut) passe par le skill `/jira`. **Si le MCP Atlassian n'est PAS connecté** (auth échoue / tools `jira_*` indisponibles) → **NE PAS bloquer** : utiliser le **fallback API REST v3** documenté dans le skill `/jira` (curl + Basic auth, env `.zshrc`). Le skill `/jira` gère les deux : MCP si dispo, sinon REST. Vérifier au besoin : `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/myself"` → 200.

## DÉCISION D'ÉCHELLE — AVANT TOUT

Avant de planifier, trancher : **plan simple** ou **multi-plans** ?

- **Plan simple** (défaut) : le besoin tient dans **un seul domaine fonctionnel** → suivre le WORKFLOW ci-dessous tel quel.
- **Multi-plans** : le besoin est **trop gros pour un seul plan** — il traverse **plusieurs domaines fonctionnels** (ex : un chantier sur tout le monorepo Malt, ou touchant accounting + billing + payments + front). Dans ce cas, **NE PAS tout planifier soi-même** : faire **un sous-plan par domaine fonctionnel**, chacun dans sa propre surface CMUX, et les **orchestrer** comme le GO IMPLEMENTATION orchestre les `/dev`. → voir la section **MODE MULTI-PLANS**.

Signal « trop gros » : > ~8-10 tâches parallélisables, ou le découpage naturel se fait d'abord **par domaine** avant de se faire par tâche. En cas de doute, proposer le mode multi-plans à l'utilisateur.

## WORKFLOW DE PLAN — RÈGLE ABSOLUE

### PRÉFIXES DE HEADER CMUX — TABLE UNIFIÉE (RÈGLE ABSOLUE, commune à `/plan` `/dev` `/hotfix`)

Mettre à jour le titre de l'onglet cmux **de Claude** (jamais celui de l'utilisateur ; via `CMUX_SURFACE_ID`) **dès qu'un changement d'état survient**, avec `~/.claude/scripts/cmux-tab.sh phase <PREFIX> "<résumé 3-4 mots>"` :

| Préfixe | Signification |
|---|---|
| `[MAIN]` | Processus qui en **orchestre d'autres** — reste en `[MAIN]` en permanence (c'est le cas d'un `/plan` **pendant le GO IMPLEMENTATION** : il supervise le DAG / les sous-plans). |
| `[PLAN]` | En **réflexion / analyse**, rien de commencé (sync master, analyse, découpage, création des tickets). |
| `[IMPL]` | En cours d'implémentation (peu utilisé par `/plan` racine ; c'est l'état des `/dev` enfants). |
| `[PIPE]` | Implémentation terminée, en attente / en fix de pipeline verte. |
| `[MR (numMR)]` | En attente d'approval sur une MR. |
| `[ASK]` | Une **question a été posée à l'utilisateur**, on attend sa réponse (ex : attente du `GO IMPLEMENTATION`, arbitrage de découpage, blocage remonté). |
| `[BLOCK]` | Processus **bloqué** pour une raison diverse (pas une question utilisateur). |
| `[WAIT]` | En **attente d'un autre processus** (ex : `await` d'un ticket/sous-plan en vol) ou attente diverse. |
| `[CLEAN]` | En cours de clean (worktree, artefacts). |
| `[END]` | Tout est terminé — dernier état avant de fermer (DAG drainé, User Story `To Validate`). |

**Règles :** la session **DOIT** mettre à jour le header dès qu'elle fait quelque chose ; le header peut **revenir en arrière** ; le résumé décrit CE QU'ON FAIT (3-4 mots, jamais le numéro de ticket seul) et reste identique entre phases, seul le préfixe change.

### Étapes

TOUTES les étapes sont OBLIGATOIRES, dans l'ordre :

1. **Titre onglet** → `[PLAN] <résumé 3-4 mots>` (phase d'analyse/planification).
2. **Sync master — OBLIGATOIRE AVANT toute analyse.** L'étude DOIT partir de la dernière version de `master`. Depuis le repo principal (`cd ~/Documents/projects/malt`) :
   ```
   git fetch origin master
   git checkout master
   git pull --ff-only origin master
   ```
   - **Vérifier `git branch --show-current` == `master` et `git status` propre** avant le `pull`. Si le working tree est sale (modifs traînant sur master, cf. GIT WORKFLOW) → **STOPPER**, porter les modifs vers un worktree puis `git checkout -- .`, et ne reprendre qu'une fois master vierge.
   - `--ff-only` : si le pull n'est pas fast-forward → **STOPPER** et surfacer à l'utilisateur (master local divergent = anomalie à résoudre, jamais de merge/rebase silencieux).
   - **Ne rien éditer/committer sur master** : cette étape sert uniquement à mettre master à jour pour que l'analyse et la base des worktrees (`origin/master`) soient à jour.
3. **EPIC** — demander à l'utilisateur l'**EPIC** sous laquelle rattacher le travail (le plus tôt possible : le SPIKE et la User Story en ont besoin). En **mode multi-plans**, c'est cette EPIC que chaque sous-plan recevra pour savoir **où pousser ses tickets**.
4. **Ticket SPIKE de recherche — OBLIGATOIRE (skill `/jira`).** Créer **UN ticket SPIKE** sous l'EPIC qui représente **LA recherche/étude DE CE PLAN** (l'effort de planification lui-même : exploration du code, cadrage, découpage, DAG).
   - Type `Spike` si disponible dans le projet, sinon `Task` avec titre préfixé `[SPIKE]`.
   - **Titre + Description en ANGLAIS**, décrivant le périmètre étudié et le livrable attendu (plan + tickets + DAG).
   - Le passer en **In Progress** au début de l'analyse.
   - **En mode multi-plans** : ce SPIKE couvre la recherche de **décomposition** (identifier les domaines) ; **chaque sous-plan créera SON PROPRE SPIKE** pour la recherche de son domaine.
5. **Analyse** — étudier le prompt utilisateur, le code, et les sources fournies. **Déléguer l'exploration à des sous-agents** (ORCHESTRATION). Sur repo Malt : note Obsidian `[[Monorepo Malt - Carte technique]]` d'abord (`/obsidian` recherche), sous-agent si insuffisant.
   - **VÉRIFICATION DES SOURCES CONTRE LE RÉEL — RÈGLE ABSOLUE.** La mémoire (notes Obsidian, mémoire persistante, souvenirs de chantiers passés) est un **point de départ, jamais une vérité**. Elle est **souvent périmée ou fausse** (drift). Avant d'ancrer une décision de plan sur un fait mémorisé, **le confirmer contre le réel** :
     - **Code** : lire le fichier/symbole réel **sur `master` fraîchement synchronisé** (étape 2), pas le souvenir de sa localisation/signature. Si un sous-agent cite un fichier/fonction/flag → il DOIT donner le `path:line` vu dans le code courant, pas de mémoire.
     - **Runtime / prod** : pour tout fait sur le comportement en prod (état d'un FF, volumétrie, erreurs, chemin réellement emprunté) → **vérifier via Datadog** (`/datadog` : logs/traces/métriques) plutôt que supposer.
     - **JIRA / FF / config** : état d'un ticket, d'un feature flag, d'une config → lire la source vivante (JIRA, fichiers ff4j, app-config), pas la mémoire.
     - **Drift** : si le réel contredit une note Obsidian → **corriger la note** (`/obsidian` capture) dans la foulée.
     - Chaque affirmation structurante du plan doit être **traçable à une source réelle vérifiée cette session** (path:line, requête Datadog, ticket JIRA). Une hypothèse non vérifiée doit être **marquée explicitement** comme telle dans le plan, jamais présentée comme un fait.
6. **Plan complet + DAG de dépendances** — plan d'implémentation découpé en **tâches parallélisables**. Chaque tâche parallélisable = 1 tâche JIRA. **Identifier explicitement les dépendances entre tâches** (B ne démarre qu'après merge de A) → construire le **DAG** : tâches **racines** (sans dépendance, lançables tout de suite) vs **dépendantes** (déclenchées après merge de leur(s) parent(s)).
7. **User Story unique** (skill `/jira`) — créer **UNE SEULE User Story** sous l'EPIC. Elle **décrit le besoin métier global** (le QUOI, pas le COMMENT). But : ne pas polluer le board de l'EPIC avec plein de tickets — toutes les tâches vivent **à l'intérieur** de cette story et sont regroupées par elle (plus besoin de préfixe de groupe sur les titres).
   - **Titre + Description OBLIGATOIREMENT en ANGLAIS**, point de vue **MÉTIER**.
   - **DESCRIPTION DU PARAPLUIE = complète, belle, remise à jour après étude — RÈGLE ABSOLUE.** Le ticket parapluie (que ce soit cette User Story, ou l'EPIC en mode multi-plans) porte **la description de référence du besoin**. Après l'analyse (étape 5-6), **réécrire/mettre à jour cette description** pour qu'elle reflète la compréhension affinée du besoin : mise en forme propre et professionnelle (jamais un paragraphe brut) — résumé du besoin, contexte, objectif métier, périmètre couvert, découpage en tâches (liste des sous-tickets et leur rôle), définition of done globale. Lisible de bout en bout par une personne non technique du produit. C'est LA source de vérité du chantier ; ne pas la laisser à l'état d'ébauche de création.
   - **La User Story = le ticket parapluie dont le statut DOIT suivre l'avancée du chantier** (cf. CYCLE DE VIE DU TICKET PARAPLUIE ci-dessous). La laisser en `To Do` / `Open` à la création (tant que le GO n'a pas été donné).
8. **Création des tâches JIRA DANS la User Story** (skill `/jira`) — une tâche par tâche parallélisable, chacune **enfant de la User Story** (étape 7) via le champ **parent** (hiérarchie Epic → Story → Task/Sub-task). Chaque tâche :
   - **Titre + Description OBLIGATOIREMENT en ANGLAIS**, décrivant le besoin d'un point de vue **MÉTIER** (le QUOI, pas le COMMENT). Pas de préfixe : la User Story parente assure déjà le regroupement.
   - **DESCRIPTION = lisible par un non-technique produit — RÈGLE ABSOLUE.** La description N'EST PAS le prompt. Elle est **mise en forme proprement et professionnellement** (jamais un paragraphe brut) : un titre/résumé du besoin, des sections claires (contexte, objectif, critères d'acceptation / definition of done), bullets, gras sur les termes clés. Un PM ou une personne non technique doit la comprendre. **AUCUN bloc `PROMPT`, aucun détail d'implémentation technique dans la description.**
   - **Champ "Prompt" (`customfield_11956`) = la consigne d'implémentation, EN FRANÇAIS — RÈGLE ABSOLUE.** Le prompt exact qui servira à lancer la tâche va dans CE CHAMP, plus JAMAIS dans la description. Y inclure une ligne metadata **`DEPENDS_ON: TICKET-A, TICKET-B`** (ou `DEPENDS_ON: -` si racine).
     - **Le prompt doit être LE PLUS COMPLET POSSIBLE** : le travail doit être **mâché** pour le `/dev` qui l'implémentera, afin qu'il reste focus sur SA partie et **économise ses tokens** (pas de re-exploration). Y mettre : périmètre exact, fichiers/symboles concernés avec `path:line`, pattern jumeau à copier, contrats/interfaces partagés, cas de test attendus, pièges connus, et tout contexte partagé utile.
     - **Écriture du champ** (doc ADF) via API REST :
       ```
       curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -X PUT -H "Content-Type: application/json" \
         "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET>" \
         -d '{"fields":{"customfield_11956":{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":"<PROMPT complet>"}]}]}}}'
       ```
   - **Liens de dépendance JIRA** : pour chaque dépendance du DAG, créer un lien **"is blocked by"** (dépendant → parent).
   - **MODE DE LANCEMENT selon le TYPE de ticket — RÈGLE ABSOLUE** : le champ `Prompt` doit dire explicitement quel workflow lancer :
     - **Ticket d'implémentation** (code) → `lance /dev`.
     - **Ticket SPIKE / recherche / investigation** (dans le DAG, distinct du SPIKE de planification de l'étape 4) → **`lance /plan`**, PAS `/dev`. Un SPIKE n'est pas un simple "va chercher une réponse" : c'est une mini-mission qui peut **découvrir du travail, créer ses propres tickets et orchestrer son propre sous-ensemble** (cf. section **SPIKE = SOUS-PLAN RÉCURSIF**).
9. **SPIKE → DONE (GATE avant GO).** Une fois le plan terminé (User Story + toutes les tâches créées + DAG + liens de dépendance posés) : d'abord **finaliser la description du ticket parapluie** (cf. étape 7 — description complète, belle, avec la liste des sous-tickets et leur rôle, la DoD globale ; source de vérité du chantier), PUIS **passer le ticket SPIKE de l'étape 4 en `DONE`**. **Le SPIKE DOIT être DONE avant tout `GO IMPLEMENTATION`** — c'est le signal que la planification est close. (En multi-plans : chaque sous-plan met SON spike à DONE quand SON domaine est planifié ; le plan racine met son spike de décomposition à DONE quand tous les domaines ont été dispatchés/planifiés.)
10. **Attendre le `GO IMPLEMENTATION`** de l'utilisateur. Ne rien lancer avant. → onglet `[ASK] <résumé>` (question en attente).
11. **GO IMPLEMENTATION — orchestrateur superviseur.** → onglet **`[MAIN]` <résumé>** dès le GO et **pendant toute la supervision** (ce process orchestre d'autres process, il reste en `[MAIN]` ; utiliser `[WAIT]` seulement si l'on veut expliciter une attente d'`await`, mais `[MAIN]` est l'état par défaut de l'orchestrateur). Superviser le DAG jusqu'au bout (voir `/cmux-tab`, section « Fan-out avec dépendances ») :
    - **Passer le ticket parapluie (User Story, étape 7) en `In Progress`** (skill `/jira`) — première action du GO, signale que le chantier démarre.
    - **Créer le dossier de statuts partagé** : `STATUS_DIR=/tmp/claude_plan_<EPIC>_status` (header `TMP_INDEX`).
    - **Spawn les tickets racines uniquement** (`DEPENDS_ON` vide), chacun dans **une nouvelle surface DANS LE MÊME WORKSPACE CMUX que le process qui lance** (jamais autre workflow ni workspace focus utilisateur), en passant `status_dir` + `ticket`. **Le workflow lancé dépend du TYPE du ticket** (`/dev` pour l'implémentation, **`/plan` pour un SPIKE**, cf. étape 8 et section SPIKE = SOUS-PLAN RÉCURSIF) :
      ```
      ~/.claude/scripts/cmux-tab.sh spawn "<contenu du champ Prompt (customfield_11956) du ticket + numéro JIRA + consigne: lance /dev OU /plan selon le type>" "<TICKET-XXX résumé>" ~/Documents/projects/malt "$STATUS_DIR" TICKET-XXX
      ```
      `spawn` injecte le préambule "report ton statut" et écrit `SPAWNED`. Cible le workspace du process appelant (`$CMUX_SURFACE_ID`, jamais `$CMUX_WORKSPACE_ID`). Chaque surface = un Claude exécutant `/dev` (ticket d'implémentation) OU `/plan` (ticket SPIKE → sous-plan récursif).
      **cwd OBLIGATOIRE = `~/Documents/projects/malt`** (repo principal). Jamais un worktree ni le `$PWD` du Claude de plan : l'agent lancé crée son propre worktree (ou, pour un `/plan`, ses propres tickets + worktrees enfants).
    - **Écouter chaque ticket en vol** : `~/.claude/scripts/cmux-tab.sh await "$STATUS_DIR" TICKET-XXX` **EN BACKGROUND** (`run_in_background: true`) — jamais en foreground (cap 10 min du tool Bash). Le harness re-réveille l'orchestrateur à la sortie de l'`await`.
    - **SPAWN IDEMPOTENT — un timeout/erreur du spawn ≠ échec (RÈGLE ABSOLUE).** Le tool Bash cape à 120s ; or `cmux new-surface`+`send` peut dépasser ce cap OU la résolution workspace `cmux workspace list` hang par intermittence sous charge. Un spawn qui « timeout » ou sort en erreur **a pu quand même créer la surface + lancer l'agent**. Donc : (1) lancer les `spawn` lents **en `run_in_background: true`** ; (2) **AVANT de re-spawn un ticket, vérifier que `<ticket>.status` est VIDE** (`[ -s <dir>/<ticket>.status]`) — un re-spawn sur un ticket déjà lancé crée un **worker DOUBLON sur le même worktree/branche** → deux agents s'écrasent mutuellement (incident vécu BILL-2909). En cas de flakiness workspace persistante, bypasser la résolution en appelant `new-surface --workspace <shortref>` en dur (cf. [[reference_cmux_tab_workspace_resolution]]).
    - **RESCAN DES ENFANTS DE L'UMBRELLA — À CHAQUE RÉVEIL (RÈGLE ABSOLUE).** Un ticket lancé (`/dev` OU `/plan`) peut **créer de nouveaux tickets** sous le parapluie (bug découvert, spike de suivi, sous-tâche). Ces tickets sont **invisibles de tes status files**. Donc à chaque réveil, **re-lister les enfants de la User Story parapluie via `/jira`** (`parent = <umbrella>`), comparer à ton DAG connu, et **intégrer tout orphelin** : poser ses liens de dépendance, décider son mode (`/dev` vs `/plan`), le spawn+await quand débloqué. Ne JAMAIS te fier uniquement au `STATUS_DIR` : le JIRA (enfants de l'umbrella) est la source de vérité du périmètre.
    - **Déclencher les dépendants** : à chaque réveil (un `await` sort), recalculer les tickets dont **tous** les `DEPENDS_ON` sont dans un état terminal *satisfaisant*, les spawn, et lancer leur `await` en background. État terminal satisfaisant = **`MERGED`** pour un ticket d'implémentation (`/dev`), **`DONE`** (sous-DAG drainé) pour un ticket SPIKE lancé en `/plan`. Répéter jusqu'au **drainage complet du DAG** (arbre entier, tous niveaux).
    - **Gestion `BLOCKED`** : si un `await` sort en **code 3** (ticket `BLOCKED`), surfacer le blocage à l'utilisateur (onglet `[ASK]`) et **ne pas spawn** les dépendants de ce ticket tant que non résolu. Un SPIKE-sous-plan qui bute sur une **réponse externe** (équipe tierce, décision humaine) reporte `BLOCKED` et remonte la question exacte à poser.
12. **Fin du Claude de plan** — une fois le DAG drainé (**toutes les tâches `MERGED`**). → onglet `[END] <résumé>` :
    - **Passer le ticket parapluie (User Story) en `To Validate`** (skill `/jira`) — toutes les tâches sont mergées, le chantier attend validation. Ne **jamais** passer la User Story directement en `Done` soi-même : la validation est un acte humain.
    - S'arrêter, en **laissant le terminal CMUX ouvert**. Ne pas fermer la surface. (Si blocage explicité au lieu du drainage complet → laisser la User Story en `In Progress` et surfacer le blocage, cf. gestion `BLOCKED`.)

## CYCLE DE VIE DU TICKET PARAPLUIE (User Story) — RÈGLE ABSOLUE

Le ticket parapluie (la **User Story** de l'étape 7) DOIT refléter l'état réel du chantier à tout moment. Transitions obligatoires (skill `/jira`) :

- **`To Do` / `Open`** — à la création (étape 7), tant que le GO n'a pas été donné.
- **`In Progress`** — dès le `GO IMPLEMENTATION` (étape 11, première action).
- **`To Validate`** — quand **toutes** les tâches enfants sont `MERGED` (étape 12).
- **`Done`** — **jamais par Claude** : transition humaine après validation.

En **multi-plans** : chaque sous-plan gère le cycle de vie de SA User Story de domaine ; le plan racine gère la User Story racine si elle existe (sinon l'EPIC fait office de parapluie et n'est pas transitionnée par Claude).

## MODE MULTI-PLANS — découper en sous-plans par domaine

Quand le besoin est **trop gros pour un seul plan** (cf. DÉCISION D'ÉCHELLE), le plan racine ne planifie PAS les tâches lui-même : il **découpe par domaine fonctionnel** et **délègue chaque domaine à un sous-plan** dans sa propre surface CMUX, puis les **orchestre exactement comme le GO IMPLEMENTATION orchestre les `/dev`** (spawn + await background + réveil).

Étapes du plan **racine** :

1. **Titre onglet** + **Sync master** (comme ci-dessus).
2. **EPIC** — demander l'EPIC parapluie du chantier.
3. **SPIKE de décomposition** (skill `/jira`, sous l'EPIC) — représente **la recherche du plan racine** : identifier les domaines fonctionnels impactés et leurs interfaces. Le passer **In Progress**.
4. **Analyse de décomposition** (sous-agents) — identifier les **domaines fonctionnels** (ex : accounting, billing, payments, front, ...) et les **dépendances inter-domaines** (un domaine peut être bloqué par un autre → DAG de domaines).
5. **Créer le dossier de statuts** : `STATUS_DIR=/tmp/claude_plan_<EPIC>_status` (header `TMP_INDEX`).
6. **Spawn un `/plan` par domaine racine** (domaines sans dépendance inter-domaine), chacun dans **une nouvelle surface du MÊME workspace CMUX** (`$CMUX_SURFACE_ID`), cwd `~/Documents/projects/malt` :
   ```
   ~/.claude/scripts/cmux-tab.sh spawn "<prompt de sous-plan : périmètre du domaine + 'lance /plan' + ORIENTATION>" "<DOMAINE résumé>" ~/Documents/projects/malt "$STATUS_DIR" DOMAIN-<domaine>
   ```
   **ORIENTATION OBLIGATOIRE dans le prompt de chaque sous-plan** (sinon il ne saura pas où pousser ses tickets) :
   - **l'EPIC** parapluie à utiliser (le sous-plan crée SA User Story de domaine sous cette EPIC) ;
   - le **périmètre exact** du domaine (ce qui est à lui, ce qui appartient aux autres domaines) ;
   - les **interfaces/contrats** partagés avec les autres domaines (pour éviter les collisions) ;
   - la consigne : **le sous-plan crée son PROPRE SPIKE**, planifie SON domaine, met son spike DONE, puis **attend le GO** ;
   - le `STATUS_DIR` + son identifiant `DOMAIN-<domaine>` pour reporter son statut.
7. **Orchestrer les sous-plans** — pour chaque domaine en vol : `await "$STATUS_DIR" DOMAIN-<domaine>` **EN BACKGROUND**. À chaque réveil (un sous-plan reporte `PLANNED` = son domaine est planifié + son spike DONE), déclencher les **sous-plans dépendants** (dont tous les domaines parents sont `PLANNED`). Répéter jusqu'à ce que **tous les domaines soient planifiés**.
   - États reportés par un sous-plan : `IN_PROGRESS` (analyse) → `PLANNED` (tickets du domaine créés, spike domaine DONE, en attente de GO) → `DONE` (DAG du domaine drainé) | `BLOCKED` (surfacer à l'utilisateur).
8. **SPIKE racine → DONE** une fois **tous les domaines dispatchés et planifiés** (tous `PLANNED`).
9. **GO IMPLEMENTATION en multi-plans** — deux niveaux d'orchestration :
   - **Chaque sous-plan supervise le GO de SON domaine** (il est un `/plan` complet → il spawn les `/dev` de son domaine et draine son propre DAG). Relayer le `GO IMPLEMENTATION` de l'utilisateur à chaque sous-plan (ou déclencher automatiquement selon le DAG de domaines) ; le sous-plan reporte `DONE` quand son domaine est drainé.
   - **Le plan racine supervise les sous-plans** : il déclenche les domaines dépendants au fur et à mesure des `DONE`/`PLANNED`, jusqu'au drainage du **DAG de domaines**.
10. **Fin** — le plan racine s'arrête seulement quand **tous les sous-plans sont `DONE`** (ou blocage explicité), terminal CMUX laissé ouvert.

## SPIKE = SOUS-PLAN RÉCURSIF — RÈGLE ABSOLUE

Un **ticket SPIKE présent dans le DAG** (recherche/investigation/cadrage — à NE PAS confondre avec le SPIKE de planification du plan lui-même, étape 4) n'est **jamais lancé en `/dev`**. Il est lancé en **`/plan`**, car une investigation débouche presque toujours sur du travail à créer et à orchestrer. Conséquences :

- **Un SPIKE lancé en `/plan` est un plan complet à part entière** : il fait sa propre analyse, peut **créer ses propres tickets** (sous la même EPIC / le même parapluie, ou un sous-parapluie qu'il crée), construire **son propre sous-DAG**, et **superviser son propre fan-out** (spawn `/dev` et/ou `/plan` enfants, await, réveils). Exactement comme le MODE MULTI-PLANS, mais déclenché par un SPIKE et non par un découpage de domaines.
- **RÉCURSIVITÉ SUR N NIVEAUX** : un plan lance un SPIKE-plan, qui lance un SPIKE-plan, qui lance… Il n'y a pas de profondeur fixe. Chaque niveau est un orchestrateur pour son sous-arbre.
- **REMONTÉE DE STATUT (chaque niveau → son parent)** : un SPIKE-plan reporte dans le `STATUS_DIR` de SON parent, via son identifiant de ticket, les états : `IN_PROGRESS` (analyse) → `PLANNED` (sous-tickets créés + son propre SPIKE de planif DONE) → `DONE` (**son sous-DAG entièrement drainé**) | `BLOCKED` (dont blocage sur réponse externe). Le parent traite `DONE` (pas `MERGED`) comme le signal de déblocage des dépendants d'un ticket SPIKE.
- **CONSCIENCE GLOBALE DE L'ORCHESTRATEUR MAÎTRE** : le `/plan` racine reste **responsable de l'orchestration globale de tout l'arbre**. Il ne "perd" pas la main sur un sous-arbre : (1) il applique le **RESCAN DES ENFANTS DE L'UMBRELLA** à chaque réveil (les sous-plans créent des tickets → capter les orphelins) ; (2) il propage les `BLOCKED` d'un sous-niveau jusqu'à l'utilisateur ; (3) le chantier n'est `To Validate` que quand **tout l'arbre** (tous niveaux, tous tickets) est drainé. Chaque orchestrateur intermédiaire fait de même pour son sous-arbre et remonte l'agrégat.
- **PROMPT de spawn d'un SPIKE** : donner l'EPIC/parapluie où pousser ses tickets, le périmètre de l'investigation, le `STATUS_DIR` + son identifiant pour reporter, et la consigne « **lance /plan** ; si tu découvres du travail, crée les tickets sous l'umbrella et orchestre-les ; reporte `PLANNED` puis `DONE`/`BLOCKED` ».

## Rappels transverses (voir CLAUDE.md)

- **ORCHESTRATION PAR SOUS-AGENTS** : thread principal = orchestrateur ; déléguer exploration/analyse ; sous-agents retournent une CONCLUSION, pas des dumps. Sous-tâches indépendantes → plusieurs sous-agents dans le même message.
- **SPIKE de recherche OBLIGATOIRE** : tout `/plan` (racine ou sous-plan) crée un ticket SPIKE pour SA propre recherche et le passe **DONE avant le GO IMPLEMENTATION**.
- **SPIKE du DAG = `/plan`, jamais `/dev`** : un ticket SPIKE parallélisable se lance en `/plan` (sous-plan récursif) ; il peut créer + orchestrer ses propres tickets ; l'orchestrateur maître garde la conscience globale de l'arbre et rescanne les enfants de l'umbrella à chaque réveil.
- **LANGUE** : titres/descriptions/liens JIRA en **ANGLAIS** ; seuls le champ `Prompt` (`customfield_11956`) / prompts de spawn en français.
- **cmux-tab** : résolution workspace via `$CMUX_SURFACE_ID` (piège : `identify --surface` cassé, suit le focus).
