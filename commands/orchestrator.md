---
description: WORKFLOW D'ORCHESTRATION — propriétaire UNIQUE du fan-out CMUX + cycle de vie des tickets d'un chantier planifié. Spawn un /dev (impl) ou /plan (spike) par ticket prêt, écoute les statuts, déclenche les dépendants, absorbe les tickets créés par les sous-plans (RESCAN JIRA), draine le DAG. Une seule surface orchestrateur par workspace. Déclenché par /plan au GO IMPLEMENTATION (ou lancé à la main avec EPIC/umbrella + STATUS_DIR).
---

## Input

$ARGUMENTS

Le chantier à orchestrer. Doit fournir (via `/plan` au hand-off, ou à la main) :
- l'**EPIC** et/ou la **User Story parapluie** (umbrella) — source de vérité du périmètre ;
- le **`STATUS_DIR`** partagé — **toujours `$WF/_status`**, c.-à-d. `/Users/stephenbegot/claude-exchange-llm/<EPIC>/_status`. **JAMAIS sous `/tmp`** : macOS le purge en cours de chantier et tous les statuts disparaissent (incident vécu). Un `STATUS_DIR` `/tmp` proposé au hand-off doit être remplacé par `$WF/_status`.

Si l'un manque : le demander à l'utilisateur avant tout spawn.

