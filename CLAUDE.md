# Instructions globales

## CAVEMAN — mode réponse (TOUJOURS ACTIF)

Niveau défaut **full** (`/caveman lite|full|ultra` ; « mode normal » désactive). Supprime articles, remplissage, politesses ; garde substance technique, termes exacts, blocs de code intacts. Pattern : `[chose] [action] [raison]. [étape suivante].`

**Prose normale obligatoire** (puis reprise caveman) : avertissement sécurité · confirmation d'action irréversible · séquence multi-étapes où la compression risque une mauvaise lecture · question posée à l'utilisateur (cf. skill `asking-the-user`).

## PRINCIPES

Direct, zéro blabla. Montrer le raisonnement, jamais d'hypothèse silencieuse. **Vérifier avant d'affirmer** (lire le code, lire les docs fournies). Pas de cleanup non demandé.

## COMMUNICATION AVEC L'UTILISATEUR — TROIS SKILLS OBLIGATOIRES

- **Je pose une question** (clarification, arbitrage, `AskUserQuestion`, « je te laisse trancher »), ou il répond « je n'ai rien compris » → charger `asking-the-user` AVANT de rédiger. Gabarit : le fait en 1 à 3 phrases avec les **vrais noms**, la question, 2 à 4 options d'une ligne, une reco. 150 mots max.
- **Je rédige un document lu par un humain** (RFC, Notion, description ou commentaire JIRA, description de MR, compte rendu, doc markdown) → charger `writing-for-humans` AVANT d'écrire. Conclusion en haut, uniquement le sujet demandé, cible non technique par défaut, zéro tic d'écriture IA.
- **J'écris quoi que ce soit d'autre** (commentaire de code, message de commit, réponse) → skill `claude-prose`, la barre permanente : clair, lisible, compréhensible, concis. Il porte aussi le plafond dur des commentaires de code (§ COMMENTAIRES DANS LE CODE).

## LANGUE DES ÉCRITURES EXTERNES — RÈGLE ABSOLUE

**Tout ce qui est écrit dans Notion, JIRA ou GitLab est en ANGLAIS** — titres, descriptions, commentaires, notes de statut, subjects de commit, notes de review, même une réponse d'une ligne. Contexte de travail en français → traduire avant d'écrire. La conversation avec l'utilisateur reste en français. Seule exception : le champ JIRA `Prompt` (`customfield_11956`), en français.

## WORKFLOWS — dispatcher

Choisir **avant toute action**. Signal : un numéro de ticket JIRA en entrée → `/dev` ; besoin large sans ticket → `/plan` ; bug signalé sans ticket → `/hotfix`. Le détail de chaque workflow vit dans sa commande ; ne pas le dupliquer ici.

- **`/plan`** — planificateur PUR : analyse, plan + DAG, tickets JIRA parallélisables, spike DONE. Ne spawn rien ; au GO il passe le relais à `/orchestrator`.
- **`/orchestrator`** — propriétaire UNIQUE du fan-out CMUX et du cycle de vie des tickets d'un chantier planifié. **Un seul par workspace.**
- **`/dev`** — un ticket JIRA implémenté de bout en bout (worktree → tests → MR → pipeline → statuts). Ne jamais merger la MR soi-même.
- **`/hotfix`** — diagnostic → cause racine → crée son ticket → implémente.
- **Le juge est un sous-agent MÉTIER, pas une surface — UN SEUL round, à UN SEUL checkpoint, juste avant la livraison** (`pre-mr` pour `/dev` — implémentation terminée, avant `glab mr create` ; `hotfix-verify` pour `/hotfix` ; `plan-gate` pour `/plan`). Pas de gate juge pré-impl, pas de boucle : `NEEDS_WORK` → fermer les GAPS avec preuve **puis continuer** (le push reste ouvert ; rapporter GAPS, corrections et reste ouvert dans la MR et les Tradeoffs). Jamais de round 2, jamais de GO à demander pour pousser. Il ne juge QUE le métier (besoin couvert, meilleure solution, pièges du domaine, cas de test métier) — **jamais** lint, style, commentaires, tests rouges, coverage ; **il ne lance ni build ni test**. Protocole : skill `malt-judge-loop`.

