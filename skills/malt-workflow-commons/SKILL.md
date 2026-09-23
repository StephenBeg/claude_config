---
name: malt-workflow-commons
description: Regles communes a /dev, /plan, /hotfix : questions a choix, escalade des decisions d'archi, acces JIRA, creation de ticket JIRA (statut Ready obligatoire), prefixes de header CMUX, verification des sources contre le reel, boucles de controle, smoke-run local, /end avec MR, travail decouvert, livrable final. A invoquer en PREMIER dans ces trois workflows.
---

# Workflow commons — /dev · /plan · /hotfix

Bloc de règles **partagées** par les trois workflows. Source de vérité UNIQUE : ne jamais recopier ces sections dans une commande — la commande invoque ce skill et renvoie à la section par son nom. Chaque commande **invoque ce skill en premier**, puis suit ses étapes propres.

Toutes les sections sont des **RÈGLES ABSOLUES**. Une commande peut n'utiliser qu'un sous-ensemble (ex : `/plan` n'a ni smoke-run ni MR ; `/orchestrator` est le seul à porter `[ORCH]` en continu — `/plan` planifie puis passe le relais et ne supervise rien).

---

## § QUESTIONS À CHOIX DE RÉPONSES

**La forme d'une question est définie par le skill `asking-the-user` — le charger AVANT de rédiger, il est la source de vérité unique.** En résumé exécutable : le fait en 1 à 3 phrases avec les **vrais noms** du domaine et un chiffre mesuré, la question en une phrase, 2 à 4 options d'une ligne, une reco. Plafond dur 150 mots. Pas de mise en situation, pas d'analogie, pas de paragraphe « pourquoi je ne peux pas trancher seul ».

Ce qui reste porté ici, propre aux workflows :

- **Un libellé d'option = UN seul périmètre.** L'utilisateur répond au libellé, pas à la description. « A + B » = deux options. Une option qui élargit le périmètre du ticket le dit dans son libellé.
- **Recommandation en 1re position**, suffixée `(Recommended)`, mais **ne jamais trancher à sa place**.
- **Pas de caveman** pour l'énoncé ni pour les libellés et descriptions d'options : prose normale. Caveman reste actif pour le reste du tour.
- **Onglet CMUX → `[ASK]`** pendant l'attente (§ PRÉFIXES DE HEADER CMUX).
- **Ne jamais avancer « en attendant »** sur une branche qui présume la réponse : un choix d'archi non validé bloque, il ne se pré-implémente pas.
- **Ne jamais relayer une question qu'une autre surface est déjà en train de poser** : le double-ask produit deux réponses contradictoires, et c'est la réponse obtenue en direct par la surface qui fait foi.
- Le point **Tradeoffs** du § LIVRABLE FINAL ne liste que les choix **non différenciants** tranchés seul + rappel des décisions **déjà validées**. Un tradeoff différenciant qui y apparaîtrait sans validation amont = violation.

---

## § DÉCISIONS D'ARCHI & TRADEOFFS — ESCALADE OBLIGATOIRE (jamais décider seul)

**Décider seul d'une archi ou d'un tradeoff, puis le révéler dans le livrable, est INTERDIT.** Claude ne fait **AUCUN** choix d'architecture de sa propre initiative, et **escalade tout tradeoff différenciant AVANT de coder**, pas après.

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

## § CRÉATION DE TICKET JIRA — CHECKLIST

Toute création de ticket par un workflow — `/plan` (User Story parapluie, SPIKE, tâches), `/hotfix` (ticket bug), `/dev` (ticket manquant), § TRAVAIL DÉCOUVERT — suit cette checklist. **Source de vérité UNIQUE** : les commandes y renvoient par le nom de section, elles ne la recopient pas. Mécanique d'appel = skill `/jira` (MCP sinon REST, cf. § ACCÈS JIRA).

1. **Parent** — champ `parent` posé (EPIC → Story → Task/Sub-task). EPIC jamais devinée : la demander (§ QUESTIONS À CHOIX).
2. **Titre + description en ANGLAIS**, point de vue métier, lisibles par un non-technique. La description N'EST PAS le prompt.
3. **Champ `Prompt` (`customfield_11956`) en FRANÇAIS** = consigne d'implémentation (ADF), avec `DEPENDS_ON:` et le mode de lancement (`lance /dev` ou `lance /plan`).
4. **Label de squad dès la création** (skill `malt-squad-conventions`).
5. **Liens `is blocked by`** pour chaque arête du DAG.
6. **NE PAS assigner à la création** — l'assignation à `stephen.begot` a lieu au passage `In Progress` par le dev qui implémente.
7. **STATUT → `Ready` IMMÉDIATEMENT APRÈS LA CRÉATION — RÈGLE ABSOLUE.** Un `POST /issue` naît en **`Selected for Development`** (statut initial du workflow JIRA — vérifié le 2026-09-09 sur BILL-3587 et BILL-3590 : aucune transition de statut dans leur changelog), et **ce statut n'apparaît pas sur les boards de la squad** : le ticket existe mais reste invisible, donc jamais pris. **La création n'est TERMINÉE qu'une fois le ticket passé en `Ready`.**
   - **Aucun statut `To Do` / `Open` n'existe** dans ce workflow — piège : il y a une *transition* nommée `To Do`, mais elle mène à `Scoped`, qui n'est pas `Ready`.
   - **Exception unique** : le SPIKE de planification de `/plan`, qui part directement en `In Progress` (déjà visible sur le board).
   - Transition = plomberie mécanique → **déléguer en `haiku`** (§ ACCÈS JIRA).

```
# `Ready` = transition 191 sur BILL — résoudre par NOM (l'id varie par projet/type d'issue)
TID=$(curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET>/transitions" \
  | python3 -c 'import sys,json;[print(t["id"]) for t in json.load(sys.stdin)["transitions"] if t["name"].lower()=="ready"]')
curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -H "Content-Type: application/json" \
  -X POST "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET>/transitions" -d "{\"transition\":{\"id\":\"$TID\"}}"   # 204
```

8. **VÉRIFIER, jamais déclarer** — relire le statut (`GET /issue/<TICKET>?fields=status`) et **citer `Ready`**. Un `POST /transitions` en 4xx ou un statut resté `Selected for Development` = ticket hors board : la création n'est pas faite, ne pas passer à la suite.

**Statuts du workflow** (projet BILL, vérifié 2026-09-09) : `Selected for Development` · `Scoped` · `Ready` · `In Progress` · `Review` · `To Validate` · `To deploy` · `Blocked` · `Done` · `Closed / Not done`.

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
- **Fin de tour** → **BLOQUÉE** tant qu'une MR mergée n'a pas son `/end` écrit dans le log du jour (vérifié dans le fichier, pas déclaré), tant qu'un push du tour n'a pas son **bloc de clôture** dans la réponse, tant que le ticket n'est pas en `To Validate`, et tant que le **LIVRABLE FINAL** (avec Tradeoffs) n'est pas rendu.
- **Étapes du workflow REFUSÉES par un gate si sautées** (CLAUDE.md § GATES DÉTERMINISTES — table complète) : 1er push sans verdict juge `OK` / sans tests verts / sans smoke-run des services touchés · commit sans test dans l'index · MR sans reviewer/titre/label · merge sans `Approved` frais + pipeline verte + rebase `skip_ci` + `--squash` · écriture JIRA/GitLab/Notion en français · édition d'un fichier sans le skill de son domaine · réveil programmé en heures calmes. Le verdict du juge est **périmé par tout nouveau commit**.

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
- **`[JUGE]`** : posé par `/dev`/`/hotfix`/`/plan` (jamais `/orchestrator`) à chaque round de la LOOP JUGE (skill `malt-judge-loop`), tant que le sous-agent `judge` tourne. Un nouveau round = repasser par `[JUGE]` à chaque fois (juge frais).

---

## § DISCIPLINE DE COMMENTAIRE — CODE PRODUIT (RÈGLE ABSOLUE)

**Défaut = AUCUN commentaire.** Le code nommé correctement, le test, et le ticket JIRA portent l'explication. Un commentaire est une **exception justifiée**, jamais un réflexe de fin d'implémentation. Un LLM qui vient de raisonner longuement a une pulsion forte de déverser ce raisonnement en KDoc : c'est exactement ce qu'il ne faut pas faire. Le raisonnement va dans la **description de MR** et dans le **commentaire JIRA de tradeoffs**, pas dans le fichier source.

**Plafond dur : 1 à 2 lignes.** Un commentaire de 3 lignes ou plus est un défaut, sans exception d'« ampleur du sujet ». Pas de titres markdown (`## Why this exists`), pas de listes à puces, pas de paragraphes.

**Un commentaire ne survit que s'il porte un fait qu'on ne peut PAS lire dans le code** et dont l'ignorance ferait commettre une erreur :
- un invariant ou un piège non évident (« `exists` avale un refus en `false` — utiliser `isPresent` ») ;
- une contrainte externe que le code ne peut pas exprimer (quirk NetSuite, comportement legacy, ordre/concurrence, unité ou scale) ;
- un « pourquoi PAS la solution évidente » qui empêche une modif plausible mais fausse ;
- `TODO` / `FIXME`, message de `@Deprecated` ;
- les **directives outillage**, jamais touchées : `ktlint-disable`, `noinspection`, `language=SQL`, `eslint-disable*`, `@ts-ignore`, `prettier-ignore`, en-têtes de licence.

**Interdits, à supprimer à vue :**
- toute reformulation du nom de la classe / méthode / propriété / test ;
- toute **explication métier** — elle vit dans JIRA, pas dans le code ;
- tout **récit de ticket** : « BILL-1234 — pourquoi on a fait ça », historique, « avant ce ticket… », « used to… », verdicts de revue, justifications de choix passés ;
- toute **énumération d'appelants / d'émetteurs / de seams**, et tout renvoi au KDoc d'une autre classe ;
- `NOTE:` / `IMPORTANT:` / « Companion to… » / essais de rationalisation ;
- `@param` / `@return` / `@throws` qui ne font que répéter le nom ou le type ;
- commentaire de fin de ligne qui paraphrase la ligne ;
- `// given` / `// when` / `// then` et « ce test vérifie que… » quand le test se lit déjà ainsi ;
- code commenté.

**Raccourcir ≠ résumer.** On ne condense pas le paragraphe : on garde le SEUL fait non lisible dans le code et on jette le reste. S'il n'y en a aucun, on supprime tout le bloc.

**Où ça mord dans les workflows :**
- **Champ `Prompt` d'un ticket** (`/plan`, `/hotfix`) : ne jamais y demander « documenter le raisonnement en commentaire ». Le contexte du fix va dans le `Prompt`, pas en consigne d'écriture de KDoc.
- **Sous-agent d'implémentation** (`malt-orchestration`) : la consigne de délégation rappelle ce plafond explicitement, sinon le sous-agent produit le déversement.
- **Juge** (`malt-judge-loop`) : un diff qui ajoute un commentaire de ≥ 3 lignes, ou un commentaire qui répète le code / raconte le ticket, est un **GAP de scope** à remonter — au même titre qu'un effet de bord hors périmètre.
- **Revue de son propre diff avant push** : relire les `+` de commentaire et supprimer tout ce qui ne passe pas la barre ci-dessus.

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

1. **Preuve, jamais affirmation.** Toute conclusion « c'est vert / c'est fixé / ça boote » DOIT citer une **sortie réelle** : output de test, exit code de build, log `Started …Application(Kt)? in`, ligne Sonar `règle fichier:ligne`, statut de pipeline, état JIRA. Jamais « les tests passent » sans la sortie. (superpowers:verification-before-completion.)
2. **`/goal` — ligne d'arrivée mesurable et bornée.** Pour la vérif pré-livraison, poser un `/goal` explicite plutôt que juger à l'œil : un évaluateur re-teste la condition à chaque tour, l'agent boucle jusqu'à ce qu'elle tienne. Conditions typiques : 0 test en échec (modules touchés) ; service(s) touché(s) qui bootent ; 0 violation Sonar new-code + coverage ≥ 80 % ; scope = besoin du ticket, rien de plus. Pour `/orchestrator` : **DAG entièrement drainé** (toutes tâches `MERGED`, tous spikes-plan `PLANNED` avec leur sous-arbre `MERGED`, zéro orphelin au dernier RESCAN de l'umbrella). (`/plan`, lui, s'arrête au hand-off vers `/orchestrator` — il ne draine rien.) **Borne dure : ~6 tours max** — atteinte sans vert → surfacer (`[BLOCK]`), jamais d'acharnement.
3. **LOOP JUGE en CONTEXTE FRAIS — solo comme orchestré.** Le juge ne tourne JAMAIS dans le contexte qui a écrit le code/le plan (biais). C'est un **sous-agent `judge`** (`.claude/agents/judge.md`, `opus`, read-only) lancé par la surface elle-même au checkpoint, **un juge NEUF à chaque round**, rebouclé jusqu'à ce qu'un juge rende `OK` (borne dure par checkpoint, détail skill `malt-judge-loop` — 2 rounds pour `/dev`/`/hotfix`, 4 pour `/plan` → escalade `[ASK]`). Chaque juge écrit son **compte rendu** dans le fichier de la surface (`REPORT_FILE`) — trace auditable. Protocole complet : skill `malt-judge-loop`. Il n'existe **plus de surface `/judge`** ni d'inbox juge ; le subagent `reviewer` est remplacé par le juge à ces checkpoints.
   Dans les deux cas, le contrôleur ne voit QUE le diff (ou le plan) + la consigne (`Prompt`) + les critères, et cherche à **réfuter** : requirement non couvert, cas limite sans test, effet de bord hors scope, bug introduit (pour un plan : domaine/tâche/dépendance/contrat oublié). Retourne des **GAPS**, pas des préférences de style. Traiter correctness/scope ; **ne pas sur-corriger** le reste. Alternative outillée : skill `/code-review`. (Exploration : subagent **`explorer`** ; smoke-run : **`smoke-runner`**.)
   Un round `NEEDS_WORK` ne se traite jamais à moitié : le juge est déjà exhaustif en un seul passage, donc chaque GAP est fermé avec une **preuve rejouée** avant resoumission (skill `malt-judge-loop`) — sinon le round suivant retrouve du travail bâclé, pas de nouveaux problèmes.
4. **`/loop` — attente/polling auto-cadencé (option).** Pour surveiller un état externe qui évolue seul (pipeline CI, attente d'approbation `Approved`, `await` d'un DAG), `/loop` est l'alternative auto-cadencée aux réveils manuels. **Ne remplace PAS** la boucle `until` en background ni `ScheduleWakeup` : mécanismes équivalents. **L'outil `Monitor` reste INTERDIT** (un accord par événement bloque l'utilisateur). Intervalle calé sur la vitesse réelle de l'état surveillé (pipeline ~8 min → un check ~480 s, pas 8 checks de 60 s). **HEURES CALMES 20h–7h (CLAUDE.md) : ne JAMAIS programmer `/loop`/`ScheduleWakeup`/boucle `until` de suivi dans cette plage — vérifier `date +%H%M` avant, STOPPER NET si ∈ [2000,0659], consigner l'état, relance manuelle le matin.** Mécanique exacte de la boucle `until` (y compris le piège du process détaché qui ne notifie jamais) et son extension à l'attente d'`Approved` → skill `malt-pipeline-followup` § 3, seule source de vérité.
5. **Explore → Plan → Code.** Séparer compréhension et exécution pour ne pas résoudre le mauvais problème. Utile quand l'approche est incertaine / multi-fichiers / code peu connu. **À sauter** si le diff tient en une phrase. Dans ces workflows, l'explore sert surtout à **vérifier le plan mâché (`Prompt`) contre le code réel** (§ VÉRIFICATION DES SOURCES CONTRE LE RÉEL), pas à tout re-découvrir.

---

## § SMOKE-RUN LOCAL (services modifiés — /dev · /hotfix)

Les tests verts ne prouvent PAS que le service boote : contexte Spring cassé (bean manquant/ambigu, `@Bean` dépendance non câblée, `NoResourceFoundException` 404 au boot, FF absent, migration Liquibase invalide, conflit de scan infra) ne sort qu'au démarrage. Pour **chaque service applicatif dont une ligne a été touchée** (projets `*-application` / porteurs d'un `bootRun`, ex `netsuite-connector`, `accounting-backend`) :

- **Déterminer les services impactés** : mapper les fichiers du diff (`git diff --name-only origin/master...`) vers leur projet Gradle applicatif. Ne lancer QUE ceux réellement touchés.
- **Déléguer au subagent `smoke-runner`** (`haiku`) qui encapsule la procédure : lancer `./gradlew :<application-project>:bootRun` en `run_in_background: true`, boucle `until` sur `Started .*Application(Kt)? in` vs `APPLICATION FAILED TO START`/`BUILD FAILED`/`BeanCreationException`/`UnsatisfiedDependency`/`NoResourceFoundException`, **jamais `Monitor`**, timeout ~5 min, `pkill -f bootRun` après verdict. Il retourne une **CONCLUSION** : `BOOTED_OK` ou `BOOT_FAILED` + la cause racine extraite du log (pas le dump).
- **Si `BOOT_FAILED` par la faute du diff** → **bug à corriger** (systematic-debugging), fix + re-smoke-run jusqu'au boot vert. Ne pas pousser un service qui ne boote pas.
- **Si le boot échoue pour une raison d'ENVIRONNEMENT local** (devbox DB down, secret manquant, dépendance externe indispo — pas causé par le diff) → **ne pas bloquer** : consigner la raison dans le livrable (Tradeoffs), se rabattre sur la vérif pipeline du `/end`. Distinguer clairement « cassé par mon code » (bloquant) de « env local indispo » (non bloquant).

**TIPS bootRun local (éprouvés sur `accounting-backend`) :**
- **Nom de projet Gradle = basename du module, PAS le chemin.** `accounting-backend` vit dans `erp/accounting-backend` mais la task est `:accounting-backend:bootRun` — **jamais** `:erp:accounting-backend`.
- **Toujours le profil `dev`** : `./gradlew :<module>:bootRun --args='--spring.profiles.active=dev'`.
- **Le crash de WIRING Spring sort AVANT toute connexion DB/rabbit**, pendant le refresh du contexte → un boot cassé par le code se détecte **même sans devbox up**. Signal le plus rentable à guetter.
- **Frontière wiring vs env** : dès que le log atteint `HikariPool` / `Liquibase` / `Connection refused` / `jdbc` / un log applicatif tardif → **le wiring est OK** ; un échec après = env local (non bloquant). Succès total = `Started <App>Application[Kt] in Ns` (les apps Kotlin loguent `…ApplicationKt`, un motif sans `Kt` rate le succès et fait conclure à tort à un boot incomplet) (accounting-backend ~90 s avec devbox up).
- **Ne pas laisser tourner** : `pkill -f bootRun` après le verdict (`illegal byte sequence` de pkill bénin).

---

## § /end AVEC MR — VÉRIF PIPELINE

Quand `/end` est lancé **avec une MR**, avant de clore : **invoquer le skill `malt-pipeline-followup`** (source de vérité unique du suivi pipeline — lookup statut, pipelines parent-child, diagnostic + fix + repush, intégration Sonar, conflits de rebase, boucle d'attente, heures calmes) et le suivre jusqu'à pipeline **verte citée**, ou jusqu'à avoir explicitement demandé les erreurs Sonar à l'utilisateur (exception « Sonar illisible »). Ne clore le `/end` qu'à cette condition remplie.

---

## § TRAVAIL DÉCOUVERT EN COURS DE ROUTE

Un workflow reste **focalisé sur SON périmètre**. S'il découvre du travail annexe (bug hors scope, dette, champ à revoir, question de cadrage), il **ne l'implémente pas en douce** et ne l'enfouit pas dans son commit :

- **Créer un ticket JIRA dédié** (skill `/jira`, checklist § CRÉATION DE TICKET JIRA — **statut `Ready` compris**) **sous le MÊME parapluie** (la User Story / umbrella parente, ou l'EPIC), pour que l'**orchestrateur de plan le capte à son RESCAN des enfants de l'umbrella**. Poser les liens de dépendance pertinents (`is blocked by`). **Label JIRA de squad obligatoire à la création** (skill `malt-squad-conventions`). **NE PAS assigner** le ticket à la création — l'assignation à `stephen.begot` n'a lieu qu'au démarrage du dev qui l'implémentera.
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