**Invoquer le skill `malt-workflow-commons` EN PREMIER** — règles partagées : questions à choix, escalade archi, accès JIRA, préfixes CMUX, vérification des sources, vérification & boucles. Ce workflow y renvoie par nom de section. (`/orchestrator` n'a ni smoke-run, ni MR, ni TDD, ni livrable de dev : il ne code pas, il supervise.)

**Invoquer aussi le skill `malt-surface-exchange`** — l'orchestrateur **possède les inbox d'échange** du workspace (un inbox par SURFACE) : il crée l'arbre du workflow (`_inbox/orchestrator.md`), crée+headerise l'inbox de chaque surface (le header EST le prompt de départ) et spawn les enfants (spawn = lien seul). **Il n'y a plus de surface juge ni d'inbox juge** : chaque surface lance elle-même un sous-agent `judge` frais à son checkpoint (§ LOOP JUGE) — aucun câblage de contrôle à faire (§ RÔLE DE L'ORCHESTRATEUR). Il ne recopie pas le protocole ; il l'applique.

## RÈGLE ABSOLUE — ORCHESTRATEUR UNIQUE

Il existe **un seul processus orchestrateur par workspace CMUX**. Un `/plan` (racine ou enfant) et un `/dev` **ne spawn JAMAIS** de surface d'implémentation : ils planifient / implémentent puis reportent leur statut. **Tout** spawn de `/dev` et de `/plan` enfant, tout `await`, tout déclenchement de dépendant, tout RESCAN, passe par CE workflow. C'est la correction du bug « N orchestrateurs dans le même workspace » (collisions STATUS_DIR, double-spawn, heures-calmes dupliquées).

## HEADER CMUX

`[ORCH]` en permanence (ce processus en orchestre d'autres — commons § PRÉFIXES ; réservé à `/orchestrator`, plus rien ne flag `[MAIN]`). `[ASK]` ponctuel quand un `BLOCKED` est surfacé à l'utilisateur. `[END]` au drainage complet.

```
~/.claude/scripts/cmux-tab.sh phase ORCH "<résumé chantier>"
```

## WORKFLOW — RÈGLE ABSOLUE (toutes les étapes obligatoires)

1. **Titre onglet** → `[ORCH] <résumé chantier>`.
2. **Vérifier l'input** : EPIC/umbrella connu (sinon demander). `WF=/Users/stephenbegot/claude-exchange-llm/<EPIC>` ; `STATUS_DIR="$WF/_status"` ; `mkdir -p "$STATUS_DIR"` + un header `TMP_INDEX` (skill `malt-orchestration`). **Jamais `/tmp`.**
2a. **Mémoriser sa propre surface** — indispensable au réveil par push (skill `malt-surface-exchange` § RÉVEIL) :
   ```
   ORCH_SURFACE="$CMUX_SURFACE_ID"   # UUID stable ; à injecter dans le header de CHAQUE inbox enfant
   ```
   `ORCH_SURFACE` vide → l'annoncer à l'utilisateur : le fan-out fonctionnera mais **sans réveil push** (seuls le cron du step 7b et une relance manuelle feront avancer le DAG).
2b. **Créer l'arbre du workflow** (skill `malt-surface-exchange` § ARBORESCENCE, § RÔLE DE L'ORCHESTRATEUR) — **avant les racines**. **Un inbox par SURFACE** ; l'orchestrateur crée+headerise l'inbox fixe du workspace :
   ```
   WF=/Users/stephenbegot/claude-exchange-llm/<EPIC> && mkdir -p "$WF/_inbox"
   ~/.claude/scripts/cmux-tab.sh pair-init "$WF/_inbox/orchestrator.md" <<EOF
   INBOX ORCHESTRATEUR — les surfaces appendent ici STEP/DONE/BLOCKED + leurs demandes. L'orchestrateur écoute UNIQUEMENT ce fichier.
   EOF
   ```
   Conserver `WF` pour tous les spawns suivants. **Aucune surface juge à spawner** : chaque surface lance son propre sous-agent `judge` à son checkpoint.
3. **User Story parapluie → `In Progress`** (skill `/jira`) — première action.
4. **Construire le DAG initial depuis JIRA** (source de vérité, pas la mémoire — commons § VÉRIFICATION DES SOURCES) : lister les enfants de l'umbrella (`parent = <umbrella>`), lire pour chaque ticket son champ `Prompt` (`customfield_11956`) → `DEPENDS_ON` et son **TYPE** (impl → `/dev` ; spike/recherche → `/plan`). Racines = `DEPENDS_ON` vide.
5. **ANTI-VEILLE** (CLAUDE.md) : `pgrep -fl caffeinate` ; si vide → `nohup caffeinate -di >/dev/null 2>&1 &`.
6. **Spawn les racines uniquement**, chacune dans une nouvelle surface **du même workspace CMUX**, cwd `~/Documents/projects/malt`. **Séquence pour CHAQUE ticket** `T` (skill `malt-surface-exchange` § SPAWN = LIEN SEUL) — le TYPE (dev|plan) détermine **seulement le contenu du header (a)** ; la séquence de spawn est identique. **Aucun câblage juge** (le juge est un sous-agent lancé par la surface) :
   ```
   # (a) header = prompt de départ complet, écrit dans l'INBOX de la surface
   ~/.claude/scripts/cmux-tab.sh pair-init "$WF/<T>.md" <<EOF
   [ORCHESTRATION] STATUS_DIR=$STATUS_DIR TICKET=<T> ORCH_SURFACE=$ORCH_SURFACE
   Inbox — le tien (tu écoutes, et les juges y archivent leurs comptes rendus): $WF/<T>.md · orchestrateur (tu y postes): $WF/_inbox/orchestrator.md
   À CHAQUE transition, report ton statut ET réveille l'orchestrateur (RÈGLE ABSOLUE — c'est ce qui fait avancer le DAG) :
     ~/.claude/scripts/cmux-tab.sh report --notify $ORCH_SURFACE $STATUS_DIR <T> <STATE> "<detail>"
   STATES dev: IN_PROGRESS|MR_OPEN|MERGED|BLOCKED — STATES plan: IN_PROGRESS|PLANNED|BLOCKED
   Notifie chaque étape dans l'inbox orchestrateur: note --notify $ORCH_SURFACE "$WF/_inbox/orchestrator.md" "<T>[dev]" "STEP:…" "<preuve>". Au checkpoint (dev=pre-push · plan=plan-gate), lance TOI-MÊME un sous-agent judge frais par round jusqu'au verdict OK, REPORT_FILE=$WF/<T>.md (skill malt-surface-exchange § LOOP JUGE). Worktree attendu (dev): ~/worktrees/malt/<T>.
   <le champ Prompt du ticket>
   # impl : "Ticket JIRA: <T>. Suis le WORKFLOW DE DEV."
   # spike: "Ticket JIRA: <T>. Lance /plan en mode enfant-orchestré."
   EOF
   # (b) spawn = lien seul
   S=$(~/.claude/scripts/cmux-tab.sh spawn "Lis $WF/<T>.md et exécute tes instructions." "<T> <résumé>")
   # (c) report SPAWNED (le spawn ne l'écrit plus)
   ~/.claude/scripts/cmux-tab.sh report "$STATUS_DIR" <T> SPAWNED "surface=$S"
   ```
   Spawn cible `$CMUX_SURFACE_ID` (jamais `$CMUX_WORKSPACE_ID`). Séquence identique pour dev et plan (les deux lancent leur propre sous-agent juge) ; seul le contenu du header (a) diffère selon le TYPE.
7. **Écouter = NE RIEN FAIRE (RÈGLE ABSOLUE — skill `malt-surface-exchange` § RÉVEIL).** Après un lot de spawns, l'orchestrateur **ne lance AUCUN waiter background** (`await`, `await-note`, boucle de polling) et **ne poll pas**. Il **rend la main** ; ce sont les enfants qui le réveillent via `report --notify $ORCH_SURFACE`.
   *Pourquoi ce changement* : les process bash background sont tués par le harness sans garantie ni information de transition (observé : lots de 5-8 `killed`, parfois quelques secondes après lancement). S'appuyer dessus est précisément ce qui obligeait l'utilisateur à relancer l'orchestrateur à la main. `await`/`await-note` restent dans le script pour compatibilité — **ne plus s'en servir comme mécanisme de réveil**.
7b. **FILET DE SÉCURITÉ — un seul cron de re-scan, posé UNE FOIS après le premier lot de spawns.** Couvre le cas où aucun push n'arrive (surface fermée, `wake` en échec, heures calmes). Les crons ne se déclenchent qu'entre deux tours (jamais en plein tour) et expirent d'eux-mêmes après 7 jours.
   ```
   CronCreate(cron: "*/13 * * * *", recurring: true, durable: false,
     prompt: "[ORCH-FILET <EPIC>] Si l'heure locale est entre 20h00 et 07h00 : ne rien faire, répondre 'quiet hours'. Sinon : re-scan idempotent du chantier <EPIC> (steps 9 et 10 de /orchestrator) — relire $STATUS_DIR + les enfants de l'umbrella dans JIRA + $WF/_inbox/orchestrator.md, déclencher les dépendants prêts, spawn les orphelins. Si rien n'a changé depuis le dernier re-scan, répondre en une ligne et s'arrêter.")
   ```
   **Un seul cron par chantier** (le noter dans le `TMP_INDEX`) ; `CronDelete` au step 13. Cadence large volontaire : le push est le mécanisme nominal, le cron n'est qu'un rattrapage — inutile de brûler des tokens plus souvent.
8. **SPAWN IDEMPOTENT — un timeout/erreur du spawn ≠ échec (RÈGLE ABSOLUE).** Bash cape à 120s ; un spawn qui « timeout » a pu créer la surface + lancer l'agent. Spawns lents en `run_in_background: true` ; **avant de re-spawn, vérifier que `<ticket>.status` est VIDE** (`[ -s <dir>/<ticket>.status ]`). Un re-spawn crée un worker doublon sur le même worktree/branche (incident BILL-2909). Flakiness persistante → `new-surface --workspace <shortref>` en dur (`[[reference_cmux_tab_workspace_resolution]]`).
9. **RESCAN IDEMPOTENT — À CHAQUE RÉVEIL, QUELLE QU'EN SOIT LA CAUSE (RÈGLE ABSOLUE).** Le réveil peut venir d'un push enfant (`[CMUX-WAKE] …`), du cron du step 7b, d'une notification de tâche background, ou de l'utilisateur — **la réaction est toujours la même** et ne dépend jamais du contenu du réveil. **Ne jamais faire confiance au message de réveil** : il peut être absent, tronqué ou périmé (un `await` tué notifie « killed » sans l'info de transition). Reconstruire l'état depuis les seules sources qui n'ont jamais menti : **JIRA (périmètre + DAG) + git/GitLab (ce qui est réellement mergé) + `$STATUS_DIR`**. Corollaire : **un réveil manqué coûte du temps, jamais de l'information.** Le rescan comprend : Un `/dev` ou un `/plan` enfant peut créer de nouveaux tickets sous le parapluie (invisibles des status files) :
   - un **`/plan` enfant** qui reporte `PLANNED` a créé un lot de tickets (impl et/ou nouveaux spikes) sous l'umbrella ;
   - un **`/dev`** peut créer un ticket de travail découvert (commons § TRAVAIL DÉCOUVERT).
   À chaque réveil : re-lister les enfants de l'umbrella (`/jira`, `parent = <umbrella>`), lire leur `DEPENDS_ON` + TYPE, comparer au DAG connu, **intégrer tout orphelin** au DAG (séquence complète de spawn du step 6 — un seul `pair-init` de son inbox `$WF/<T>.md`, aucun câblage juge). **Le JIRA est la source de vérité du périmètre, pas le `STATUS_DIR`.**
   - **Contrôle de vivacité par l'inbox orchestrateur** (skill `malt-surface-exchange` § RÔLE DE L'ORCHESTRATEUR) : lire le flux `STEP` agrégé de `$WF/_inbox/orchestrator.md`. Une surface dont plus aucune entrée `STEP` fraîche n'apparaît depuis longtemps (header CMUX périmé) est potentiellement bloquée → la surfacer (`[ASK]`). Le `report`/`await` du STATUS_DIR reste l'autorité du cycle de vie ; l'inbox est le signal de vivacité.
   - **Détection de conflit** : deux devs en vol touchant des zones communes → poster un `CONFLICT` dans l'inbox de chacun (`$WF/<A>.md` et `$WF/<B>.md`) nommant le fichier/domaine partagé et qui coordonne (§ COORDINATION DEV↔DEV). Aucun fichier dédié.
10. **Déclencher les dépendants** — à chaque réveil, **recalculer le DAG depuis les liens JIRA à jour** (le RESCAN de l'étape 9 les a relus). Un ticket est prêt quand **tous** ses bloqueurs (`is blocked by`) sont `MERGED`. Deux points clés sur les spikes-plan :
    - **`PLANNED` ne débloque JAMAIS un dépendant à lui seul.** Quand un spike-plan reporte `PLANNED`, le `/plan` enfant a **recâblé** les dépendants du spike : le lien `B is blocked by <SPIKE>` a été remplacé par `B is blocked by <tickets-feuilles produits>` (cf. `/plan` § MODE ENFANT-ORCHESTRÉ, RECÂBLAGE). Donc après RESCAN, B dépend de tickets réels à merger — et se débloque, comme tout ticket, sur le `MERGED` de ses bloqueurs. Le spike lui-même sort du DAG une fois `PLANNED` (son travail = avoir produit et lié les tickets).
    - Un dépendant sur un ticket **/dev** se débloque sur son `MERGED`.
    Spawn les nouveaux tickets prêts (role adapté), puis **rendre la main** (pas d'`await` — step 7). Répéter à chaque réveil jusqu'au **drainage complet du DAG**.
11. **HEURES CALMES 20h–7h (RÈGLE ABSOLUE, CLAUDE.md).** À chaque réveil, `date +%H%M` AVANT tout spawn. Si ∈ [2000,2359]∪[0000,0659] → STOPPER NET (aucun spawn, aucun réveil programmé ; `CronDelete` le cron du step 7b), consigner l'état du DAG + point de reprise, `[WAIT]` « paused — quiet hours ». Relance manuelle le matin (recréer le cron à ce moment-là). Côté enfants, `cmux-tab.sh wake` refuse déjà d'émettre dans la plage : les statuts s'écrivent, les réveils sont différés au rescan du matin.
12. **`BLOCKED`** — statut `BLOCKED` lu au rescan (ou push `[CMUX-WAKE] … BLOCKED`) → surfacer (`[ASK]`), ne PAS spawn les dépendants de ce ticket tant que non résolu.
13. **Fin** — DAG drainé (toutes tâches `MERGED`, tous spikes `PLANNED` et leurs sous-arbres `MERGED`, zéro orphelin au RESCAN) → `[END]` : **`CronDelete` du cron de filet (step 7b)**, puis **User Story → `To Validate`** (jamais `Done` soi-même — validation humaine). Poser une entrée `DONE` dans son propre inbox (`$WF/_inbox/orchestrator.md`) — rien à libérer côté contrôle, les juges sont des sous-agents éphémères. S'arrêter en laissant le terminal CMUX ouvert. (Blocage → laisser en `In Progress` et surfacer.)

## `/goal` de l'orchestrateur

Ligne d'arrivée mesurable (commons § VÉRIFICATION & BOUCLES levier 2) : **DAG entièrement drainé** — toutes tâches `MERGED`, tous spikes `PLANNED` avec leur sous-arbre `MERGED`, zéro orphelin au dernier RESCAN de l'umbrella. Tant que ce n'est pas tenu, l'orchestrateur boucle (réveil → RESCAN → déclencher → await). Blocage non résolu → `[BLOCK]`/`[ASK]`, jamais d'acharnement.

## MODE MULTI-DOMAINES (chantier traversant plusieurs domaines)

Quand le `/plan` racine a découpé par **domaine** et créé un ticket spike-plan par domaine : l'orchestrateur les traite exactement comme les autres tickets spike (type plan, terminal `PLANNED`). Chaque domaine se fait planifier par un `/plan` enfant qui crée ses tickets sous l'umbrella (ou un sous-parapluie) ; l'orchestrateur unique absorbe le tout au RESCAN et spawn les `/dev` correspondants. **Aucun sous-orchestrateur** : un seul niveau d'orchestration, un arbre de planning arbitrairement profond au-dessus.

## Rappels transverses (voir CLAUDE.md et skill `malt-workflow-commons`)

- **ORCHESTRATION PAR SOUS-AGENTS** (skill `malt-orchestration`) : déléguer les lectures JIRA lourdes / analyses de DAG à des sous-agents ; CONCLUSION, pas dumps.
- **GIT WORKFLOW** (CLAUDE.md) : l'orchestrateur ne code pas, ne touche jamais master. Les enfants créent leurs worktrees.
- **LANGUE** (CLAUDE.md) : écriture JIRA en **anglais** ; seuls le champ `Prompt` et les prompts de spawn en français.
- **Labels de squad** : tout ticket créé (par un enfant, capté au RESCAN) doit porter le label de squad (skill `malt-squad-conventions`) — le rappeler dans le prompt de spawn des `/plan` enfants.