## ÉTAT DE WORKFLOW — OUTILLÉ, PAS DÉCLARATIF

Header CMUX, numéro de MR et `/end` vivent dans un état persistant (`~/claude-exchange-llm/_phase/<surface>.json`, écrit par `~/.claude/scripts/cmux-tab.sh`) piloté par des hooks déterministes — pas dans la mémoire du LLM.

- **Poser le sujet une fois** : `cmux-tab.sh topic "<3-4 mots>"` (survit aux phases et à la compaction). Puis `cmux-tab.sh phase <PREFIX>` avec le préfixe **NU** — le script pose les crochets et refuse un préfixe hors liste.
- **Automatique, ne pas refaire à la main** : `glab mr create` → `[MR (n)]` · `git push` → `[PIPE (n)]` + bloc de clôture · `git worktree add` → `[IMPL]` · `glab mr merge` → `[CLEAN]` · réponse de l'utilisateur → sortie de `[ASK]`/`[BLOCK]`/`[WAIT]`.
- **`/end` non sautable** : la fin de tour est bloquée tant qu'une MR mergée n'a pas son `/end` écrit dans le log du jour (vérifié dans le fichier). Il se fait **en dernier**, après merge.
- À la charge de la session : `[PLAN]`, `[ASK]`, `[BLOCK]`, `[WAIT]`, `[END]`, le sujet, et les retours arrière métier. Table complète : `malt-workflow-commons` § PRÉFIXES DE HEADER CMUX.

## GATES DÉTERMINISTES — CE QUE LE HARNESS REFUSE (pas moi)

Les règles ci-dessous ne sont plus seulement écrites : elles sont **exécutées par des hooks**. Un texte de CLAUDE.md ou de skill est advisory ; un gate refuse l'appel. Le message de refus porte la consigne **et** la sortie de secours — le lire plutôt que contourner.

| Gate | Refuse |
|---|---|
| `master-write` · `master-push` | écrire (Edit/Write **et Bash** : `sed -i`, redirection, `git apply/checkout/reset`) dans le repo principal quand il est sur `master` ; pousser depuis/vers `master` |
| `worktree-form` | `git worktree add` hors `~/worktrees/malt/` ou sans base explicite `origin/master` |
| `coauthor` | `Co-Authored-By` dans un message de commit (y compris en heredoc) |
| `coverage` | `git commit` qui ajoute du code source sans **aucun** fichier de test dans l'index |
| `pre-push` | **1er push** d'une branche sans exécution de tests verte observée, sans smoke-run des services applicatifs touchés (détectés par le diff) |
| `pre-mr` | `glab mr create` sans **passage** de juge (`OK` **ou** `NEEDS_WORK` — le gate exige que le dev ait été jugé, pas que le juge ait dit oui). Le juge est dû **une fois, implémentation terminée, avant la MR** — pas au push. Il est **asynchrone** : son lancement ne lève rien, sa conclusion si |
| `mr-create` | MR sans reviewer `@stephen.begot`, sans titre `[<préfixe>] Titre`, sans label |
| `rebase-skipci` · `mr-merge` | rebase d'API sans `skip_ci=true` ; merge sans `--squash --remove-source-branch`, sans rebase préalable, sans commentaire `Approved` **postérieur au dernier push réel**, pipeline non verte — un `skipped` de rebase `skip_ci` passe si une pipeline verte de la MR porte encore mes fichiers inchangés — **fail closed** : invérifiable = refusé |
| `end-gate` · `closing-block` · `jira-status` · `livrable` | **clore le tour** : MR mergée sans `/end` écrit dans le log du jour · push sans bloc de clôture dans la réponse · ticket pas en `To Validate` · pas de tableau LIVRABLE FINAL avec Tradeoffs |
| `tmp-ban` | tout chemin `/tmp`, `/private/tmp`, `/var/folders` (y compris le scratchpad proposé par le harness) — seule exception : `mktemp` consommé dans la même commande |
| `quiet-hours` | entre 20h00 et 07h00 : `ScheduleWakeup`, `CronCreate`, `/loop`, boucle `until` en background, réveil de surface, spawn d'`/orchestrator`. Un round de juge reste autorisé |
| `prod-db` | lire la base de prod hors `/hotfix` : `malt-sql.sh` sans `--env integ`, tunnel `pg-prod`/`mongo-prod*`, token Cloud SQL, skill `malt-prod-sql` |
| `external-lang` | écriture JIRA / GitLab / Notion contenant du français (exception : `customfield_11956`) |
| `skill-required` | éditer un `.vue`, un test, un contrat d'API, une migration, `erp/accounting*` sans avoir chargé le skill du domaine |
| `prose-required` *(warn)* | écrire du code sans le skill `claude-prose` — rappelle la barre (clair, lisible, concis ; commentaires 0 par défaut, plafond 1-2 lignes) |
| `preanalysis` *(warn)* | explorer le monorepo sans pré-analyse (skill `malt-accounting-domain` ou note Obsidian) |

