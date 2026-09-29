---
name: malt-surface-exchange
description: Bus d'echange entre surfaces CMUX d'un chantier ORCHESTRE — arborescence par workflow, inbox par surface, reveil par push actif, spawn par lien, notification, coordination dev<->dev, checklist DONE. A n'invoquer QUE si le header porte [ORCHESTRATION] : inutile en solo. Ne couvre pas le juge (skill malt-judge-loop).
---

# Surface exchange — inbox par nœud

Rend les échanges entre surfaces CMUX d'un chantier **auditables** (journal immuable sur disque) au lieu d'un contrôle one-shot noyé dans le contexte qui a produit le travail.

**Le juge n'est PAS une surface CMUX** (protocole complet : skill `malt-judge-loop`). Plus d'inbox juge, plus de `/judge`, plus de monitor à surveiller : le loop juge vit entièrement dans la surface qui demande le verdict, et le **compte rendu de chaque juge est écrit dans le fichier de cette surface** (`SURFACE_FILE`, résolu ici § ARBORESCENCE / § QUI CRÉE QUOI).

**Modèle = un fichier INBOX par SURFACE (nœud), PAS un fichier par paire.** Chaque surface possède exactement UN fichier — sa boîte de réception append-only — et **n'écoute QUE ce fichier**. Pour solliciter une autre surface, on **append dans l'inbox du destinataire** ; la réponse revient **dans l'inbox du demandeur**. L'orchestrateur n'a donc qu'**un seul fichier fixe** à surveiller par workspace.

**Mécanisme = PUSH ACTIF + RE-SCAN IDEMPOTENT.** Une surface qui progresse **réveille elle-même** son destinataire (`--notify`, § RÉVEIL) ; personne ne poll. Et tout réveil manqué est rattrapé par un **re-scan depuis la source de vérité** — jamais par une relance humaine. **Le verdict du juge n'utilise AUCUN de ces mécanismes** : c'est un appel de sous-agent synchrone (skill `malt-judge-loop`).

Toutes les sections sont des **RÈGLES ABSOLUES**.

**QUAND CHARGER CE SKILL — porte d'entrée.** Uniquement si le header de mon inbox porte `[ORCHESTRATION]`. **En solo (`/dev`, `/hotfix`, `/plan` sans ce header), ce skill ne s'applique pas du tout** : le seul chemin dont le solo a besoin (`SURFACE_FILE` sous `_solo/`) est donné par `malt-judge-loop`. Ne pas le charger « au cas où ».

---

## § RÉVEIL — push actif d'abord, re-scan idempotent comme socle (RÈGLE ABSOLUE)

**Trois couches, dans cet ordre.**

**1. PUSH ACTIF (nominal).** La surface qui progresse **réveille** son destinataire en lui injectant un prompt : `cmux send` + `send-key enter` réveille un Claude au repos (~4 s) et met en file, sans corrompre le tour, un Claude occupé.

```
# enfant → orchestrateur, à CHAQUE transition de cycle de vie :
~/.claude/scripts/cmux-tab.sh report --notify "$ORCH_SURFACE" "$STATUS_DIR" <T> <STATE> "<detail>"
# enfant → orchestrateur, à chaque étape (couplé au header CMUX, § NOTIFICATION) :
~/.claude/scripts/cmux-tab.sh note --notify "$ORCH_SURFACE" "$WF/_inbox/orchestrator.md" "<T>[dev]" "STEP:<nom>" "<preuve>"
# dev A → dev B (conflit) : --notify <surface de B>
```
`$ORCH_SURFACE` (UUID de la surface orchestrateur) est **transmis dans le header de l'inbox** de chaque surface, au même titre que `STATUS_DIR` (§ QUI CRÉE QUOI). Sans lui, `--notify` est simplement omis (dégradation propre : on retombe sur la couche 3).

**Le push est best-effort par construction.** Un `wake` envoyé pendant la bascule de fin de tour de la cible peut être perdu ; `wake_surface()` attend donc que la cible ne soit plus `running` (index `~/.cmuxterm/claude-hook-sessions.json`, max 40 s). Cela réduit la fenêtre sans la fermer → les couches 2 et 3 ne sont pas optionnelles.

**2. FILET PÉRIODIQUE (secours).** L'orchestrateur pose **un** cron de re-scan (`/orchestrator` step 7b). Il couvre le cas « le push n'est jamais parti » (surface fermée, `wake` en échec, heures calmes).

**3. RE-SCAN IDEMPOTENT (socle — ne ment jamais).** Source de vérité = **JIRA + git + le `STATUS_DIR` durable**, JAMAIS la mémoire ni un process vivant. À chaque réveil, quelle qu'en soit la cause, l'orchestrateur **reconstruit** l'état complet (`/orchestrator` step 9). Conséquence assumée : **un réveil manqué coûte du temps, jamais de l'information.**

