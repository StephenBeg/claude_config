---
name: malt-surface-exchange
description: Bus d'échange par INBOX de surface CMUX d'un workspace orchestré + protocole du JUGE en SOUS-AGENT (loop de contrôle radical-honesty, un juge frais par round, compte rendu écrit dans le fichier de la surface). Source de vérité UNIQUE du protocole — invoqué par /orchestrator, /dev, /plan, /hotfix. Couvre — arborescence par workflow, inbox par nœud (chaque surface n'écoute QUE son propre fichier ; header=prompt de départ écrit par l'orchestrateur + journal append-only), routage, spawn réduit à un lien, écho des chemins au démarrage, notification obligatoire à chaque étape, loop juge borné jusqu'au verdict OK, coordination dev↔dev sur conflit, checklist DONE auditable. Ne jamais recopier ce protocole ailleurs : y renvoyer par nom de section.
---

# Surface exchange — inbox par nœud + juge en sous-agent

Rend les échanges entre surfaces CMUX d'un chantier **auditables** (journal immuable sur disque) et le **LLM-as-judge** **itératif et traçable** (loop jusqu'à verdict OK) au lieu d'un contrôle one-shot noyé dans le contexte qui a produit le travail.

**Le juge n'est PLUS une surface CMUX.** C'est un **sous-agent `judge`** lancé par la surface elle-même (dev/hotfix/plan), en contexte frais, **un juge NEUF à chaque round**. Plus d'inbox juge, plus de `/judge`, plus de monitor à surveiller : le loop vit entièrement dans la surface qui demande le verdict, et le **compte rendu de chaque juge est écrit dans le fichier de cette surface** (§ LOOP JUGE).

**Modèle = un fichier INBOX par SURFACE (nœud), PAS un fichier par paire.** Chaque surface possède exactement UN fichier — sa boîte de réception append-only — et **n'écoute QUE ce fichier**. Pour solliciter une autre surface, on **append dans l'inbox du destinataire** ; la réponse revient **dans l'inbox du demandeur**. L'orchestrateur n'a donc qu'**un seul fichier fixe** à surveiller par workspace.

**Mécanisme = PUSH ACTIF + RE-SCAN IDEMPOTENT.** Une surface qui progresse **réveille elle-même** son destinataire (`--notify`, § RÉVEIL) ; personne ne poll. Et tout réveil manqué est rattrapé par un **re-scan depuis la source de vérité** — jamais par une relance humaine. **Le verdict du juge n'utilise AUCUN de ces mécanismes** : c'est un appel de sous-agent synchrone (§ LOOP JUGE).

Toutes les sections sont des **RÈGLES ABSOLUES**.

**ROUTAGE PAR MODE — chaque section est taguée `[SOLO+ORCHESTRÉ]` ou `[ORCHESTRÉ UNIQUEMENT]`.** `/dev`/`/hotfix`/`/plan` en **solo** (pas de header `[ORCHESTRATION]`) : lire seulement les sections `[SOLO+ORCHESTRÉ]` — § ARBORESCENCE (paragraphe « Cas SOLO »), § LOOP JUGE, § RÔLE DU JUGE. Les sections `[ORCHESTRÉ UNIQUEMENT]` ne s'appliquent pas et peuvent être sautées. `/orchestrator` et les surfaces qu'il spawn lisent tout.

---

## § RÉVEIL [ORCHESTRÉ UNIQUEMENT] — push actif d'abord, re-scan idempotent comme socle (RÈGLE ABSOLUE)

Corrige le bug historique « l'orchestrateur ne repart que si l'humain tape *continue* ».

**Trois couches, dans cet ordre.**

**1. PUSH ACTIF (nominal).** La surface qui progresse **réveille** son destinataire en lui injectant un prompt. Constaté empiriquement (2026-08-17, `~/.claude/scripts/tests/cmux-wake-test.sh`) : `cmux send` + `send-key enter` sur une surface CMUX réveille un Claude **au repos** en ~4 s, et **met en file** (sans corrompre le tour) un Claude **occupé**.

