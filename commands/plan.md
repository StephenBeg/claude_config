---
description: WORKFLOW DE PLAN — planificateur pur : analyser un besoin large, produire un plan + DAG de dependances, creer les tickets JIRA parallelisables, passer son spike en DONE, puis passer le relais a /orchestrator. Declenche quand l'utilisateur decrit un besoin large sans ticket en entree.
---

## Input

$ARGUMENTS

Le besoin large à découper (pas de ticket JIRA en entrée). **Si le prompt est un lien `Lis $WF/<T>.md et exécute` dont le header contient `[ORCHESTRATION]` + `Lance /plan en mode enfant-orchestré`** → **MODE ENFANT-ORCHESTRÉ** (voir section dédiée) : planifier + reporter `PLANNED`, ne rien orchestrer.

**Invoquer le skill `malt-workflow-commons` EN PREMIER** — source de vérité unique des règles partagées : questions à choix, escalade archi & tradeoffs, accès JIRA, **création de ticket JIRA (statut `Ready` obligatoire)**, préfixes CMUX, vérification des sources contre le réel, vérification & boucles de contrôle, travail découvert. Ce workflow y renvoie par nom de section et ne les recopie pas. (`/plan` n'a ni smoke-run ni MR ni livrable de dev, et **n'orchestre pas** — l'orchestration vit dans `/orchestrator`.)

**Décisions d'archi = escalade (commons § DÉCISIONS D'ARCHI & TRADEOFFS).** Le découpage en tickets, la forme des contrats d'API, le choix des patterns et les frontières de domaine sont des décisions d'architecture : le plan ne fige aucun choix structurant seul. **Le défaut d'un `/plan` est de POSER la question, pas de trancher** : toute décision rencontrée pendant l'analyse s'inscrit au registre et passe par le **§ CHECKPOINT DÉCISIONS**, qui est un GATE bloquant **avant la création du premier ticket**. Un tradeoff tranché en silence puis découvert dans JIRA est une violation, pas un gain de temps.

## RÈGLE ABSOLUE — /plan NE SPAWN JAMAIS

Séparation des concerns : `/plan` **planifie** (analyse, DAG, tickets JIRA, liens), `/orchestrator` **spawn et supervise**. Un `/plan` — racine OU enfant — **ne spawn JAMAIS** de surface CMUX (`/dev` ou `/plan`), ne lance jamais d'`await`, ne déclenche jamais de dépendant. Au GO, le plan racine **passe le relais à `/orchestrator`** (surface dédiée). Un plan enfant se contente de créer ses tickets et de reporter `PLANNED`. C'est la correction du bug « N orchestrateurs dans le même workspace ».

## DÉCISION D'ÉCHELLE — avant tout

Trancher : **plan simple** ou **multi-domaines** ?

- **Plan simple** (défaut) : le besoin tient dans **un seul domaine fonctionnel** → suivre le WORKFLOW ci-dessous (tickets d'implémentation directs).
- **Multi-domaines** : le besoin traverse **plusieurs domaines** (ex : chantier monorepo entier, ou accounting + billing + payments + front). Ne pas tout planifier soi-même → créer **un ticket spike-plan par domaine** (type SPIKE, `lance /plan`), que l'orchestrateur fera planifier par un `/plan` enfant. → voir **MODE MULTI-DOMAINES**.

Signal « trop gros » : > ~8-10 tâches parallélisables, ou le découpage naturel se fait d'abord **par domaine** avant de se faire par tâche. Doute → proposer le multi-domaines à l'utilisateur.

## WORKFLOW DE PLAN

**HEADER CMUX** (commons § PRÉFIXES) : `[PLAN]` en analyse/découpage, `[ASK]` en attente du `GO`. **Jamais `[ORCH]`** — `/plan` n'orchestre plus (c'est `/orchestrator` seul qui porte `[ORCH]`). `[JUGE]` pendant le round de juge.

Étapes dans l'ordre :