**Portée — les gates de workflow ne valent QUE dans le monorepo Malt** (`~/Documents/projects/malt` et `~/worktrees/malt/*`) : `master-write`, `master-push`, `worktree-form`, `coverage`, `pre-push`, `pre-mr` — donc aussi le juge, qui n'est exigé que par `pre-mr`. Dans un repo perso (portfolio, side projects) ils se taisent : commit et push directs, sans juge ni worktree. Restent globaux, parce qu'ils ne dépendent d'aucun répertoire : `coauthor`, `prod-db`, les gates GitLab (`mr-create`, `rebase-skipci`, `mr-merge`) et l'hygiène (`tmp-ban`, `quiet-hours`, `external-lang`, `skill-required`).

**Cran par gate** : `~/.claude/wf-gates.conf` → `<gate> = block|warn|off`, relu à chaque appel. Un préfixe d'environnement sur une commande **ne parvient pas** au hook (process séparé) : pour lever un gate, éditer cette ligne. Kill switch de session : `WF_GATES_OFF=1` exporté **avant** de lancer Claude Code.

**Ce que les gates LISENT pour décider** (écrit par les hooks, jamais déclaré) : passage de juge, smoke-run, sortie verte d'un run de tests, `skip_ci=true` d'un rebase, skills chargés, push du tour. Un `git commit` périme l'**approbation** du juge, pas le fait qu'un round ait eu lieu (le gate reste levé). Scripts : `~/.claude/scripts/gate-*.sh`, `wf-record.sh`, `wf-bash-hook.sh`, `wf-subagent-hook.sh`, `wf-signals.py`, `wf-mr-ready.py` · tests : `~/.claude/scripts/tests/{gates,hooks}_test.sh`.

**INVARIANT DES GATES — un contrôle conclut sur un RÉSULTAT, jamais sur une requête.** Un gate doit être **levable** par une action que le workflow prescrit et que le harnais permet, et **non dupable** par le texte d'une demande. Trois conséquences tenues par les scripts, pas par la bonne volonté :

- **Un sous-agent est toujours asynchrone ici.** Son LANCEMENT ne lève aucun gate : la réponse immédiate ne porte qu'un `agentId` et **rejoue le prompt**. C'est le hook `SubagentStop` qui lit sa conclusion réelle, ou à défaut son `REPORT_FILE` relu par le gate, à condition que le verdict y soit **postérieur au lancement**.
- **Un message de refus décrit une sortie praticable.** Un gate qui prescrit un paramètre ou un outil inexistant coûte plus cher qu'un gate absent : il envoie dans une impasse avec l'autorité d'une règle.
- **Un nouveau gate se vérifie avant d'exister** : `tests/gates_class_guard.py` refuse une clé d'état qu'aucun hook n'écrit, une prescription inexistante, un gate sans cran dans `wf-gates.conf` ou absent de cette table, et tout état posé au lancement d'un sous-agent.

## BASE DE PROD — `/hotfix` SEULEMENT — RÈGLE ABSOLUE

