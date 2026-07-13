---
description: WORKFLOW DE PLAN — analyser un besoin large, produire un plan + DAG de dépendances, créer les tickets JIRA parallélisables, puis (sur GO) superviser le fan-out CMUX (un /dev par ticket) jusqu'au drainage du DAG. Déclenché quand l'utilisateur décrit un besoin large sans ticket en entrée.
---

## Input

$ARGUMENTS

Le besoin large à découper (pas de ticket JIRA en entrée).

## WORKFLOW DE PLAN — RÈGLE ABSOLUE

TOUTES les étapes sont OBLIGATOIRES, dans l'ordre :

1. **Titre onglet** → `PLAN <résumé 3-4 mots>` (`~/.claude/scripts/cmux-tab.sh phase PLAN "<résumé>"`).
2. **Sync master — OBLIGATOIRE AVANT toute analyse.** L'étude DOIT partir de la dernière version de `master`. Depuis le repo principal (`cd ~/Documents/projects/malt`) :
   ```
   git fetch origin master
   git checkout master
   git pull --ff-only origin master
   ```
   - **Vérifier `git branch --show-current` == `master` et `git status` propre** avant le `pull`. Si le working tree est sale (modifs traînant sur master, cf. GIT WORKFLOW) → **STOPPER**, porter les modifs vers un worktree puis `git checkout -- .`, et ne reprendre qu'une fois master vierge.
   - `--ff-only` : si le pull n'est pas fast-forward → **STOPPER** et surfacer à l'utilisateur (master local divergent = anomalie à résoudre, jamais de merge/rebase silencieux).
   - **Ne rien éditer/committer sur master** : cette étape sert uniquement à mettre master à jour pour que l'analyse et la base des worktrees (`origin/master`) soient à jour.
3. **Analyse** — étudier le prompt utilisateur, le code, et les sources fournies. **Déléguer l'exploration à des sous-agents** (ORCHESTRATION). Sur repo Malt : note Obsidian `[[Monorepo Malt - Carte technique]]` d'abord (`/obsidian` recherche), sous-agent si insuffisant.
3. **Plan complet + DAG de dépendances** — plan d'implémentation découpé en **tâches parallélisables**. Chaque tâche parallélisable = 1 tâche JIRA. **Identifier explicitement les dépendances entre tâches** (B ne démarre qu'après merge de A) → construire le **DAG** : tâches **racines** (sans dépendance, lançables tout de suite) vs **dépendantes** (déclenchées après merge de leur(s) parent(s)).
4. **EPIC** — demander à l'utilisateur l'**EPIC** sous laquelle créer la User Story (au moment où c'en est besoin, pas avant).
5. **User Story unique** (skill `/jira`) — créer **UNE SEULE User Story** sous l'EPIC. Elle **décrit le besoin métier global** (le QUOI, pas le COMMENT). But : ne pas polluer le board de l'EPIC avec plein de tickets — toutes les tâches vivent **à l'intérieur** de cette story et sont regroupées par elle (plus besoin de préfixe de groupe sur les titres).
   - **Titre + Description OBLIGATOIREMENT en ANGLAIS**, point de vue **MÉTIER**.
6. **Création des tâches JIRA DANS la User Story** (skill `/jira`) — une tâche par tâche parallélisable, chacune **enfant de la User Story** (étape 5) via le champ **parent** (hiérarchie Epic → Story → Task/Sub-task). Chaque tâche :
   - **Titre + Description OBLIGATOIREMENT en ANGLAIS**, décrivant le besoin d'un point de vue **MÉTIER** (le QUOI, pas le COMMENT). Pas de préfixe : la User Story parente assure déjà le regroupement.
   - **Liens de dépendance JIRA** : pour chaque dépendance du DAG, créer un lien **"is blocked by"** (dépendant → parent).
   - **Bloc `PROMPT` en fin de description, EN FRANÇAIS** : le prompt exact qui servira à lancer `/dev` pour cette tâche. Y inclure une ligne metadata **`DEPENDS_ON: TICKET-A, TICKET-B`** (ou `DEPENDS_ON: -` si racine).
7. **Attendre le `GO IMPLEMENTATION`** de l'utilisateur. Ne rien lancer avant.
8. **GO IMPLEMENTATION — orchestrateur superviseur.** Superviser le DAG jusqu'au bout (voir `/cmux-tab`, section « Fan-out avec dépendances ») :
   - **Créer le dossier de statuts partagé** : `STATUS_DIR=/tmp/claude_plan_<EPIC>_status` (header `TMP_INDEX`).
   - **Spawn les tickets racines uniquement** (`DEPENDS_ON` vide), chacun dans **une nouvelle surface DANS LE MÊME WORKSPACE CMUX que le process qui lance** (jamais autre workflow ni workspace focus utilisateur), en passant `status_dir` + `ticket` :
     ```
     ~/.claude/scripts/cmux-tab.sh spawn "<bloc PROMPT du ticket + numéro JIRA + consigne: lance /dev>" "<TICKET-XXX résumé>" ~/Documents/projects/malt "$STATUS_DIR" TICKET-XXX
     ```
     `spawn` injecte le préambule "report ton statut" et écrit `SPAWNED`. Cible le workspace du process appelant (`$CMUX_SURFACE_ID`, jamais `$CMUX_WORKSPACE_ID`). Chaque surface = un Claude exécutant `/dev`.
     **cwd OBLIGATOIRE = `~/Documents/projects/malt`** (repo principal). Jamais un worktree ni le `$PWD` du Claude de plan : l'agent de dev crée son propre worktree.
   - **Écouter chaque ticket en vol** : `~/.claude/scripts/cmux-tab.sh await "$STATUS_DIR" TICKET-XXX` **EN BACKGROUND** (`run_in_background: true`) — jamais en foreground (cap 10 min du tool Bash). Le harness re-réveille l'orchestrateur à la sortie de l'`await`.
   - **Déclencher les dépendants** : à chaque réveil (un `await` sort → ticket `MERGED`), recalculer les tickets dont **tous** les `DEPENDS_ON` sont `MERGED`, les spawn, et lancer leur `await` en background. Répéter jusqu'au **drainage complet du DAG**.
   - **Gestion `BLOCKED`** : si un `await` sort en **code 3** (ticket `BLOCKED`), surfacer le blocage à l'utilisateur (onglet `[ASK]`) et **ne pas spawn** les dépendants de ce ticket tant que non résolu.
9. **Fin du Claude de plan** — s'arrêter **seulement une fois le DAG drainé** (tous `MERGED`, ou blocage explicité), en **laissant le terminal CMUX ouvert**. Ne pas fermer la surface.

## Rappels transverses (voir CLAUDE.md)

- **ORCHESTRATION PAR SOUS-AGENTS** : thread principal = orchestrateur ; déléguer exploration/analyse ; sous-agents retournent une CONCLUSION, pas des dumps. Sous-tâches indépendantes → plusieurs sous-agents dans le même message.
- **LANGUE** : titres/descriptions/liens JIRA en **ANGLAIS** ; seul le bloc `PROMPT` en français.
- **cmux-tab** : résolution workspace via `$CMUX_SURFACE_ID` (piège : `identify --surface` cassé, suit le focus).
