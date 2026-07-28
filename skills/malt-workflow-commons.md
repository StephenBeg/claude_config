---
name: malt-workflow-commons
description: Règles communes aux workflows /dev /plan /hotfix (source de vérité unique, dédupliquée). Contient — questions à choix de réponses, accès JIRA MCP/fallback, préfixes de header CMUX, vérification des sources contre le réel, vérification & boucles de contrôle, smoke-run local, /end avec MR (vérif pipeline), travail découvert en cours de route, livrable final. Invoquer en PREMIER dans /dev, /plan, /hotfix.
---

# Workflow commons — /dev · /plan · /hotfix

Bloc de règles **partagées** par les trois workflows. Source de vérité UNIQUE : ne jamais recopier ces sections dans une commande — la commande invoque ce skill et renvoie à la section par son nom. Chaque commande **invoque ce skill en premier**, puis suit ses étapes propres.

Toutes les sections sont des **RÈGLES ABSOLUES**. Une commande peut n'utiliser qu'un sous-ensemble (ex : `/plan` n'a ni smoke-run ni MR ; `/plan` est le seul à porter `[MAIN]` en continu).

---

## § QUESTIONS À CHOIX DE RÉPONSES

Quand un workflow pose une question à l'utilisateur **avec des choix de réponses** (options prédéfinies, arbitrage, `AskUserQuestion`) :

- **Explication détaillée AVANT les choix — obligatoire.** Avant de présenter les options, exposer le problème **point par point** : contexte, ce qui est en jeu, pourquoi la décision se pose, et pour **chaque option** ses implications / tradeoffs. But : que l'utilisateur comprenne réellement l'issue et les solutions, pas qu'il tranche à l'aveugle.
- **INTERDICTION D'UTILISER CAVEMAN dans ce cas précis.** L'explication du problème ET les libellés/descriptions des choix sont rédigés en **prose normale, complète et claire**. Caveman reste actif pour tout le reste de la session — on ne le suspend QUE pour la formulation de la question et de ses options.

---

## § ACCÈS JIRA — MCP ou fallback API REST

Toute interaction JIRA d'un workflow (lecture ticket, création, transitions de statut, commentaires, liens de dépendance) passe par le skill `/jira`. **Si le MCP Atlassian n'est PAS connecté** (auth échoue / tools `jira_*` indisponibles) → **NE PAS bloquer** : utiliser le **fallback API REST v3** documenté dans le skill `/jira` (curl + Basic auth, env `.zshrc`). Le skill `/jira` gère les deux : MCP si dispo, sinon REST. Vérifier au besoin :

```
curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/myself"   # → 200
```

---

## § PRÉFIXES DE HEADER CMUX — TABLE UNIFIÉE

Mettre à jour le titre de l'onglet cmux **de Claude** (jamais celui de l'utilisateur ; cible via `CMUX_SURFACE_ID`) **dès qu'un changement d'état survient** :

```
~/.claude/scripts/cmux-tab.sh phase <PREFIX> "<résumé 3-4 mots>"
```

| Préfixe | Signification |
|---|---|
| `[MAIN]` | Processus qui en **orchestre d'autres** — reste en `[MAIN]` en permanence (orchestrateur de plan / GO IMPLEMENTATION). |
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
- Le header peut **revenir en arrière** : ex `[MR (1234)]` → `[PIPE (1234)]` (fix demandé qui relance la pipeline) → `[MR (1234)]` ; ou `[MR (1234)]` → `[IMPL]` (request changes) → `[PIPE (1234)]` → `[MR (1234)]`.
- **Le résumé décrit CE QU'ON FAIT — jamais "impl du ticket X".** 3-4 mots sur le contenu réel, pas le mot "impl" ni le numéro de ticket seul. Le résumé reste **identique** entre phases ; seul le préfixe change.
  - ❌ `[IMPL] BILL-2607 impl`
  - ✅ `[IMPL] TRY PAR EVENTID`
- **Spécificités par workflow** : `[MAIN]` = un `/plan` **pendant le GO IMPLEMENTATION** (il supervise le DAG / les sous-plans). Un `/dev`/`/hotfix` n'utilise `[MAIN]` que s'il orchestre lui-même.

---

## § VÉRIFICATION DES SOURCES CONTRE LE RÉEL

La mémoire (notes Obsidian, mémoire persistante, souvenirs de chantiers passés) est un **point de départ, jamais une vérité**. Elle est **souvent périmée ou fausse** (drift). Avant d'ancrer une décision (plan, diagnostic, implémentation) sur un fait mémorisé, **le confirmer contre le réel** :