**Ce qui NE marche PAS — ne pas y revenir :**
- Les process bash background (`await`, `await-note`, boucles de polling) sont **tués sans garantie** par le harness (observé : lots de 5-8, parfois quelques secondes après lancement). Ils restent dans le script pour compatibilité mais **ne sont plus le mécanisme de réveil**. Un `await` tué notifie « killed » sans l'info de transition → réveil aveugle, ou pas de réveil du tout.
- **Détacher** le waiter (`nohup`/`setsid`/`disown`) le fait survivre **mais il ne réveille plus jamais l'agent**. Piège connu, interdit.
- `cmux notify` / `set-status` / `trigger-flash` sont **purement UI** : aucun effet sur le process agent.
- `STATUS_DIR` sous `/tmp` : **purgé par macOS** en cours de chantier (le script avertit).

**HEURES CALMES 20h–7h** : un `wake` ré-invoque Claude → `cmux-tab.sh wake` **refuse d'envoyer** dans la plage (sort en code 4) et l'appelant continue normalement. L'info reste sur disque ; la couche 3 la récupère au redémarrage manuel du matin.

---

## § ARBORESCENCE — un dossier par workflow, un inbox par surface

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

Une surface obtient tout ce dont elle a besoin en lisant SON inbox ; l'orchestrateur a UN inbox fixe. **Aucun inbox juge, aucun fichier de paire.** La coordination dev↔dev passe par les inbox des devs eux-mêmes (§ COORDINATION DEV↔DEV).

