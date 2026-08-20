---
name: malt-workflow-commons
description: Règles communes aux workflows /dev /plan /hotfix (source de vérité unique, dédupliquée). Contient — questions à choix de réponses, accès JIRA MCP/fallback, préfixes de header CMUX, vérification des sources contre le réel, vérification & boucles de contrôle, smoke-run local, /end avec MR (vérif pipeline), travail découvert en cours de route, livrable final. Invoquer en PREMIER dans /dev, /plan, /hotfix.
---

# Workflow commons — /dev · /plan · /hotfix

Bloc de règles **partagées** par les trois workflows. Source de vérité UNIQUE : ne jamais recopier ces sections dans une commande — la commande invoque ce skill et renvoie à la section par son nom. Chaque commande **invoque ce skill en premier**, puis suit ses étapes propres.

Toutes les sections sont des **RÈGLES ABSOLUES**. Une commande peut n'utiliser qu'un sous-ensemble (ex : `/plan` n'a ni smoke-run ni MR ; `/orchestrator` est le seul à porter `[ORCH]` en continu — `/plan` planifie puis passe le relais et ne supervise rien).

---

## § QUESTIONS À CHOIX DE RÉPONSES

Quand un workflow pose une question à l'utilisateur **avec des choix de réponses** (options prédéfinies, arbitrage, `AskUserQuestion`) :

- **FORMULATION MÉTIER, SIMPLE, SANS CODE — RÈGLE ABSOLUE.** L'utilisateur ne lit **pas** le code et ne veut **aucun** détail technique dans la question. **Interdits dans l'énoncé ET dans les libellés/descriptions d'options** : noms de variables/fonctions/classes/fichiers, `path:line`, noms de tables/colonnes, termes d'archi bruts (port/adapter, event vs appel, DTO, endpoint, migration…), extraits de code. **Traduire chaque option en IMPACT CONCRET OBSERVABLE** : ce que ça change pour l'utilisateur final / le comportement du produit / les données visibles / le délai / la réversibilité. Si un choix technique n'a pas d'impact métier explicable simplement, c'est probablement un choix non différenciant que Claude tranche seul (cf. § DÉCISIONS D'ARCHI) — ne pas le poser.
  - ❌ « Faut-il router via `SyncCommandBus` ou appeler `NetsuiteRecordPusher` en direct ? »
  - ✅ « Quand un paiement arrive, on l'enregistre tout de suite au risque de rares doublons, ou on attend une confirmation (plus lent mais zéro doublon) ? »
- **Explication AVANT les choix — obligatoire, en langage clair.** Avant les options, exposer le problème **point par point** : la situation, ce qui est en jeu **pour le produit/métier**, pourquoi la décision se pose, et pour **chaque option** sa conséquence concrète (avantage / coût / risque), sans jargon. But : que l'utilisateur comprenne l'enjeu réel et tranche en connaissance de cause — pas à l'aveugle, pas noyé sous la technique.
- **Test avant d'envoyer** : « Un collègue non-développeur comprendrait-il la question et chaque option ? » Si non → reformuler en métier.
- **INTERDICTION D'UTILISER CAVEMAN dans ce cas précis.** L'explication du problème ET les libellés/descriptions des choix sont rédigés en **prose normale, complète et claire**. Caveman reste actif pour tout le reste de la session — on ne le suspend QUE pour la formulation de la question et de ses options.

---

## § DÉCISIONS D'ARCHI & TRADEOFFS — ESCALADE OBLIGATOIRE (jamais décider seul)

Défaut historique de Claude : **prendre trop de décisions d'archi et de tradeoffs seul**, puis les révéler après coup dans le livrable. **Ce comportement est INTERDIT.** Claude ne fait **AUCUN** choix d'architecture de sa propre initiative, et **escalade tout tradeoff différenciant AVANT de coder**, pas après.

### Ce qui doit TOUJOURS être escaladé à l'utilisateur (STOPPER + demander avant d'agir)

- **Toute décision d'ARCHITECTURE, sans exception.** Découpage en modules/couches/services, choix ou création d'un pattern (nouveau port/adapter, nouvelle abstraction, event vs appel direct, sync vs async, nouvelle table vs colonne, nouveau endpoint vs extension d'un existant), forme d'un contrat d'API, structure de données persistée, stratégie de migration, introduction d'une dépendance/librairie, frontière entre domaines. → **Claude ne trie JAMAIS ça seul.**
- **Tout tradeoff DIFFÉRENCIANT** : dès qu'au moins deux options mènent à un **résultat observablement différent** (comportement, perf, schéma de données, surface d'API, ergonomie, coût de maintenance, réversibilité). Si le choix **change le résultat**, il n'appartient pas à Claude → escalade.

### Ce qui NE nécessite PAS d'escalade (Claude tranche seul et le mentionne dans Tradeoffs)

- Choix **non différenciant** : les options convergent vers le même résultat observable (nom de variable interne, ordre de deux instructions sans effet, style de code déjà imposé par le repo, application mécanique d'un pattern jumeau **déjà existant** et non ambigu).
- **Application d'une convention/pattern déjà établi dans le repo** pour un cas identique : ce n'est pas une décision d'archi, c'est se conformer. (Mais **créer** ou **étendre** un pattern = archi → escalade.)
- **Doute → escalader.** Le seuil penche vers la question, pas vers l'initiative. Une escalade de trop coûte une question ; un choix d'archi de trop coûte une reprise complète + une MR à jeter.

### COMMENT escalader

- **AVANT de coder / avant de figer le plan**, pas dans le livrable final. Interrompre le workflow, poser la question via `AskUserQuestion`, attendre l'accord.
- Suivre **§ QUESTIONS À CHOIX DE RÉPONSES** : exposer le problème point par point, chaque option avec ses implications/tradeoffs, en **prose normale (pas caveman)**. Donner une **recommandation** (option en 1er, `(Recommended)`), mais **ne pas trancher à la place de l'utilisateur**.
- Onglet CMUX → `[ASK]` pendant l'attente (cf. § PRÉFIXES DE HEADER CMUX).
- **Ne jamais avancer « en attendant »** sur une branche qui présume la réponse : un choix d'archi non validé bloque, il ne se pré-implémente pas.
- Le point **Tradeoffs** du § LIVRABLE FINAL ne liste plus que les choix **non différenciants** tranchés seul + rappel des décisions **déjà validées** par l'utilisateur. Un tradeoff différenciant qui y apparaîtrait **sans avoir été validé en amont = violation de cette règle.**

---

## § ACCÈS JIRA — MCP ou fallback API REST

Toute interaction JIRA d'un workflow (lecture ticket, création, transitions de statut, commentaires, liens de dépendance) passe par le skill `/jira`. **Si le MCP Atlassian n'est PAS connecté** (auth échoue / tools `jira_*` indisponibles) → **NE PAS bloquer** : utiliser le **fallback API REST v3** documenté dans le skill `/jira` (curl + Basic auth, env `.zshrc`). Le skill `/jira` gère les deux : MCP si dispo, sinon REST. Vérifier au besoin :

**Transitions de statut = plomberie mécanique, DÉLÉGUER en `haiku` (skill `malt-orchestration` § dimensionnement model).** `In Progress`/`Review`/`To Validate`, auto-assignation, pose de labels, commentaire déjà rédigé → appel API déterministe, zéro raisonnement, ne pas l'exécuter inline dans la session principale (sonnet/opus). La session principale fournit la valeur (statut cible, texte du commentaire) au sous-agent `haiku`, qui exécute l'appel.

```
curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/myself"   # → 200
```

---

## § PRÉFIXES DE HEADER CMUX — TABLE UNIFIÉE

Mettre à jour le titre de l'onglet cmux **de Claude** (jamais celui de l'utilisateur ; cible via `CMUX_SURFACE_ID`) **dès qu'un changement d'état survient** :

```
~/.claude/scripts/cmux-tab.sh phase <PREFIX> "<résumé 3-4 mots>"   # crochets posés par le SCRIPT
~/.claude/scripts/cmux-tab.sh topic "<résumé>"                     # (re)pose le sujet seul
~/.claude/scripts/cmux-tab.sh sync                                 # recale sur le réel (branche + MR)
```

**Écrire le préfixe NU** (`phase MR "…"`, pas `phase "[MR (1234)]"`) : le script pose les crochets, valide le préfixe contre la liste (un préfixe inconnu est **refusé**) et injecte le numéro de MR tout seul dès qu'il est connu. Le résumé (`topic`) est **persistant** : il survit aux changements de phase ET à la compaction — inutile de le redonner à chaque `phase`.

**CE QUI EST AUTOMATIQUE (hooks — ne pas le refaire à la main).** L'état de workflow vit dans `~/claude-exchange-llm/_phase/<surface>.json` et des hooks déterministes le pilotent :
- `glab mr create` → numéro de MR mémorisé + header `[MR (n)]` posé **automatiquement**.
- `git push` → `[PIPE (n)]` + rappel du bloc de clôture.
- `git worktree add` → `[IMPL]`.
- `glab mr merge` → `merged`, `[CLEAN]`, rappel des 3 obligations restantes.
- **Réponse de l'utilisateur** → sortie automatique de `[ASK]`/`[BLOCK]`/`[WAIT]` vers la phase précédente. (Ne jamais laisser un `[ASK]` traîner : si la phase de retour n'est pas la bonne, en poser une explicitement.)
- **Fin de tour** → **BLOQUÉE** tant qu'une MR mergée n'a pas son `/end` écrit dans le log du jour (vérifié dans le fichier, pas déclaré).

Restent donc **à la charge de la session** : `[PLAN]`, `[ASK]`, `[BLOCK]`, `[WAIT]`, `[END]`, le `topic`, et tout retour arrière métier (`[MR]` → `[IMPL]` sur request changes).

**GARDE-FOU — RÈGLES ABSOLUES :**
- `[MAIN]` **N'EXISTE PLUS** (whitelist script). Le préfixe orchestrateur est **`[ORCH]`** — `/orchestrator` uniquement, en continu pendant tout le GO IMPLEMENTATION. Aucune autre surface ne pose jamais `[ORCH]`.
- `[JUGE]` **obligatoire** dès qu'une surface (`/dev`, `/hotfix`, `/plan`) lance son sous-agent `judge` et attend son verdict — le temps du round de jugement. Retour à la phase précédente (`[MR]`, `[PIPE]`, …) dès le verdict reçu (`OK` ou `NEEDS_WORK` traité).

| Préfixe | Signification |
|---|---|
| `[ORCH]` | Processus qui en **orchestre d'autres** — reste en `[ORCH]` en permanence (`/orchestrator` pendant le GO IMPLEMENTATION). Réservé à `/orchestrator` ; jamais posé par `/dev` `/hotfix` `/plan`. |
| `[JUGE]` | Sous-agent `judge` en cours d'exécution sur cette surface — round de contrôle radical-honesty en attente de verdict. |
| `[PLAN]` | En **réflexion / analyse**, rien de commencé (diagnostic, cadrage, étude du prompt, sync master, découpage). |
| `[IMPL]` | En **cours d'implémentation** (code + tests). |
| `[PIPE (numMR)]` | Implémentation terminée, **en attente / en fix de pipeline verte**. Dès qu'une MR existe, **inclure son numéro** : `[PIPE (1234)]`. Tant qu'aucune MR n'existe, `[PIPE]` seul. |
| `[MR (numMR)]` | En **attente d'approval sur une MR** (mettre le numéro : `[MR (1234)]`). |
| `[ASK]` | Une **question a été posée à l'utilisateur**, on attend sa réponse. |
| `[BLOCK]` | Processus **bloqué** pour une raison diverse (**pas** une question à poser à l'utilisateur). |
| `[WAIT]` | En **attente d'un autre processus** (ex : `await` d'un ticket/sous-plan en vol) ou attente diverse. |
| `[CLEAN]` | En **cours de clean** (worktree, artefacts). |
| `[END]` | **Tout est terminé** — dernier état avant de fermer (worktree cleané, `/end` exécuté, MR mergée / DAG drainé). |

**Règles :**
- La session **DOIT** mettre à jour le header **dès qu'elle fait quelque chose** — jamais laisser un header périmé.
- `[END]` ne se pose qu'**après** le `/end` réellement écrit (le hook de fin de tour le vérifie dans le log du jour).
- Le header peut **revenir en arrière** : ex `[MR (1234)]` → `[PIPE (1234)]` (fix demandé qui relance la pipeline) → `[MR (1234)]` ; ou `[MR (1234)]` → `[IMPL]` (request changes) → `[PIPE (1234)]` → `[MR (1234)]`.
- **Le résumé décrit CE QU'ON FAIT — jamais "impl du ticket X".** 3-4 mots sur le contenu réel, pas le mot "impl" ni le numéro de ticket seul. Le résumé reste **identique** entre phases ; seul le préfixe change.
  - ❌ `[IMPL] BILL-2607 impl`
  - ✅ `[IMPL] TRY PAR EVENTID`
- **Spécificités par workflow** : `[ORCH]` = **`/orchestrator`** pendant tout le GO IMPLEMENTATION (il supervise le DAG / les spikes-plan) — **et lui seul**. `/plan` ne porte JAMAIS `[ORCH]` (il planifie en `[PLAN]`, attend en `[ASK]`, passe le relais à `/orchestrator`, puis `[END]`). `/dev`/`/hotfix` ne posent JAMAIS `[ORCH]` non plus, même s'ils orchestrent un sous-agent ponctuel — `[ORCH]` est réservé à la surface `/orchestrator`.
- **`[JUGE]`** : posé par `/dev`/`/hotfix`/`/plan` (jamais `/orchestrator`) à chaque round de la LOOP JUGE (skill `malt-surface-exchange`), tant que le sous-agent `judge` tourne. Un nouveau round = repasser par `[JUGE]` à chaque fois (juge frais).

---

## § VÉRIFICATION DES SOURCES CONTRE LE RÉEL

La mémoire (notes Obsidian, mémoire persistante, souvenirs de chantiers passés) est un **point de départ, jamais une vérité**. Elle est **souvent périmée ou fausse** (drift). Avant d'ancrer une décision (plan, diagnostic, implémentation) sur un fait mémorisé, **le confirmer contre le réel** :

- **Code** : lire le fichier/symbole réel **sur `master` fraîchement synchronisé**, pas le souvenir de sa localisation/signature. Toute citation d'un sous-agent = `path:line` vu dans le code courant, jamais de mémoire.
- **Runtime / prod** : pour tout fait sur le comportement en prod (état d'un FF, volumétrie, erreurs, chemin réellement emprunté) → **vérifier via Datadog** (`/datadog` : logs/traces/métriques) ou **Sentry** (`/sentry-analyzer`) plutôt que supposer. **Le fetch brut = plomberie mécanique, DÉLÉGUER en `haiku`** (skill `malt-orchestration` § dimensionnement model) : lancer la requête `pup`/Sentry et remonter logs/traces/stacktrace/métriques bruts filtrés en CONCLUSION. La session principale fournit la requête cible et **interprète** le résultat (cause racine) — le fetch lui-même ne tourne jamais inline en sonnet/opus.
- **JIRA / FF / config** : état d'un ticket, d'un feature flag, d'une config → lire la source vivante (JIRA, fichiers ff4j, app-config), pas la mémoire.
- **Drift** : si le réel contredit une note Obsidian → **corriger la note** (`/obsidian` capture) dans la foulée.
- Chaque affirmation structurante doit être **traçable à une source réelle vérifiée cette session** (path:line, requête Datadog, ticket JIRA). Une hypothèse non vérifiée est **marquée explicitement** comme telle, jamais présentée comme un fait.

---

## § VÉRIFICATION & BOUCLES DE CONTRÔLE

Principe Anthropic : **donner à l'agent un moyen de vérifier son propre travail** — un signal pass/fail qu'il lit et sur lequel il itère seul, au lieu que l'humain soit la boucle de vérification. Cinq leviers :

1. **Preuve, jamais affirmation.** Toute conclusion « c'est vert / c'est fixé / ça boote » DOIT citer une **sortie réelle** : output de test, exit code de build, log `Started …Application in`, ligne Sonar `règle fichier:ligne`, statut de pipeline, état JIRA. Jamais « les tests passent » sans la sortie. (superpowers:verification-before-completion.)
2. **`/goal` — ligne d'arrivée mesurable et bornée.** Pour la vérif pré-livraison, poser un `/goal` explicite plutôt que juger à l'œil : un évaluateur re-teste la condition à chaque tour, l'agent boucle jusqu'à ce qu'elle tienne. Conditions typiques : 0 test en échec (modules touchés) ; service(s) touché(s) qui bootent ; 0 violation Sonar new-code + coverage ≥ 80 % ; scope = besoin du ticket, rien de plus. Pour `/orchestrator` : **DAG entièrement drainé** (toutes tâches `MERGED`, tous spikes-plan `PLANNED` avec leur sous-arbre `MERGED`, zéro orphelin au dernier RESCAN de l'umbrella). (`/plan`, lui, s'arrête au hand-off vers `/orchestrator` — il ne draine rien.) **Borne dure : ~6 tours max** — atteinte sans vert → surfacer (`[BLOCK]`), jamais d'acharnement.
3. **LOOP JUGE en CONTEXTE FRAIS — solo comme orchestré.** Le juge ne tourne JAMAIS dans le contexte qui a écrit le code/le plan (biais). C'est un **sous-agent `judge`** (`.claude/agents/judge.md`, `opus`, read-only) lancé par la surface elle-même au checkpoint, **un juge NEUF à chaque round**, rebouclé jusqu'à ce qu'un juge rende `OK` (4 rounds max → escalade `[ASK]`). Chaque juge écrit son **compte rendu** dans le fichier de la surface (`REPORT_FILE`) — trace auditable. Protocole complet : skill `malt-surface-exchange` § LOOP JUGE. Il n'existe **plus de surface `/judge`** ni d'inbox juge ; le subagent `reviewer` est remplacé par le juge à ces checkpoints.
   Dans les deux cas, le contrôleur ne voit QUE le diff (ou le plan) + la consigne (`Prompt`) + les critères, et cherche à **réfuter** : requirement non couvert, cas limite sans test, effet de bord hors scope, bug introduit (pour un plan : domaine/tâche/dépendance/contrat oublié). Retourne des **GAPS**, pas des préférences de style. Traiter correctness/scope ; **ne pas sur-corriger** le reste. Alternative outillée : skill `/code-review`. (Exploration : subagent **`explorer`** ; smoke-run : **`smoke-runner`**.)
   Un round `NEEDS_WORK` ne se traite jamais à moitié : le juge est déjà exhaustif en un seul passage, donc chaque GAP est fermé avec une **preuve rejouée** avant resoumission (skill `malt-surface-exchange` § LOOP JUGE) — sinon le round suivant retrouve du travail bâclé, pas de nouveaux problèmes.
4. **`/loop` — attente/polling auto-cadencé (option).** Pour surveiller un état externe qui évolue seul (pipeline CI, attente d'approbation `Approved`, `await` d'un DAG), `/loop` est l'alternative auto-cadencée aux réveils manuels. **Ne remplace PAS** la boucle `until` en background ni `ScheduleWakeup` : mécanismes équivalents. **L'outil `Monitor` reste INTERDIT** (un accord par événement bloque l'utilisateur). Intervalle calé sur la vitesse réelle de l'état surveillé (pipeline ~8 min → un check ~480 s, pas 8 checks de 60 s). **HEURES CALMES 20h–7h (CLAUDE.md) : ne JAMAIS programmer `/loop`/`ScheduleWakeup`/boucle `until` de suivi dans cette plage — vérifier `date +%H%M` avant, STOPPER NET si ∈ [2000,0659], consigner l'état, relance manuelle le matin.** Mécanique exacte de la boucle `until` (y compris le piège du process détaché qui ne notifie jamais) et son extension à l'attente d'`Approved` → skill `malt-pipeline-followup` § 3, seule source de vérité.
5. **Explore → Plan → Code.** Séparer compréhension et exécution pour ne pas résoudre le mauvais problème. Utile quand l'approche est incertaine / multi-fichiers / code peu connu. **À sauter** si le diff tient en une phrase. Dans ces workflows, l'explore sert surtout à **vérifier le plan mâché (`Prompt`) contre le code réel** (§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL), pas à tout re-découvrir.

---

## § SMOKE-RUN LOCAL (services modifiés — /dev · /hotfix)

Les tests verts ne prouvent PAS que le service boote : contexte Spring cassé (bean manquant/ambigu, `@Bean` dépendance non câblée, `NoResourceFoundException` 404 au boot, FF absent, migration Liquibase invalide, conflit de scan infra) ne sort qu'au démarrage. Pour **chaque service applicatif dont une ligne a été touchée** (projets `*-application` / porteurs d'un `bootRun`, ex `netsuite-connector`, `accounting-backend`) :

- **Déterminer les services impactés** : mapper les fichiers du diff (`git diff --name-only origin/master...`) vers leur projet Gradle applicatif. Ne lancer QUE ceux réellement touchés.
- **Déléguer au subagent `smoke-runner`** (`haiku`) qui encapsule la procédure : lancer `./gradlew :<application-project>:bootRun` en `run_in_background: true`, boucle `until` sur `Started …Application in` vs `APPLICATION FAILED TO START`/`BUILD FAILED`/`BeanCreationException`/`UnsatisfiedDependency`/`NoResourceFoundException`, **jamais `Monitor`**, timeout ~5 min, `pkill -f bootRun` après verdict. Il retourne une **CONCLUSION** : `BOOTED_OK` ou `BOOT_FAILED` + la cause racine extraite du log (pas le dump).
- **Si `BOOT_FAILED` par la faute du diff** → **bug à corriger** (systematic-debugging), fix + re-smoke-run jusqu'au boot vert. Ne pas pousser un service qui ne boote pas.
- **Si le boot échoue pour une raison d'ENVIRONNEMENT local** (devbox DB down, secret manquant, dépendance externe indispo — pas causé par le diff) → **ne pas bloquer** : consigner la raison dans le livrable (Tradeoffs), se rabattre sur la vérif pipeline du `/end`. Distinguer clairement « cassé par mon code » (bloquant) de « env local indispo » (non bloquant).

**TIPS bootRun local (éprouvés sur `accounting-backend`) :**
- **Nom de projet Gradle = basename du module, PAS le chemin.** `accounting-backend` vit dans `erp/accounting-backend` mais la task est `:accounting-backend:bootRun` — **jamais** `:erp:accounting-backend`.
- **Toujours le profil `dev`** : `./gradlew :<module>:bootRun --args='--spring.profiles.active=dev'`.
- **Le crash de WIRING Spring sort AVANT toute connexion DB/rabbit**, pendant le refresh du contexte → un boot cassé par le code se détecte **même sans devbox up**. Signal le plus rentable à guetter.
- **Frontière wiring vs env** : dès que le log atteint `HikariPool` / `Liquibase` / `Connection refused` / `jdbc` / un log applicatif tardif → **le wiring est OK** ; un échec après = env local (non bloquant). Succès total = `Started <App>Application in Ns` (accounting-backend ~90 s avec devbox up).
- **Ne pas laisser tourner** : `pkill -f bootRun` après le verdict (`illegal byte sequence` de pkill bénin).

---

## § /end AVEC MR — VÉRIF PIPELINE

Quand `/end` est lancé **avec une MR**, avant de clore : **invoquer le skill `malt-pipeline-followup`** (source de vérité unique du suivi pipeline — lookup statut, pipelines parent-child, diagnostic + fix + repush, intégration Sonar, conflits de rebase, boucle d'attente, heures calmes) et le suivre jusqu'à pipeline **verte citée**, ou jusqu'à avoir explicitement demandé les erreurs Sonar à l'utilisateur (exception « Sonar illisible »). Ne clore le `/end` qu'à cette condition remplie.

---

## § TRAVAIL DÉCOUVERT EN COURS DE ROUTE

Un workflow reste **focalisé sur SON périmètre**. S'il découvre du travail annexe (bug hors scope, dette, champ à revoir, question de cadrage), il **ne l'implémente pas en douce** et ne l'enfouit pas dans son commit :

- **Créer un ticket JIRA dédié** (skill `/jira`) **sous le MÊME parapluie** (la User Story / umbrella parente, ou l'EPIC), pour que l'**orchestrateur de plan le capte à son RESCAN des enfants de l'umbrella**. Poser les liens de dépendance pertinents (`is blocked by`). **Label JIRA de squad obligatoire à la création** (skill `malt-squad-conventions`). **NE PAS assigner** le ticket à la création — l'assignation à `stephen.begot` n'a lieu qu'au démarrage du dev qui l'implémentera.
- **CHOISIR LE TYPE correctement** : travail de **recherche / investigation / cadrage** → **SPIKE**, destiné à `/plan` (sous-plan récursif). Fix d'implémentation clair et borné → ticket d'implémentation → `/dev`. Rédiger la consigne dans le **champ "Prompt" (`customfield_11956`)** (jamais dans la description, qui reste métier et lisible), en indiquant explicitement `lance /plan` ou `lance /dev`.
- **Signaler à l'orchestrateur** : en mode orchestré, mentionner le(s) ticket(s) créé(s) dans le `detail` du prochain `report` (et dans le livrable final). Ne jamais élargir silencieusement le périmètre de son propre ticket.
- **Ne PAS orchestrer soi-même** ces tickets depuis un `/dev`/`/hotfix`/`/plan` : on crée et signale ; c'est **`/orchestrator` (l'orchestrateur unique)** qui les capte à son RESCAN de l'umbrella, les intègre au DAG et les lance. Un `/plan` enfant qui découvre du travail crée les tickets sous l'umbrella (avec liens) et les laisse à l'orchestrateur — il ne les lance jamais lui-même.

---

## § LIVRABLE FINAL

En fin de workflow d'implémentation (`/dev`, `/hotfix`), retourner ce tableau :

| | |
|---|---|
| **JIRA** | lien vers le ticket |
| **Statut JIRA** | statut courant — doit être **"To Validate"** en fin (sinon expliquer pourquoi) |
| **MR** | lien vers la MR |
| **`/end`** | ✅ / ❌ |
| **Obsidian** | ✅ / ❌ / N/A — nouvelles specs/savoir capturés (`/obsidian` capture) ; N/A si rien de nouveau |
| **Tradeoffs** | liste des arbitrages **non différenciants** tranchés seul (cf. § DÉCISIONS D'ARCHI & TRADEOFFS) + rappel des décisions d'archi **déjà validées** par l'utilisateur en amont. Une ligne chacune, avec la raison. **Un tradeoff différenciant ou un choix d'archi qui apparaîtrait ici sans avoir été validé AVANT = violation de la règle d'escalade.** **Aucun** si rien à signaler. |
| **Résumé** | synthèse du travail |

Le point **Tradeoffs** est OBLIGATOIRE : lister explicitement toute décision non triviale prise sans accord de l'utilisateur, pour qu'il puisse la contester en review.