```
# enfant → orchestrateur, à CHAQUE transition de cycle de vie :
~/.claude/scripts/cmux-tab.sh report --notify "$ORCH_SURFACE" "$STATUS_DIR" <T> <STATE> "<detail>"
# enfant → orchestrateur, à chaque étape (couplé au header CMUX, § NOTIFICATION) :
~/.claude/scripts/cmux-tab.sh note --notify "$ORCH_SURFACE" "$WF/_inbox/orchestrator.md" "<T>[dev]" "STEP:<nom>" "<preuve>"
# dev A → dev B (conflit) : --notify <surface de B>
```
`$ORCH_SURFACE` (UUID de la surface orchestrateur) est **transmis dans le header de l'inbox** de chaque surface, au même titre que `STATUS_DIR` (§ QUI CRÉE QUOI). Sans lui, `--notify` est simplement omis (dégradation propre : on retombe sur la couche 3).

**Limite connue du push, mesurée.** Un `wake` envoyé **pile pendant la bascule de fin de tour** de la cible peut être **perdu** (observé une fois sur trois runs du test : ni file d'attente, ni prompt). `wake_surface()` attend donc que la cible ne soit plus `running` (index `~/.cmuxterm/claude-hook-sessions.json`, max 40 s) avant d'envoyer. Cela réduit la fenêtre sans la fermer : **le push reste best-effort par construction**, d'où les couches 2 et 3 — non optionnelles.

**2. FILET PÉRIODIQUE (secours).** L'orchestrateur pose **un** cron de re-scan (`/orchestrator` step 7b). Il couvre le cas « le push n'est jamais parti » (surface fermée, `wake` en échec, heures calmes).

**3. RE-SCAN IDEMPOTENT (socle — ne ment jamais).** Source de vérité = **JIRA + git + le `STATUS_DIR` durable**, JAMAIS la mémoire ni un process vivant. À chaque réveil, quelle qu'en soit la cause, l'orchestrateur **reconstruit** l'état complet (`/orchestrator` step 9). Conséquence assumée : **un réveil manqué coûte du temps, jamais de l'information.**

**Ce qui NE marche PAS — ne pas y revenir :**
- Les process bash background (`await`, `await-note`, boucles de polling) sont **tués sans garantie** par le harness (observé : lots de 5-8, parfois quelques secondes après lancement). Ils restent dans le script pour compatibilité mais **ne sont plus le mécanisme de réveil**. Un `await` tué notifie « killed » sans l'info de transition → réveil aveugle, ou pas de réveil du tout.
- **Détacher** le waiter (`nohup`/`setsid`/`disown`) le fait survivre **mais il ne réveille plus jamais l'agent**. Piège connu, interdit.
- `cmux notify` / `set-status` / `trigger-flash` sont **purement UI** : aucun effet sur le process agent.
- `STATUS_DIR` sous `/tmp` : **purgé par macOS** en cours de chantier (incident vécu). Le script émet désormais un avertissement.

**HEURES CALMES 20h–7h** : un `wake` ré-invoque Claude → `cmux-tab.sh wake` **refuse d'envoyer** dans la plage (sort en code 4) et l'appelant continue normalement. L'info reste sur disque ; la couche 3 la récupère au redémarrage manuel du matin.

---

## § ARBORESCENCE — un dossier par workflow, un inbox par surface [ORCHESTRÉ UNIQUEMENT]

Racine : `/Users/stephenbegot/claude-exchange-llm/`. **Un sous-dossier par WORKFLOW** (chantier orchestré — isole les orchestrateurs parallèles) ; nommé d'après l'**EPIC/umbrella** (source de vérité du périmètre, connue de l'orchestrateur). Sous lui : l'inbox fixe de l'orchestrateur dans `_inbox/`, plus un inbox par ticket à la racine.

```
/Users/stephenbegot/claude-exchange-llm/<WORKFLOW>/
├── _inbox/
│   └── orchestrator.md          # INBOX ORCHESTRATEUR (nom fixe/workspace)
├── _status/                     # STATUS_DIR DURABLE (report/await) — JAMAIS sous /tmp (purgé)
└── <TICKET>.md                  # INBOX de la surface (dev|plan|hotfix) du ticket
                                 #   = aussi le fichier où sont archivés les comptes rendus des juges
```

**`STATUS_DIR` = `$WF/_status`** (RÈGLE). macOS purge `/tmp` : un `STATUS_DIR` sous `/tmp` a déjà fait disparaître tous les statuts d'un chantier en cours. Le dossier d'échange est le seul emplacement stable partagé par toutes les surfaces.

**Résolution déterministe du chemin** (tout membre calcule le même chemin sans se parler), avec `WF=/Users/stephenbegot/claude-exchange-llm/<WORKFLOW>` :

| Inbox de… | Fichier |
|---|---|
| Orchestrateur | `$WF/_inbox/orchestrator.md` |
| Surface du ticket T (dev/plan/hotfix) | `$WF/<T>.md` |

**Il n'existe plus d'inbox juge, ni de fichier de paire, ni de dossier `_pairs/`.** Une surface obtient tout ce dont elle a besoin en lisant SON inbox ; l'orchestrateur a UN inbox fixe. La coordination dev↔dev passe par les inbox des devs eux-mêmes (§ COORDINATION DEV↔DEV).

**Cas SOLO (pas d'orchestrateur).** Le loop juge s'applique **aussi en solo** : la surface se donne un fichier de surface sous `$WF` avec `WORKFLOW=_solo` — soit `SURFACE_FILE=/Users/stephenbegot/claude-exchange-llm/_solo/<TICKET>.md`. Le créer si absent (`mkdir -p` + `pair-init` avec un header d'une ligne : ticket + mode solo). C'est là que les comptes rendus des juges sont archivés. Aucun autre inbox n'existe en solo.

---

## § ANATOMIE D'UN INBOX — header + journal append-only [ORCHESTRÉ UNIQUEMENT]

Chaque inbox a **deux zones** :

1. **HEADER** — écrit **une seule fois par le CRÉATEUR** (l'orchestrateur, voir § QUI CRÉE QUOI), via `cmux-tab.sh pair-init <file>` (stdin). Immuable après création.
   - **Inbox d'une surface `$WF/<T>.md`** : le header **EST le prompt de départ complet** de cette surface — rôle, ticket, `WORKFLOW DE DEV`/`/plan`, `STATUS_DIR` + protocole `report`, et les chemins qu'elle doit connaître (son propre inbox, l'inbox orchestrateur). La surface spawnée lit ce header comme ses instructions.
   - **Inbox orchestrateur (`_inbox/orchestrator.md`)** : le header est **minimal** — titre + rôle du canal. Ce n'est pas un prompt de départ.
2. **JOURNAL (append-only)** — sous le marqueur `## JOURNAL (append-only)` (posé par `pair-init`). Tout le monde y **append** via `cmux-tab.sh note` — **jamais d'édition ni de suppression**. Écriture uniquement via `note` (append atomique sous lock — un `>>` nu n'est pas atomique au-delà de 512 o sur macOS).

Initialiser un inbox (header) :
```
# Inbox d'une surface (header = prompt de départ) :
~/.claude/scripts/cmux-tab.sh pair-init "$WF/<T>.md" <<'EOF'
[ORCHESTRATION CMUX] Un orchestrateur t'a lancé et attend tes statuts.
STATUS_DIR=$WF/_status TICKET=<T> ORCH_SURFACE=<UUID de la surface orchestrateur>
Inbox — le tien (tu écoutes ce fichier, et tu y archives les comptes rendus des juges): $WF/<T>.md · orchestrateur (tu y postes): $WF/_inbox/orchestrator.md
<le champ Prompt du ticket + "Ticket JIRA: <T>. Suis le WORKFLOW DE DEV.">
À CHAQUE transition, report ton statut ET réveille l'orchestrateur (§ RÉVEIL) :
  cmux-tab.sh report --notify $ORCH_SURFACE $WF/_status <T> <STATE> "<detail>"
EOF

# Inbox fixe orchestrateur (header minimal) :
~/.claude/scripts/cmux-tab.sh pair-init "$WF/_inbox/orchestrator.md" <<'EOF'
INBOX ORCHESTRATEUR — les surfaces appendent ici STEP/DONE/BLOCKED. L'orchestrateur écoute UNIQUEMENT ce fichier.
EOF
```

Appendre une entrée de journal :
```
~/.claude/scripts/cmux-tab.sh note "<inbox_file>" "<LABEL>" "<EVENT>" "<detail multi-lignes>"
```
- `LABEL` : `<TICKET>[dev]` · `<TICKET>[plan]` · `JUDGE` · `ORCHESTRATOR`.
- `EVENT` (vocabulaire fixe) : `STEP:<nom>` · `JUDGE-VERDICT: OK round N` · `JUDGE-VERDICT: NEEDS_WORK round N` · `CONFLICT` · `BLOCKED` · `DONE`.

**Routage des EVENT vers le bon fichier** (RÈGLE) :
- `STEP:*`, `DONE`, `BLOCKED` (progression/vivacité/checklist d'une surface) → **inbox orchestrateur** (`$WF/_inbox/orchestrator.md`).
- `JUDGE-VERDICT: …` (compte rendu d'un sous-agent `judge`) → **fichier de la surface jugée** (`$WF/<T>.md`, ou le `SURFACE_FILE` solo). **Écrit par le sous-agent juge lui-même** ; la surface n'a rien à recopier.
- Coordination de conflit (dev A → dev B) → **inbox de dev B** (`$WF/<B>.md`) ; la réponse de B → **inbox de dev A** (`$WF/<A>.md`).

---

## § QUI CRÉE QUOI — l'orchestrateur possède les inbox [ORCHESTRÉ UNIQUEMENT]

**L'orchestrateur crée et header TOUS les inbox.** Aucune autre surface ne crée d'inbox (elles n'appendent qu'aux journaux d'inbox déjà créés).

| Inbox | Créé + headeré par | Header contient |
|---|---|---|
| `$WF/_inbox/orchestrator.md` | Orchestrateur, au démarrage du workflow | header minimal (rôle du canal) |
| `$WF/<T>.md` | Orchestrateur, **avant** le spawn de T (dev ET plan) | le **prompt de départ complet** de la surface T (dont le checkpoint juge attendu : dev=pre-push · plan=plan-gate) |

En **solo**, il n'y a pas d'orchestrateur : la surface crée elle-même son `SURFACE_FILE` sous `_solo/` (§ ARBORESCENCE, cas SOLO) au moment du premier round de juge.

---

## § SPAWN = LIEN SEUL — tout le prompt vit dans l'inbox de la surface [ORCHESTRÉ UNIQUEMENT]

`cmux-tab.sh spawn` ne construit **aucun préambule** : le prompt de départ est **déjà** dans le header de l'inbox `$WF/<T>.md`. Le spawn ne transporte qu'un **pointeur** :

```
~/.claude/scripts/cmux-tab.sh spawn \
  "Lis $WF/<T>.md et exécute tes instructions." \
  "<T> <résumé>"
```

**Il n'y a plus de surface juge à spawner** : chaque surface lance son propre sous-agent `judge` au checkpoint (§ LOOP JUGE).

Séquence orchestrateur pour chaque surface (dev ou plan) :
1. `pair-init "$WF/<T>.md"` — écrire le header (= prompt de départ).
2. `spawn "Lis $WF/<T>.md et exécute…" "<T> …"` → récupère `surface:N`.
3. `report "$STATUS_DIR" <T> SPAWNED "surface=$surface"` (le spawn ne l'écrit plus).

**Plus de `pair-init` de fichier juge, plus d'annonce `PAIR-ADDED`, plus de surface juge** : un nouveau ticket est absorbé sans aucun câblage de contrôle.

---

## § ANNONCE DES CHEMINS AU DÉMARRAGE — OBLIGATOIRE [ORCHESTRÉ UNIQUEMENT]

Dès sa 1re étape, **toute surface CMUX** (dev/plan/hotfix, ainsi que l'orchestrateur pour son propre inbox) **affiche à l'utilisateur, en clair et en chemin ABSOLU**, l'inbox qu'elle écoute et ceux où elle poste, pour qu'il puisse les **ouvrir en side dans cmux** :

```
📂 Fichiers d'échange (ouvre en side dans cmux) :
  • mon inbox (j'écoute, + comptes rendus des juges) : $WF/<T>.md
  • → orchestrateur (je poste)                       : $WF/_inbox/orchestrator.md
```

L'orchestrateur affiche son **propre** inbox. En **solo**, afficher le seul `SURFACE_FILE` (`…/_solo/<TICKET>.md`) dès le premier round de juge.

## § NOTIFICATION À CHAQUE ÉTAPE — OBLIGATOIRE (couplée au header CMUX) [ORCHESTRÉ UNIQUEMENT]

**Règle de couplage : chaque fois qu'une surface met à jour son header CMUX (`cmux-tab.sh phase …`), elle pose AUSSI une entrée `note STEP:<nom>` dans l'INBOX ORCHESTRATEUR** (`$WF/_inbox/orchestrator.md`) — même contenu de résumé. Header et journal avancent ensemble ; un header à jour sans entrée (ou l'inverse) = violation.

```
~/.claude/scripts/cmux-tab.sh phase IMPL "TRY PAR EVENTID"
~/.claude/scripts/cmux-tab.sh note --notify "$ORCH_SURFACE" "$WF/_inbox/orchestrator.md" "<T>[dev]" "STEP:impl" "TDD rouge→vert sur try par eventId"
```
`--notify "$ORCH_SURFACE"` est **obligatoire en mode orchestré** (§ RÉVEIL) : c'est ce qui fait avancer le DAG sans intervention humaine. Omettre `--notify` si `ORCH_SURFACE` n'est pas dans le header.

- L'entrée `STEP` dit **où en est** la surface et **ce qui est fait/prouvé** (pas un simple libellé) : ex `STEP:pipeline` → `pipeline #12345 verte (cité), 0 conflit GitLab`.
- **Étapes dont la notification est explicitement due** : worktree créé, GATE liste de tests, impl, MR ouverte (+ n° MR), **suivi pipeline verte** (citer le statut), **conflits GitLab** signalés/résolus, **`/end` exécuté**, `Approved` reçu, merge.
- Hors mode orchestré (pas d'inbox dans le préambule) : la notification est **sans objet** — la surface suit son header CMUX normalement.

---

## § LOOP JUGE [SOLO+ORCHESTRÉ] (côté /dev · /hotfix · /plan) — sous-agent frais par round, borné jusqu'au verdict OK

**S'applique EN SOLO COMME EN ORCHESTRÉ.** Le juge est un **sous-agent `judge`** (`Agent` tool, `subagent_type: "judge"`), lancé **par la surface elle-même**, en contexte frais, **synchrone** (`run_in_background: false` — on a besoin du verdict pour continuer). Il **remplace** le subagent `reviewer` à ces checkpoints et remplace l'ancienne surface `/judge` (supprimée : plus d'inbox juge, plus de monitor à surveiller, plus de navigation entre onglets).

**RÈGLE ABSOLUE — UN JUGE NEUF PAR ROUND.** Chaque round lance un **nouvel** appel `Agent` : jamais de `SendMessage` vers un juge déjà utilisé, jamais de réutilisation de contexte. Un juge qui a vu le round N-1 n'est plus neutre. On reboucle jusqu'à ce qu'**un juge dise `OK`**.

**Checkpoints** : `/dev` step 4 (avant push) · `/hotfix` step 7b · `/plan` step 9 (GATE avant SPIKE DONE).

**Fichier de compte rendu.** Avant le round 1, poser `SURFACE_FILE` :
- **orchestré** → `SURFACE_FILE="$WF/<T>.md"` (mon propre inbox) ;
- **solo** → `SURFACE_FILE=/Users/stephenbegot/claude-exchange-llm/_solo/<TICKET>.md`, créé si absent (`mkdir -p` + `pair-init`, header = ticket + « mode solo »).

C'est **le juge** qui y append son compte rendu (`JUDGE-VERDICT: … round N` + preuves). La surface ne recopie rien ; elle **relit le fichier** si elle a besoin de l'historique des rounds.

**Protocole du round** (`round N`, N à partir de 1) :
1. **Lancer un juge frais** avec un prompt **auto-suffisant** (il vérifie tout lui-même, il n'a AUCUN contexte) :
   ```
   Agent(subagent_type: "judge", run_in_background: false, description: "judge round N <T>", prompt:
     "CHECKPOINT=<pre-push | hotfix-verify | plan-gate>  ROUND=N  TICKET=<T>
      WORKTREE=<chemin absolu>  BRANCH=<branche>   (ou, plan-gate : UMBRELLA + clés des tickets créés + DAG)
      REPORT_FILE=<SURFACE_FILE>
      CONSIGNE=<le champ Prompt / la consigne exacte, verbatim>
      CE QUE JE PRÉTENDS AVOIR FAIT=<…, avec les tests censés couvrir>
      GAPS DES ROUNDS PRÉCÉDENTS ET CE QUE J'AI CORRIGÉ=<… ou 'aucun, round 1'>")
   ```
2. **Lire le verdict retourné** (et le compte rendu dans `SURFACE_FILE`) :
   - `VERDICT: OK` → checkpoint franchi, continuer.
   - `VERDICT: NEEDS_WORK` → traiter **chaque GAP** (correctness/scope ; pas de sur-correction de style), repush si besoin (`[IMPL]`/`[PIPE]`), puis **round N+1 avec un juge NEUF**. Les corrections ne valent jamais approbation : re-soumettre.

**RÈGLE ABSOLUE — PAS DE ROUND N+1 SANS PREUVE DE CLÔTURE PAR GAP.** Le juge est déjà exhaustif en un seul passage (round 1 liste TOUS les GAPS d'un coup — voir `judge.md` § EXHAUSTIVITÉ). Si un round N+1 retrouve encore quelque chose, ce n'est quasiment jamais que le juge a mal cherché : c'est que la correction du round N était **incomplète, bâclée, ou a introduit un effet de bord**, resoumise sans vérification. Métaphore : le juge dit « il manque 80 % du mur à peindre » — repeindre 20 % puis resoumettre en espérant que ça passe est **interdit**. Pour CHAQUE GAP du round N, avant de relancer un juge :
1. **Traiter toute l'étendue du GAP**, pas seulement l'exemple cité (le juge dit "cas limite X non testé sur la méthode Y" → vérifier s'il y a d'autres cas analogues non couverts sur la même méthode, pas seulement X).
2. Appliquer le fix.
3. **Produire la preuve de clôture spécifique à ce GAP** — rejouer exactement ce que le GAP mettait en défaut : le test cité repasse au vert (sortie citée), la ligne signalée est désormais couverte (rapport de coverage), le comportement décrit est effectivement présent dans le diff (`path:line` cité), le test de non-régression pour un bug introduit existe et passe.
4. **Un GAP n'est coché fermé QUE si cette preuve rejouée existe.** "Je pense l'avoir corrigé" sans preuve rejouée = GAP encore ouvert — ne pas resoumettre tant que ce n'est pas fait.
5. Seulement quand TOUS les GAPS du round N sont fermés avec preuve → lancer le `judge` round N+1, en indiquant pour chaque GAP la preuve rejouée dans `CE QUE J'AI CORRIGÉ` (pas une simple déclaration) — le juge round N+1 vérifie vite au lieu de tout redécouvrir.

3. **Borne dure : 4 rounds.** Toujours `NEEDS_WORK` au round 4, ou désaccord technique argumenté → **STOPPER, escalader à l'utilisateur** (`[ASK]`) en citant les GAPS résiduels. Jamais d'acharnement, jamais franchir en ignorant un verdict.
4. **Notifier** (mode orchestré) : `note "$WF/_inbox/orchestrator.md" "<T>[dev]" "STEP:judge" "round N → OK|NEEDS_WORK (<résumé>)"`.

Le loop est **entièrement contenu dans la surface** : aucune attente inter-surfaces, aucun `await-note`, aucune action de l'utilisateur. Un round ne « se perd » plus.

**HEURES CALMES 20h–7h** (CLAUDE.md) : un round de juge est un appel synchrone borné, pas un poll — il est autorisé. Ce qui reste interdit dans la plage : programmer un réveil/poll après le verdict.

---

## § RÔLE DU JUGE [SOLO+ORCHESTRÉ] (sous-agent `judge`)

Le prompt système complet vit dans `~/.claude/agents/judge.md`. Invariants portés ici (source de vérité) :

- **Contexte frais, un juge par round.** Il n'a jamais vu le code produit ni les rounds précédents autrement que par ce que la requête lui dit — et il vérifie ce qu'on lui dit.
- **VÉRIFICATION FRAÎCHE, JAMAIS LA MÉMOIRE.** Ni mémoire persistante, ni notes Obsidian comme vérité. Il **rétablit tout lui-même** : `git diff` réel dans le worktree indiqué, code réel `path:line`, exécution/lecture des tests, logs Datadog/Sentry, statut de pipeline, tickets JIRA réels. Tout verdict cite une **preuve réelle**.
- **RADICAL HONESTY · NEUTRE · FIABLE.** Il cherche à **réfuter** que le travail est complet et correct (requirement non couvert, cas limite sans test, effet de bord hors scope, archi douteuse, parité rompue, coverage insuffisante). Verdict `OK` seulement si aucun GAP de correctness/scope ne subsiste ; sinon `NEEDS_WORK` + GAPS précis et actionnables (`path:line`, cas manquant). Ni complaisance, ni chicane de style.
- **Ne code rien, ne touche aucun worktree** (lecture seule). Sa **seule écriture** est son compte rendu dans le `REPORT_FILE` de la surface — trace auditable de chaque round.

---

## § RÔLE DE L'ORCHESTRATEUR (côté /orchestrator) [ORCHESTRÉ UNIQUEMENT]

- **Créer l'arbre du workflow** au démarrage : `WF=/Users/stephenbegot/claude-exchange-llm/<EPIC>` ; `mkdir -p "$WF/_inbox"` ; `pair-init "$WF/_inbox/orchestrator.md"` (header minimal). **Aucun inbox juge, aucune surface juge à spawner.**
- **Pour chaque ticket spawné** (racine ou capté au RESCAN, dev ET plan) : `pair-init "$WF/<T>.md"` (header = prompt de départ, incluant le checkpoint juge attendu) ; puis `spawn "Lis $WF/<T>.md et exécute…" "<T> …"` (lien seul) ; puis `report SPAWNED`. **Aucun câblage juge** — la surface lance son propre sous-agent `judge`.
- **Détection de conflit** : si le DAG révèle des zones chaudes communes entre deux devs en vol, poster un `CONFLICT` dans l'inbox de chacun (`$WF/<A>.md` et `$WF/<B>.md`) décrivant le fichier/domaine partagé et qui coordonne (§ COORDINATION DEV↔DEV).
- **Écoute** : **PASSIVE** (§ RÉVEIL). L'orchestrateur ne poll pas et ne lance pas de waiter background : il est **réveillé par push** par les surfaces (`report --notify` / `note --notify`) et, à défaut, par son **cron de re-scan**. À chaque réveil il relit son inbox `$WF/_inbox/orchestrator.md` + le `STATUS_DIR` + JIRA. Répondre/instruire une surface = poster dans son inbox `$WF/<T>.md` **avec `--notify <surface de T>`**.
- **Transmettre son propre UUID de surface** (`cmux-tab.sh get` → `$CMUX_SURFACE_ID`) dans le header `ORCH_SURFACE=` de chaque inbox qu'il crée — sinon aucun enfant ne peut le réveiller.
- **Au RESCAN** : lire l'inbox orchestrateur (flux `STEP` agrégé) pour vérifier que les surfaces en vol **progressent**. Une surface muette anormalement longtemps = potentiellement bloquée → la surfacer. Le `report`/`await` du STATUS_DIR reste l'autorité du cycle de vie ; l'inbox est le contrôle de vivacité.
- **À la fin** : rien à libérer côté contrôle (les juges sont des sous-agents éphémères) — poser une entrée `DONE` dans son propre inbox et clore.

---

## § COORDINATION DEV↔DEV (sur conflit détecté) [ORCHESTRÉ UNIQUEMENT]

Amorcée **par l'orchestrateur** quand deux devs en vol touchent des zones communes : il poste un `CONFLICT` dans l'inbox de chaque dev (`$WF/<A>.md`, `$WF/<B>.md`) nommant le fichier/domaine partagé et qui a la priorité. **Aucun fichier dédié** (`_pairs/` n'existe plus). Ensuite, **avant de toucher la zone chaude**, un dev poste un `CONFLICT` dans l'inbox de l'autre (`$WF/<autre>.md`) — « ce que je vais modifier, quand » — et lit son propre inbox pour la réponse. Pas de conflit détecté → pas de `CONFLICT`, pas de coordination.

---

## § CHECKLIST DONE FINALE — auditable [ORCHESTRÉ UNIQUEMENT]

Avant de clore, chaque surface `/dev`/`/plan` (mode orchestré) pose une entrée `DONE` dans l'**inbox orchestrateur** — trace qu'un audit relit :

```
~/.claude/scripts/cmux-tab.sh note --notify "$ORCH_SURFACE" "$WF/_inbox/orchestrator.md" "<T>[dev]" "DONE" \
  "MR=<lien> | pipeline=<#id verte, cité> | conflits GitLab=aucun/résolus | /end=fait | Approved=<par qui, postérieur au dernier repush> | merge=squash fait | JIRA=To Validate | juge=OK round <n>"
```

Un `DONE` ne se pose que si **chaque** item est réellement vrai et prouvé. Sinon → `BLOCKED` + raison, pas `DONE`.