**Cas SOLO (pas d'orchestrateur).** Le loop juge s'applique **aussi en solo** : la surface se donne un fichier de surface sous `$WF` avec `WORKFLOW=_solo` — soit `SURFACE_FILE=/Users/stephenbegot/claude-exchange-llm/_solo/<TICKET>.md`. Le créer si absent (`mkdir -p` + `pair-init` avec un header d'une ligne : ticket + mode solo). C'est là que les comptes rendus des juges sont archivés. Aucun autre inbox n'existe en solo.

---

## § ANATOMIE D'UN INBOX — header + journal append-only

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

## § QUI CRÉE QUOI — l'orchestrateur possède les inbox

**L'orchestrateur crée et header TOUS les inbox.** Aucune autre surface ne crée d'inbox (elles n'appendent qu'aux journaux d'inbox déjà créés).

| Inbox | Créé + headeré par | Header contient |
|---|---|---|
| `$WF/_inbox/orchestrator.md` | Orchestrateur, au démarrage du workflow | header minimal (rôle du canal) |
| `$WF/<T>.md` | Orchestrateur, **avant** le spawn de T (dev ET plan) | le **prompt de départ complet** de la surface T (checkpoint juge unique attendu — détail skill `malt-judge-loop` — : dev=pre-push · hotfix=hotfix-verify · plan=plan-gate) |

En **solo**, il n'y a pas d'orchestrateur : la surface crée elle-même son `SURFACE_FILE` sous `_solo/` (§ ARBORESCENCE, cas SOLO) au moment du premier round de juge.

---

## § SPAWN = LIEN SEUL — tout le prompt vit dans l'inbox de la surface

`cmux-tab.sh spawn` ne construit **aucun préambule** : le prompt de départ est **déjà** dans le header de l'inbox `$WF/<T>.md`. Le spawn ne transporte qu'un **pointeur** :

```
~/.claude/scripts/cmux-tab.sh spawn \
  "Lis $WF/<T>.md et exécute tes instructions." \
  "<T> <résumé>"
```

**Il n'y a plus de surface juge à spawner** : chaque surface lance son propre sous-agent `judge` au checkpoint (skill `malt-judge-loop`).

Séquence orchestrateur pour chaque surface (dev ou plan) :
1. `pair-init "$WF/<T>.md"` — écrire le header (= prompt de départ).
2. `spawn "Lis $WF/<T>.md et exécute…" "<T> …"` → récupère `surface:N`.
3. `report "$STATUS_DIR" <T> SPAWNED "surface=$surface"` (le spawn ne l'écrit plus).

**Plus de `pair-init` de fichier juge, plus d'annonce `PAIR-ADDED`, plus de surface juge** : un nouveau ticket est absorbé sans aucun câblage de contrôle.

---

## § ANNONCE DES CHEMINS AU DÉMARRAGE — OBLIGATOIRE

Dès sa 1re étape, **toute surface CMUX** (dev/plan/hotfix, ainsi que l'orchestrateur pour son propre inbox) **affiche à l'utilisateur, en clair et en chemin ABSOLU**, l'inbox qu'elle écoute et ceux où elle poste, pour qu'il puisse les **ouvrir en side dans cmux** :

```
📂 Fichiers d'échange (ouvre en side dans cmux) :
  • mon inbox (j'écoute, + comptes rendus des juges) : $WF/<T>.md
  • → orchestrateur (je poste)                       : $WF/_inbox/orchestrator.md
```

L'orchestrateur affiche son **propre** inbox. En **solo**, afficher le seul `SURFACE_FILE` (`…/_solo/<TICKET>.md`) dès le premier round de juge.

## § NOTIFICATION À CHAQUE ÉTAPE — OBLIGATOIRE (couplée au header CMUX)

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

## § RÔLE DE L'ORCHESTRATEUR (côté /orchestrator)

- **Créer l'arbre du workflow** au démarrage : `WF=/Users/stephenbegot/claude-exchange-llm/<EPIC>` ; `mkdir -p "$WF/_inbox"` ; `pair-init "$WF/_inbox/orchestrator.md"` (header minimal). **Aucun inbox juge, aucune surface juge à spawner.**
- **Pour chaque ticket spawné** (racine ou capté au RESCAN, dev ET plan) : `pair-init "$WF/<T>.md"` (header = prompt de départ, incluant le checkpoint juge attendu) ; puis `spawn "Lis $WF/<T>.md et exécute…" "<T> …"` (lien seul) ; puis `report SPAWNED`. **Aucun câblage juge** — la surface lance son propre sous-agent `judge`.
- **Détection de conflit** : si le DAG révèle des zones chaudes communes entre deux devs en vol, poster un `CONFLICT` dans l'inbox de chacun (`$WF/<A>.md` et `$WF/<B>.md`) décrivant le fichier/domaine partagé et qui coordonne (§ COORDINATION DEV↔DEV).
- **Écoute** : **PASSIVE** (§ RÉVEIL). L'orchestrateur ne poll pas et ne lance pas de waiter background : il est **réveillé par push** par les surfaces (`report --notify` / `note --notify`) et, à défaut, par son **cron de re-scan**. À chaque réveil il relit son inbox `$WF/_inbox/orchestrator.md` + le `STATUS_DIR` + JIRA. Répondre/instruire une surface = poster dans son inbox `$WF/<T>.md` **avec `--notify <surface de T>`**.
- **Transmettre son propre UUID de surface** (`cmux-tab.sh get` → `$CMUX_SURFACE_ID`) dans le header `ORCH_SURFACE=` de chaque inbox qu'il crée — sinon aucun enfant ne peut le réveiller.
- **Au RESCAN** : lire l'inbox orchestrateur (flux `STEP` agrégé) pour vérifier que les surfaces en vol **progressent**. Une surface muette anormalement longtemps = potentiellement bloquée → la surfacer. Le `report`/`await` du STATUS_DIR reste l'autorité du cycle de vie ; l'inbox est le contrôle de vivacité.
- **À la fin** : rien à libérer côté contrôle (les juges sont des sous-agents éphémères) — poser une entrée `DONE` dans son propre inbox et clore.

---

## § COORDINATION DEV↔DEV (sur conflit détecté)

Amorcée **par l'orchestrateur** quand deux devs en vol touchent des zones communes : il poste un `CONFLICT` dans l'inbox de chaque dev (`$WF/<A>.md`, `$WF/<B>.md`) nommant le fichier/domaine partagé et qui a la priorité. **Aucun fichier dédié** (`_pairs/` n'existe plus). Ensuite, **avant de toucher la zone chaude**, un dev poste un `CONFLICT` dans l'inbox de l'autre (`$WF/<autre>.md`) — « ce que je vais modifier, quand » — et lit son propre inbox pour la réponse. Pas de conflit détecté → pas de `CONFLICT`, pas de coordination.

---

## § CHECKLIST DONE FINALE — auditable

Avant de clore, chaque surface `/dev`/`/plan` (mode orchestré) pose une entrée `DONE` dans l'**inbox orchestrateur** — trace qu'un audit relit :

```
~/.claude/scripts/cmux-tab.sh note --notify "$ORCH_SURFACE" "$WF/_inbox/orchestrator.md" "<T>[dev]" "DONE" \
  "MR=<lien> | pipeline=<#id verte, cité> | conflits GitLab=aucun/résolus | /end=fait | Approved=<par qui, postérieur au dernier repush> | merge=squash fait | JIRA=To Validate | juge=OK round <n>"
```

Un `DONE` ne se pose que si **chaque** item est réellement vrai et prouvé. Sinon → `BLOCKED` + raison, pas `DONE`.