1. **Titre onglet** → `[PLAN] <résumé 3-4 mots>`.
2. **Sync master — AVANT toute analyse** (l'étude part de la dernière version de `master`). Depuis le repo principal (`cd ~/Documents/projects/malt`) :
   ```
   git fetch origin master && git checkout master && git pull --ff-only origin master
   ```
   Vérifier `git branch --show-current == master` et `git status` propre avant le `pull`. Working tree sale → STOPPER, porter vers un worktree puis `git checkout -- .` (GIT WORKFLOW). Pull non fast-forward → STOPPER (master local divergent = anomalie). Ne rien éditer/committer sur master.
3. **EPIC** — demander l'EPIC de rattachement le plus tôt possible (le SPIKE et la User Story en ont besoin). En mode enfant-orchestré, l'EPIC/umbrella est fournie dans le prompt d'orchestration.
4. **SPIKE de planification** (skill `/jira`, sous l'EPIC) — UN ticket représentant **la recherche/étude DE CE PLAN** (exploration, cadrage, découpage, DAG). Type `Spike` sinon `Task` titre `[SPIKE]`. Titre + description **en anglais**. Le passer **In Progress** au début.
5. **Analyse** — étudier prompt, code, sources. Déléguer l'exploration à des sous-agents (skill `malt-orchestration` : délégation + dosage model). Sur repo Malt : note `[[Monorepo Malt - Carte technique]]` d'abord (`/obsidian`), sous-agent si insuffisant. **Vérifier les sources contre le réel** (commons § VÉRIFICATION DES SOURCES) : chaque fait structurant du plan traçable à une source vérifiée cette session ; hypothèse non vérifiée marquée comme telle.
6. **Plan + DAG** — découper en **tâches parallélisables** (1 tâche = 1 ticket JIRA), identifier les dépendances (B démarre après merge de A) → DAG : **racines** (sans dépendance) vs **dépendantes**. **Appliquer `## DÉCOUPAGE DES TÂCHES` (R1→R5) AVANT de figer le DAG** — le découpage naïf (1 ligne = 1 ticket) est interdit (conflits, contrats affaiblis, MR illisibles).
7. **CHECKPOINT DÉCISIONS — GATE BLOQUANT** (§ CHECKPOINT DÉCISIONS ci-dessous). Le DAG proposé et **toutes** les décisions du registre sont posés à l'utilisateur **avant la création du moindre ticket de travail** (tâches, spikes-plan, User Story parapluie). Seuls l'EPIC et le SPIKE de planification de l'étape 4 échappent au gate. Onglet → `[ASK]`. Aucun ticket n'est créé tant que les réponses ne sont pas revenues et écrites dans le registre.
8. **User Story unique** (skill `/jira`, sous l'EPIC) — UNE SEULE, décrit le **besoin métier global** (le QUOI). Toutes les tâches vivent à l'intérieur (ne pas polluer le board EPIC). Titre + description **en anglais**, point de vue métier.
   - **Description du parapluie = complète et remise à jour après étude** : c'est LA source de vérité du chantier. Après analyse (5-6) et checkpoint (7), réécrire : résumé, contexte, objectif métier, périmètre, **décisions validées par l'utilisateur**, découpage en tâches, definition of done. Lisible par un non-technique (skill `writing-for-humans`).
   - **Statut → `Ready` dès la création** (commons § CRÉATION DE TICKET JIRA) : sans ça le parapluie reste en `Selected for Development` et **n'apparaît sur aucun board**. Il n'existe **pas** de statut `To Do`/`Open` dans ce workflow. Le passage `In Progress`/`To Validate` est fait par `/orchestrator`, pas par `/plan`.
9. **Tâches JIRA dans la User Story** (skill `/jira`) — une par tâche parallélisable, **enfant de la User Story** (champ parent : Epic → Story → Task). **Suivre la checklist commons § CRÉATION DE TICKET JIRA pour CHAQUE ticket** (parent, langue, `Prompt`, label, liens, pas d'assignation, **statut `Ready` vérifié**). Chaque tâche :
   - Titre + description **en anglais**, point de vue métier (le QUOI), lisible par un non-technique. **La description N'EST PAS le prompt** : aucun bloc `PROMPT`, aucun détail d'implémentation technique dedans.
   - **Champ "Prompt" (`customfield_11956`) = la consigne d'implémentation, en français** — écrite via `/jira` (ADF). C'est le travail **mâché** pour le `/dev` : périmètre exact, fichiers/symboles `path:line`, pattern jumeau à copier, contrats partagés, cas de test attendus, pièges. Inclure `DEPENDS_ON: TICKET-A, TICKET-B` (ou `DEPENDS_ON: -` si racine).
   - **Les décisions du registre s'y reportent telles qu'elles ont été validées**, avec la mention `DÉCIDÉ AVEC L'UTILISATEUR` ou `TRANCHÉ SEUL`. Un `Prompt` ne contient **aucun** choix structurant absent du registre : si j'en découvre un en rédigeant, retour au checkpoint (§ CHECKPOINT DÉCISIONS, point 5).
   - **MODE DE LANCEMENT selon le TYPE** (dans le champ Prompt, lu par l'orchestrateur) : ticket d'implémentation → `lance /dev` ; ticket SPIKE/recherche du DAG → **`lance /plan` (mode enfant-orchestré)**, jamais `/dev`. C'est l'orchestrateur qui écrira le bon header d'inbox selon le TYPE.
   - **Liens de dépendance JIRA** : lien **"is blocked by"** (dépendant → parent) pour chaque arête du DAG. **Ces liens sont la source de vérité du DAG pour l'orchestrateur** — les poser correctement.
   - **NE JAMAIS assigner à la création (RÈGLE ABSOLUE).** L'assignation à `stephen.begot` est faite par le `/dev` lui-même au passage `In Progress`.
   - **Statut → `Ready` juste après le `POST /issue`, et le VÉRIFIER** (commons § CRÉATION DE TICKET JIRA). Un ticket laissé en `Selected for Development` est hors board : l'orchestrateur peut le capter, un humain ne le voit pas. Un plan n'est `PLANNED` que si **tous** ses tickets sont en `Ready`.
10. **SPIKE → DONE (GATE avant GO)** — une fois plan + tâches + DAG + liens prêts : (a) **JUGE MÉTIER — obligatoire, UN SEUL ROUND, solo comme enfant-orchestré** (skill `malt-judge-loop`) : sous-agent **`judge`** frais, `CHECKPOINT=plan-gate`, `ROUND=1`, payload = umbrella + clés des tickets créés + DAG + **le registre des décisions** + le besoin d'origine, `REPORT_FILE=<SURFACE_FILE>` (`$WF/<T>.md` en orchestré, `/Users/stephenbegot/claude-exchange-llm/_solo/<SPIKE>.md` en solo). Il juge le MÉTIER du découpage : domaine/tâche/dépendance/contrat oublié, **contrôle R1→R5** (slices back/front à recoller, confettis à fusionner, zones chaudes multi-tickets, dépendances croisées/manquantes) et **contrôle le registre** : toute décision lisible dans les tickets doit y figurer, et toute ligne `TRANCHÉ SEUL` doit porter ses trois conditions dont le `path:line` du pattern jumeau — sinon c'est un GAP bloquant. Il lit les tickets et liens **réels** dans JIRA. `NEEDS_WORK` → intégrer chaque GAP avec preuve lisible (ticket/lien JIRA réel cité), puis **escalade `[ASK]`** : l'utilisateur tranche (passer le SPIKE en DONE tel quel, retravailler, ou autoriser un second juge). **Jamais de round 2 de sa propre initiative** ; (b) finaliser la description du parapluie (étape 8) ; (c) passer le SPIKE de l'étape 4 en `DONE`. **Le SPIKE DOIT être DONE avant tout GO.**
11. **Récap puis attente du `GO IMPLEMENTATION`.** Avant de demander le GO, afficher en clair (prose normale, skill `asking-the-user` pour la forme) : la liste des tickets créés en une ligne chacun, et **la liste des décisions `TRANCHÉ SEUL` du registre**, pour qu'il puisse objecter avant que le travail parte. Ne rien lancer avant le GO. → `[ASK]`.
12. **GO IMPLEMENTATION — HAND-OFF vers `/orchestrator` (surface dédiée).** Le plan **n'orchestre pas lui-même**. Il vérifie les HEURES CALMES (`date +%H%M` ; si ∈ [2000,0659] → STOPPER NET, consigner, relance manuelle le matin — CLAUDE.md), crée le `STATUS_DIR`, puis **spawn une surface `/orchestrator`** dans le même workspace CMUX et lui passe EPIC/umbrella + `STATUS_DIR` :
    ```
    # STATUS_DIR DURABLE — jamais /tmp (macOS le purge en cours de chantier).
    STATUS_DIR=/Users/stephenbegot/claude-exchange-llm/<EPIC>/_status && mkdir -p "$STATUS_DIR"
    ~/.claude/scripts/cmux-tab.sh spawn \
      "Lance /orchestrator. EPIC=<EPIC> UMBRELLA=<User Story key> STATUS_DIR=$STATUS_DIR. Draine tout le DAG des enfants de l'umbrella." \
      "ORCH <résumé chantier>" \
      ~/Documents/projects/malt
    ```
    (Spawn simple, sans `status_dir`/`ticket` : l'orchestrateur n'est pas un ticket suivi.) Une fois l'orchestrateur lancé, le `/plan` racine **se termine** — l'orchestrateur porte tout le GO (spawn, await, RESCAN, drainage, transitions de statut de la User Story). → `[END]`.
13. **Fin du plan** — surface orchestrateur lancée → `[END]`, terminal laissé ouvert. Le cycle de vie de la User Story (`In Progress` → `To Validate`) appartient désormais à `/orchestrator`.

## § CHECKPOINT DÉCISIONS — AVANT TOUTE CRÉATION DE TICKET (RÈGLE ABSOLUE)

Un plan qui crée ses tickets sans checkpoint livre des décisions déjà figées : l'utilisateur les découvre en lisant JIRA, quand le travail est déjà découpé. **Aucun ticket n'est créé tant que le checkpoint n'a pas reçu ses réponses.**

### 1. Le registre des décisions — un fichier, pas une intention

Pendant l'analyse (étapes 5-6), **chaque** décision rencontrée s'écrit au fil de l'eau dans un registre durable :

- solo : `/Users/stephenbegot/claude-exchange-llm/_solo/<SPIKE>-decisions.md`
- orchestré : `$WF/<TICKET>-decisions.md`

Une ligne par décision : `| # | la décision | TRANCHÉ SEUL ou À POSER | preuve (pattern jumeau `path:line`) ou réponse de l'utilisateur |`

Le registre est relu par le juge à l'étape 10. Une décision lisible dans les tickets et absente du registre est un GAP bloquant.

### 2. Le défaut est À POSER

**Trancher seul n'est permis que si les TROIS conditions sont vraies**, et la troisième est citable :

1. **aucun effet observable** : ni écran, ni donnée, ni message, ni délai, ni surface d'API publique, ni mode de dégradation ;
2. **réversible à l'intérieur du ticket**, sans migration ni changement de contrat ;
3. **un pattern jumeau existe déjà** dans le repo et je le copie — `path:line` cité dans le registre.

Une seule condition fausse → `À POSER`. Ne valent pas justification : « c'est évident », « je prends le plus simple », « on ajustera au `/dev` », « c'est ce que fait le legacy ».

### 3. Toujours une question, jamais une initiative

- le **périmètre** : ce qu'on fait, et surtout ce qu'on ne fait **pas** dans ce chantier ;
- le **découpage en tickets et leur ordre** — le DAG lui-même ;
- tout **contrat neuf ou modifié** : endpoint, champ, event, table, colonne, statut, enum ;
- **feature flag** : oui ou non, et qui l'allume ;
- toute **migration ou reprise de données existantes** ;
- tout **changement visible** : message, écran, délai, comportement d'un flux existant ;
- toute **suppression ou dépréciation** de code, de flux, de colonne ;
- le **mode de dégradation** : ce qu'on fait quand la donnée manque, qu'il y a un doublon, que l'appel échoue ;
- toute **nouvelle dépendance** ou librairie ;
- tout ce qui **sort du périmètre annoncé** (notamment hors accounting : on n'y touche pas sans accord explicite).

### 4. Poser le checkpoint

Onglet → `[ASK]`. Deux blocs, dans cet ordre, **au format du skill `asking-the-user`** (le charger avant de rédiger) :

- **a. Le DAG proposé, 10 lignes maximum** — une ligne par ticket : `titre court — ce qu'il livre — dépend de X`. Puis la question : regrouper, scinder, ou c'est bon ?
- **b. Les questions du registre**, par lots de 4 maximum (`AskUserQuestion`), les plus structurantes d'abord. Chacune tient dans son plafond de 150 mots, options d'une ligne, une reco.

Réponses reçues → les écrire dans le registre, puis créer les tickets. **Aucun ticket de travail avant** : les seuls `POST /issue` autorisés en amont du checkpoint sont l'EPIC de rattachement et le SPIKE de planification.

### 5. Après le checkpoint

Une décision découverte pendant la rédaction des tickets **ne se tranche pas en passant** : l'ajouter au registre, et si elle est `À POSER`, rouvrir un mini-checkpoint (`[ASK]`) avant d'écrire le ticket concerné. Un plan peut poser trois checkpoints, ce n'est pas un échec.

### Red flags — le checkpoint n'a pas eu lieu

- Le registre compte moins de 3 lignes sur un chantier de plus de 3 tickets : je n'ai pas cherché les décisions, j'ai déroulé.
- Une ligne `TRANCHÉ SEUL` sans `path:line` en preuve.
- Un champ `Prompt` qui contient un choix (nom de table, forme de contrat, valeur par défaut, comportement en cas d'erreur) absent du registre.
- Le premier `[ASK]` de la surface est le GO.
- Je m'apprête à écrire « j'ai pris l'option la plus simple, on pourra revenir dessus ».

## MODE ENFANT-ORCHESTRÉ (spike-plan lancé par `/orchestrator`)

Prompt d'entrée = un **lien vers MON inbox** (`Lis $WF/<T>.md et exécute`). **Lire ce fichier EN PREMIER** : son header (écrit par l'orchestrateur) contient `[ORCHESTRATION] STATUS_DIR=<dir> TICKET=<ticket>`, les chemins de mes inbox (le mien, orchestrateur), et l'instruction `Lance /plan en mode enfant-orchestré`. Le `/plan` est alors un **planificateur enfant** : il planifie SON périmètre et **reporte son statut**, sans orchestrer.

- **Report obligatoire** à chaque transition :
  ```
  ~/.claude/scripts/cmux-tab.sh report --notify <ORCH_SURFACE> <STATUS_DIR> <TICKET> <STATE> "<detail>"
  ```
  `--notify <ORCH_SURFACE>` (UUID lu dans le header) **réveille** l'orchestrateur : c'est le seul mécanisme qui fait avancer le DAG (skill `malt-surface-exchange` § RÉVEIL). Absent du header → omettre.
  `STATE` ∈ `IN_PROGRESS` (analyse démarrée) | `PLANNED` (tickets créés + liens JIRA posés + spike de planif DONE — compte de tickets en detail) | `BLOCKED` (blocage humain — raison).
- **Inbox d'échange (si le header liste des inbox)** — invoquer le skill `malt-surface-exchange`. Poser `MYIN="$WF/<T>.md"` (MON inbox — je l'écoute, et les juges y archivent leurs comptes rendus) et `OIN="$WF/_inbox/orchestrator.md"` (j'y poste STEP/DONE), annoncer ces chemins ABSOLUS au démarrage (§ ANNONCE) : notifier chaque étape dans `$OIN` (`note --notify "$ORCH_SURFACE" … "STEP:…"`, couplé au header — le `--notify` est ce qui réveille l'orchestrateur), lancer le **round de juge** au step 10 (sous-agent `judge`, `REPORT_FILE=$MYIN`), poser la checklist `DONE` sur `$OIN` avant `PLANNED`. Sans objet en solo (le round de juge reste dû, avec son `SURFACE_FILE` solo).
- **Suivre le WORKFLOW ci-dessus étapes 3→10** (checkpoint décisions inclus) (EPIC/umbrella fournies dans le prompt ; créer ses tickets **sous l'umbrella** ou un sous-parapluie qu'il crée dessous ; poser les liens `is blocked by` entre ses propres tickets ; spike DONE).
- **RECÂBLAGE DES DÉPENDANTS DU SPIKE (RÈGLE ABSOLUE — clé du déblocage).** Le plan racine a pu créer des tickets B qui dépendent de CE spike (`B is blocked by <SPIKE>`). Ces B ont besoin du **résultat** de l'investigation, pas de sa simple planification. Avant de reporter `PLANNED`, pour chaque dépendant pré-existant du spike : **retirer le lien `B is blocked by <SPIKE>` et le remplacer par `B is blocked by <tickets-feuilles produits>`** (les tickets terminaux dont B a réellement besoin). Ainsi le DAG lu par l'orchestrateur ne contient plus que des dépendances vers des tickets réels à merger — pas de dépendance vers le spike lui-même. Repérer les dépendants du spike : `/jira` liens entrants du spike (`is blocked by` inverse).
- **LE CHECKPOINT DÉCISIONS RESTE DÛ EN MODE ENFANT (règle absolue).** Un plan enfant ne se dispense pas de poser ses questions sous prétexte que le fan-out tourne : il pose son checkpoint sur SA surface (`AskUserQuestion`), reporte `BLOCKED` avec le motif « checkpoint décisions » le temps d'attendre, puis reprend. Un DAG qui attend une réponse coûte moins cher qu'un chantier entier construit sur un choix jamais validé.
- **NE PAS attendre de GO, NE PAS spawn, NE PAS orchestrer.** Dès le spike DONE + recâblage fait → `report … PLANNED` (compte de tickets en detail) puis clore. **L'orchestrateur unique absorbe les tickets créés à son RESCAN de l'umbrella** et les intègre au DAG global (impl → `/dev`, nouveaux spikes → `/plan` enfant). Après recâblage, `PLANNED` signifie « tickets créés + liens JIRA à jour » : l'orchestrateur ne débloque plus JAMAIS sur `PLANNED` seul, uniquement sur `MERGED` des bloqueurs réels.
- **Récursion de planning autorisée** : un plan enfant PEUT créer d'autres tickets spike-plan (sous-domaines à re-planifier). Il les crée simplement comme des tickets JIRA sous l'umbrella (`lance /plan`) ; c'est encore l'orchestrateur unique qui les fera planifier. **Jamais de fan-out imbriqué.**

## DÉCOUPAGE DES TÂCHES — JUSTE MILIEU (RÈGLE ABSOLUE)

Des tickets **ni trop petits ni trop gros**, découpés par **unité de valeur logique**, peu de collisions, ordre de dépendances propre. Le sur-découpage coûte plus qu'il ne rapporte. Appliquer R1→R5 dans l'ordre.

**R1 — Slice VERTICAL par défaut (une micro-feature = UN ticket back+front).** Back ET front couplés par un contrat neuf → un seul ticket. Sinon on livre un contrat avec des champs facultatifs (le front n'existe pas encore) puis on les repasse en requis → dette + deux MR. *Exception (back/front séparés)* : back volumineux en soi (nouvelle table, migration, logique non triviale) OU contrat déjà stable et partagé → back racine, front dépendant, contrat requis dès le back. Bon slice = comportement observable de bout en bout, testable seul, MR relisable en une passe.

**R2 — REGROUPER les petites modifs de même nature et même zone.** Plusieurs petites modifs (front OU back) sur la même zone/module/flux → un seul ticket. Repère indicatif : une modif qui seule donnerait une MR de ~30 lignes sans logique propre est trop petite → la fusionner vers le ticket cohérent le plus proche. **Ce seuil sert UNIQUEMENT à fusionner vers le haut, jamais à scinder** un ticket cohérent qui dépasse (60, 120 lignes cohérentes = un seul ticket). Critère qui prime : cohérence fonctionnelle, pas le compte de lignes. Ne pas regrouper des modifs sans lien fonctionnel juste pour la taille.

**R3 — SINGLE-OWNER par fichier / zone chaude (anti-conflit).** Deux tickets parallèles ne doivent pas éditer lourdement le même fichier (1re cause de conflits en boucle). Repérer les zones chaudes (routeur, config Spring, barrel front, fichier de contrat, mapper central, `application.yml`, registration). Chaque zone chaude → un seul ticket propriétaire ; les autres deviennent **dépendants** (sérialisés). N tickets ajoutant tous une entrée au même registre → un ticket "socle" d'extensibilité + N dépendants légers, ou fusionner si trivial.

**R4 — ORDONNER pour éviter le rework (contrats & socles d'abord).** Le DAG reflète le flux réel de prod. **Socles d'abord** (racines) : contrat d'API figé, schéma/migration, port/interface partagé, DTO commun — tout ce que plusieurs tickets consomment. **Consommateurs ensuite** (dépendants) : partent d'une base déjà mergée → zéro champ facultatif transitoire, zéro re-travail. Éviter les dépendances croisées (A↔B = mauvais découpage → fusionner). Un ticket ne dépend que de ce qui change une interface qu'il consomme.

**R5 — TEST DE VÉRIFICATION (avant de figer le DAG).** Pour chaque ticket : (1) **Autonomie** — livre une valeur observable/testable seul ? sinon fusionner. (2) **Contrat** — force un champ facultatif transitoire (slice back/front) ? oui → fusionner vertical (R1). (3) **Collision** — édite lourdement un fichier qu'un ticket parallèle édite aussi ? oui → sérialiser ou fusionner (R3). (4) **Taille MR** — relisable en une passe (~100-400 lignes utiles) ? trop petit → fusionner ; trop gros/multi-sujets → scinder par sous-comportement. (5) **Ordre** — ses dépendances reflètent un vrai besoin d'interface amont ? sinon paralléliser.

La revue adverse du plan (étape 10) contrôle explicitement R1→R5. Le découpage R1→R5 est une **proposition**, pas une décision : il est validé par l'utilisateur au CHECKPOINT DÉCISIONS avant création des tickets.

## MODE MULTI-DOMAINES — découper en tickets spike-plan par domaine

Besoin trop gros (cf. DÉCISION D'ÉCHELLE) : le plan racine ne planifie PAS les tâches d'implémentation, il découpe par **domaine fonctionnel** et crée **un ticket spike-plan par domaine** (type SPIKE, `lance /plan`), sous l'umbrella. Il **ne spawn rien** : au GO, il passe le relais à `/orchestrator` comme un plan simple.

Étapes du plan **racine** (multi-domaines) :

1. **Titre onglet** + **Sync master** (comme ci-dessus).
2. **EPIC** parapluie du chantier (la **User Story racine** est créée à l'étape 6, après le checkpoint).
3. **SPIKE de décomposition** (sous l'EPIC) — recherche du plan racine : identifier les domaines impactés et leurs interfaces. **In Progress**.
4. **Analyse de décomposition** (sous-agents) — identifier les domaines (accounting, billing, payments, front...) et les dépendances inter-domaines (DAG de domaines).
5. **CHECKPOINT DÉCISIONS — GATE BLOQUANT** (§ CHECKPOINT DÉCISIONS) : poser le **découpage en domaines** et les décisions du registre (frontières entre domaines, interfaces partagées, ce qui est hors périmètre) **avant de créer le moindre ticket**. → `[ASK]`.
6. **Créer la User Story racine** (besoin global, décisions validées), puis **un ticket spike-plan par domaine racine**, sous l'umbrella, avec dans le champ `Prompt` (FR) : le périmètre exact du domaine, l'EPIC/umbrella à utiliser, les interfaces/contrats partagés (éviter collisions), la consigne « lance /plan (mode enfant-orchestré) : planifie ce domaine sous l'umbrella, pose les liens, reporte PLANNED ». `DEPENDS_ON` = les domaines dont il dépend. Liens JIRA `is blocked by`.
7. **SPIKE de décomposition → DONE** (après revue adverse du découpage en domaines).
8. **Attendre le `GO`** → `[ASK]`.
9. **GO → HAND-OFF `/orchestrator`** (identique à l'étape 12 du plan simple) : l'orchestrateur unique fait planifier chaque domaine par un `/plan` enfant (type spike), absorbe leurs tickets au RESCAN, et spawn les `/dev` correspondants. **Aucun sous-orchestrateur.**

## SPIKE = SOUS-PLAN RÉCURSIF (planning uniquement)

Un **ticket SPIKE présent dans le DAG** (recherche/investigation/cadrage — à distinguer du SPIKE de planification de l'étape 4) n'est jamais lancé en `/dev` mais en **`/plan` (mode enfant-orchestré)** : une investigation débouche presque toujours sur du travail à créer.

- **La récursion est purement du PLANNING** : un plan enfant peut créer des sous-tickets et de nouveaux spikes-plan (sous-arbre de planning arbitrairement profond). **L'ORCHESTRATION reste plate et centralisée** dans l'unique `/orchestrator` : aucun `/plan` ne spawn jamais.
- **Remontée de statut** : un `/plan` enfant reporte dans le `STATUS_DIR` de l'orchestrateur : `IN_PROGRESS` → `PLANNED` (sous-tickets créés + son SPIKE de planif DONE) → `BLOCKED`. L'orchestrateur traite `PLANNED` comme signal d'absorption des tickets créés (RESCAN de l'umbrella) et de déblocage des dépendants du spike.
- **Conscience globale = l'orchestrateur, pas le plan** : c'est `/orchestrator` qui reste responsable de tout l'arbre (RESCAN de l'umbrella à chaque réveil, propagation des `BLOCKED`, `To Validate` seulement quand tout l'arbre est drainé). Un `/plan` enfant ne suit rien après son `PLANNED`.

## Rappels spécifiques `/plan`

- **/plan NE SPAWN JAMAIS** (cf. RÈGLE ABSOLUE en tête) : pas de spawn de `/dev`/`/plan`, pas d'`await`, pas de déclenchement de dépendant, pas de transition `In Progress`/`To Validate` de la User Story. Tout ça appartient à `/orchestrator`.
- **Aucun ticket de travail avant le CHECKPOINT DÉCISIONS** (étape 7 ; EPIC et SPIKE de planification exceptés) : le registre des décisions est écrit, le DAG et les questions sont posés, les réponses sont revenues. Le défaut est de POSER ; trancher seul exige les trois conditions du § CHECKPOINT DÉCISIONS, dont un `path:line` citable.
- **Labels de squad** : TOUT ticket créé par un `/plan` (EPIC, User Story, SPIKE, tâches, spikes-plan) porte le label JIRA de squad dès sa création (skill `malt-squad-conventions`).
- **Statut de création** : TOUT ticket créé par un `/plan` est passé en **`Ready`** immédiatement après sa création (commons § CRÉATION DE TICKET JIRA) — seule exception, le SPIKE de planification qui part en `In Progress`.
- **Langue** : JIRA en anglais ; seuls le champ `Prompt` et les prompts de spawn en français.
- **Champ `Prompt` d'un ticket : jamais de consigne d'écrire le raisonnement en commentaire.** Le contexte va dans le `Prompt` lui-même ; le code produit reste sous le plafond 1-2 lignes (skill commons § DISCIPLINE DE COMMENTAIRE).
- Le reste (orchestration sous-agents & dosage model, git workflow, escalade archi, vérification & boucles) vit dans CLAUDE.md et `malt-workflow-commons` — ne pas le recopier ici.