- **Code** : lire le fichier/symbole réel **sur `master` fraîchement synchronisé**, pas le souvenir de sa localisation/signature. Toute citation d'un sous-agent = `path:line` vu dans le code courant, jamais de mémoire.
- **Runtime / prod** : pour tout fait sur le comportement en prod (état d'un FF, volumétrie, erreurs, chemin réellement emprunté) → **vérifier via Datadog** (`/datadog` : logs/traces/métriques) ou **Sentry** (`/sentry-analyzer`) plutôt que supposer.
- **JIRA / FF / config** : état d'un ticket, d'un feature flag, d'une config → lire la source vivante (JIRA, fichiers ff4j, app-config), pas la mémoire.
- **Drift** : si le réel contredit une note Obsidian → **corriger la note** (`/obsidian` capture) dans la foulée.
- Chaque affirmation structurante doit être **traçable à une source réelle vérifiée cette session** (path:line, requête Datadog, ticket JIRA). Une hypothèse non vérifiée est **marquée explicitement** comme telle, jamais présentée comme un fait.

---

## § VÉRIFICATION & BOUCLES DE CONTRÔLE

Principe Anthropic : **donner à l'agent un moyen de vérifier son propre travail** — un signal pass/fail qu'il lit et sur lequel il itère seul, au lieu que l'humain soit la boucle de vérification. Cinq leviers :

1. **Preuve, jamais affirmation.** Toute conclusion « c'est vert / c'est fixé / ça boote » DOIT citer une **sortie réelle** : output de test, exit code de build, log `Started …Application in`, ligne Sonar `règle fichier:ligne`, statut de pipeline, état JIRA. Jamais « les tests passent » sans la sortie. (superpowers:verification-before-completion.)
2. **`/goal` — ligne d'arrivée mesurable et bornée.** Pour la vérif pré-livraison, poser un `/goal` explicite plutôt que juger à l'œil : un évaluateur re-teste la condition à chaque tour, l'agent boucle jusqu'à ce qu'elle tienne. Conditions typiques : 0 test en échec (modules touchés) ; service(s) touché(s) qui bootent ; 0 violation Sonar new-code + coverage ≥ 80 % ; scope = besoin du ticket, rien de plus. Pour un `/plan` : **DAG entièrement drainé** (toutes tâches `MERGED`, tous sous-plans `DONE`, zéro orphelin au RESCAN). **Borne dure : ~6 tours max** — atteinte sans vert → surfacer (`[BLOCK]`), jamais d'acharnement.
3. **Revue adverse en CONTEXTE FRAIS (subagent `reviewer`).** Le juge ne tourne JAMAIS dans le contexte qui a écrit le code/le plan (biais). Déléguer au subagent **`reviewer`** (`.claude/agents/`, `opus`) qui ne voit QUE le diff (ou le plan) + la consigne (`Prompt`) + les critères, et cherche à **réfuter** : requirement non couvert, cas limite sans test, effet de bord hors scope, bug introduit (pour un plan : domaine/tâche/dépendance/contrat oublié). Retourne des **GAPS**, pas des préférences de style. Traiter correctness/scope ; **ne pas sur-corriger** le reste. Alternative outillée : skill `/code-review`. (Exploration : subagent **`explorer`** ; smoke-run : **`smoke-runner`**.)
4. **`/loop` — attente/polling auto-cadencé (option).** Pour surveiller un état externe qui évolue seul (pipeline CI, attente d'approbation `Approved`, `await` d'un DAG), `/loop` est l'alternative auto-cadencée aux réveils manuels. **Ne remplace PAS** la boucle `until` en background ni `ScheduleWakeup` : mécanismes équivalents. **L'outil `Monitor` reste INTERDIT** (un accord par événement bloque l'utilisateur). Intervalle calé sur la vitesse réelle de l'état surveillé (pipeline ~8 min → un check ~480 s, pas 8 checks de 60 s). **HEURES CALMES 20h–7h (CLAUDE.md) : ne JAMAIS programmer `/loop`/`ScheduleWakeup`/boucle `until` de suivi dans cette plage — vérifier `date +%H%M` avant, STOPPER NET si ∈ [2000,0659], consigner l'état, relance manuelle le matin.**
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

Quand `/end` est lancé **avec une MR**, avant de clore :

1. **Lookup pipeline** de la MR (`glab ci status` / `glab_mr_view` / `glab_ci_list`) → vérifier **verte**.
2. **Si rouge** : lire logs du job en échec (`glab_ci_trace` / `glab_ci_artifact`), **diagnostiquer et fixer automatiquement**, commit + **repush** sur la branche de la MR (jamais master), re-vérifier. Boucler jusqu'au vert.
   - **Pipeline parent-child (monorepo Malt)** : `glab ci status` / `glab ci get` ne montrent que les jobs du parent. Le vrai job en échec est souvent dans la **child pipeline** (job-factory). La récupérer via `glab api "projects/:id/pipelines/<PARENT_ID>/bridges"` → `downstream_pipeline.id`, puis `glab api "projects/:id/pipelines/<CHILD_ID>/jobs?per_page=100"` pour trouver le job `failed`.
3. **Job Sonar en échec** : NE PAS deviner depuis le log CI (il ne donne que `QUALITY GATE FAILED` + lien dashboard). **Utiliser la commande `/sonar`** pour interroger l'API SonarQube et récupérer les conditions du gate en échec + les issues exactes (règle, fichier:ligne, message), puis fixer précisément. **Exception « Sonar illisible »** : si l'API Sonar est injoignable / token invalide et que le log reste illisible → **demander les erreurs Sonar à l'utilisateur**, puis fixer.
4. Ne clore le `/end` qu'une fois pipeline verte, ou après avoir demandé les erreurs Sonar.

**ATTENTE DE PIPELINE — OUTIL `Monitor` INTERDIT.** Ne JAMAIS utiliser `Monitor` pour surveiller une pipeline (chaque événement déclenche une demande d'accord qui bloque l'utilisateur). Pour attendre l'état terminal, utiliser un `Bash` en **`run_in_background: true`** avec une boucle `until` qui sort quand le statut vaut `success|failed|canceled` → une seule notification à la fin. Exemple :

```
until s=$(glab api "projects/:id/pipelines/<PID>" | python3 -c "import sys,json;print(json.load(sys.stdin)['status'])") \
  && [ "$s" = success -o "$s" = failed -o "$s" = canceled ]; do sleep 30; done; echo "DONE=$s"
```

**HEURES CALMES 20h–7h (CLAUDE.md) :** ne pas lancer/relancer cette boucle entre 20h et 7h — à sa sortie elle ré-invoque Claude. Vérifier `date +%H%M` ; si ∈ [2000,0659] → STOPPER NET, consigner l'état, relance manuelle le matin.

---

## § TRAVAIL DÉCOUVERT EN COURS DE ROUTE

Un workflow reste **focalisé sur SON périmètre**. S'il découvre du travail annexe (bug hors scope, dette, champ à revoir, question de cadrage), il **ne l'implémente pas en douce** et ne l'enfouit pas dans son commit :

- **Créer un ticket JIRA dédié** (skill `/jira`) **sous le MÊME parapluie** (la User Story / umbrella parente, ou l'EPIC), pour que l'**orchestrateur de plan le capte à son RESCAN des enfants de l'umbrella**. Poser les liens de dépendance pertinents (`is blocked by`). **Label `Accounting/Bookkeeping` OBLIGATOIRE à la création** (`"labels":["Accounting/Bookkeeping"]`). **NE PAS assigner** le ticket à la création — l'assignation à `stephen.begot` n'a lieu qu'au démarrage du dev qui l'implémentera.
- **CHOISIR LE TYPE correctement** : travail de **recherche / investigation / cadrage** → **SPIKE**, destiné à `/plan` (sous-plan récursif). Fix d'implémentation clair et borné → ticket d'implémentation → `/dev`. Rédiger la consigne dans le **champ "Prompt" (`customfield_11956`)** (jamais dans la description, qui reste métier et lisible), en indiquant explicitement `lance /plan` ou `lance /dev`.
- **Signaler à l'orchestrateur** : en mode orchestré, mentionner le(s) ticket(s) créé(s) dans le `detail` du prochain `report` (et dans le livrable final). Ne jamais élargir silencieusement le périmètre de son propre ticket.
- **Ne PAS orchestrer soi-même** ces tickets depuis un `/dev`/`/hotfix` : on crée et signale ; c'est l'orchestrateur de plan (ou le SPIKE-plan concerné) qui les intègre au DAG et les lance.

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
| **Tradeoffs** | liste des arbitrages pris **automatiquement** sans validation explicite de l'utilisateur (design/scope/implémentation décidés seul). Une ligne par tradeoff, avec la raison. **Aucun** si tout a été validé en amont. |
| **Résumé** | synthèse du travail |

Le point **Tradeoffs** est OBLIGATOIRE : lister explicitement toute décision non triviale prise sans accord de l'utilisateur, pour qu'il puisse la contester en review.