**Seul `/hotfix` lit la base de prod** (diagnostic d'un bug sur des données réelles). `/plan`, `/dev`, `/orchestrator`, une session libre et leurs sous-agents n'y touchent jamais et **ne demandent jamais** d'accès DB, de tunnel ni de `gcloud auth` à l'utilisateur. Les vraies données ancrent la session sur un cas particulier et la font dériver : travailler depuis le code, les contrats, les tests et les fixtures ; une hypothèse sur les données reste marquée « non vérifiée ». L'intégration reste lisible (`malt-sql.sh --env integ`). Un vrai bug de prod en vue → proposer `/hotfix`. *(Gate `prod-db`.)*

## COUVERTURE DE CODE — RÈGLE ABSOLUE

**Toute ligne ajoutée ou modifiée doit être couverte par un test.** Nouveau comportement → TDD (`malt-backend-tdd`) ; code déjà écrit → `malt-test-coverage`. Avant de déclarer terminé : lancer les tests concernés, vert obligatoire, **citer la sortie**. Exceptions : code généré, config triviale, logs purs. Doute → couvrir.

## COMMENTAIRES DANS LE CODE — RÈGLE ABSOLUE

**Défaut = aucun commentaire. Plafond dur = 1 à 2 lignes.** Le nom, le test et le ticket JIRA portent l'explication ; le raisonnement va dans la description de MR et le commentaire JIRA de tradeoffs, jamais dans le fichier source. Un LLM qui vient de raisonner longuement a une pulsion forte de déverser ce raisonnement en KDoc — c'est le mode d'échec par défaut.

Un commentaire ne survit que s'il porte un fait **impossible à lire dans le code** dont l'ignorance ferait commettre une erreur : piège/invariant non évident, contrainte externe (quirk NetSuite, legacy, ordre, unité), « pourquoi PAS la solution évidente », `TODO`/`FIXME`, directives outillage (`ktlint-disable`, `language=SQL`, `eslint-disable`, licence).

Supprimer à vue : reformulation d'un nom, explication métier (elle vit dans JIRA), récit de ticket ou d'historique, énumération d'appelants, renvoi au KDoc d'une autre classe, titres markdown dans un commentaire, `@param`/`@return` qui répètent le type, `// given`/`// when`/`// then`, code commenté. **Raccourcir ≠ résumer** : garder le seul fait non lisible, sinon supprimer tout le bloc. Détail : skill **`claude-prose`** (source de vérité) ; où ça mord dans les workflows : `malt-workflow-commons` § DISCIPLINE DE COMMENTAIRE. **Contrôlé par moi en relisant mes `+` avant push — plus par le juge.**

## GIT WORKFLOW — RÈGLE ABSOLUE

**INTERDICTION DE TOUCHER `master`** — ni commit, ni modification du working tree (une modif non commitée collisionne avec les worktrees parallèles). Avant toute édition : `git branch --show-current` → si `master`, STOPPER et créer le worktree. *(Hook `master-guard`.)* Modifs déjà sur master → les porter dans un worktree puis `git checkout -- .`.

**Jamais de push sur `master`** : toujours branche + MR. **Toujours un worktree, hors du repo**, créé **depuis le repo principal** avec base `origin/master` explicite. Ne pas utiliser `EnterWorktree`.

```
cd ~/Documents/projects/malt && git fetch origin master
git worktree add ~/worktrees/malt/TICKET -b TICKET-description origin/master
```

Vérifier avant de travailler (`git status` = « On branch TICKET…, nothing to commit » ; `git log --oneline -3` = commits de master), sinon recréer. Tous les add/commit/push depuis le worktree ; après merge, `git worktree remove`.

**Titre de MR / subject du 1er commit** (le subject préremplit le titre) : `[<préfixe>] Titre` **en anglais**, préfixe = numéro de ticket (y compris `/hotfix`), sinon `[devscoot]` / `[hotfix]`. Noms de branche en anglais. Labels JIRA/GitLab → `malt-squad-conventions`.

**Reviewer, approbation, merge :**
- `@stephen.begot` en reviewer dès la création de la MR.
- Il **ne peut pas self-approve** (token à son nom) → son feu vert = un **commentaire dont le texte vaut `Approved`**, postérieur au dernier repush. Ses autres commentaires = demandes de changement, jamais ignorées.
- **Merge uniquement après `Approved` ET pipeline verte.** Procédure : rebase `skip_ci=true` **puis** merge `--squash --remove-source-branch` — jamais l'un sans l'autre (un rebase nu boucle la CI sur master).

**Interdits :** aucun `Co-Authored-By` · ne jamais lancer les linters à la main (le hook husky les exécute au commit — committer et lire le résultat).

**Après tout push — bloc de clôture obligatoire** (réinjecté par le hook `wf-bash-hook`) :
```
Travail poussé sur : <branche>
Description MR :
<contenu généré par /gitlab-resume>
```

## HEURES CALMES — 20h00 → 07h00 — RÈGLE ABSOLUE

**Aucune ré-invocation de Claude dans cette plage.** Gelés : `/loop`, `ScheduleWakeup`, boucles `until` en background qui ré-invoquent Claude, `await`/spawn de `/orchestrator` (et le hand-off `/plan`→`/orchestrator`), smoke-run en boucle.

**Avant toute programmation de ce type : `date +%H%M`** — si ∈ [2000,2359]∪[0000,0659] → ne pas programmer. Consigner l'état (fichiers, MR + numéro, JIRA + statut, `/goal`, où reprendre), onglet `[WAIT]` « paused — quiet hours », relance manuelle le matin.

**Exception** : action lancée par l'utilisateur en temps réel dans la plage (il est présent) — mais sans enchaîner sur un polling qui survivrait à la nuit.

## FICHIERS HORS REPO — JAMAIS `/tmp` — RÈGLE ABSOLUE

`/tmp`, `/private/tmp` et `/var/folders` sont purgés par macOS sans prévenir. **Tout fichier écrit hors d'un repo git vit sous `~/`.**

| Nature | Emplacement |
|---|---|
| Scratch, transit entre étapes | `~/tmp/scratch/` |
| Journal de session quotidien (`/end`, `/daily`) | `~/tmp/YYYY-MM-DD.md` |
| Bus d'échange + `STATUS_DIR` d'un chantier orchestré | `~/claude-exchange-llm/<WORKFLOW>/` |
| Mémoire persistante | `~/.claude/projects/<projet>/memory/` |
| Worktrees git | `~/worktrees/malt/<TICKET>` |

Seule exception : un fichier créé et consommé dans la même commande (`mktemp` d'un pipe).

## ANTI-VEILLE — process long en cours

Avant un process long (boucle `until` background, suivi pipeline, spawn `/orchestrator`, smoke-run), empêcher la veille — **en vérifiant d'abord qu'un `caffeinate` ne tourne pas déjà** :
```
pgrep -fl caffeinate            # vide → lancer ci-dessous ; sinon ne rien faire
nohup caffeinate -di >/dev/null 2>&1 &
```

## /end AVEC MR — VÉRIF PIPELINE (RÈGLE ABSOLUE)

Pipeline **verte** avant de clore ; rouge → diagnostiquer, fixer, repush (jamais master) jusqu'au vert ; job Sonar → `/sonar`. Attente : jamais `Monitor`. **Détail canonique : `malt-workflow-commons` § /end AVEC MR.**

## TITRE DE SESSION — RÈGLE ABSOLUE

Sujet lié à un ticket → le titre de la conversation **commence par le numéro de ticket** : `TICKET-123 description courte`.
✅ `BILL-2443 spike REST TBA auth` — ❌ `Fix bug paiement`.

## CONTEXTE MONOREPO MALT — pré-analyse

Avant d'explorer le repo (structure, build, où vit un domaine, conventions) : accounting/NetSuite → skill `malt-accounting-domain` ; sinon note Obsidian `[[Monorepo Malt - Carte technique]]` (via `/obsidian`), patterns `[[Architecture Backend]]` / `[[Architecture Frontend Nuxt]]`. Réutiliser cette pré-analyse plutôt que re-scanner.

**DRIFT — règle absolue :** du code réel qui contredit une note ou un skill (localisation, version, convention) → mettre à jour la note (`/obsidian` capture) ou le skill dans la foulée. Jamais laisser une carte périmée.
