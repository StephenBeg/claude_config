# CMUX, procédure d'utilisation

Tout le pilotage de CMUX depuis Claude passe par un seul script, `scripts/cmux-tab.sh`. Le titre d'onglet, le bus d'échange entre surfaces et le réveil d'un agent en sont des sous-commandes.

## Modèle et adressage

Une `window` contient des `workspace` (un chantier, un onglet vertical), qui contiennent des `pane`, qui contiennent des `surface` (le terminal où tourne un Claude).

Une surface s'adresse par son UUID ou par un short ref `surface:N`. Le short ref est **positionnel** et se périme après une reprise de session, donc seul l'UUID est une adresse stable. La table de correspondance vit dans `~/claude-exchange-llm/_phase/<UUID>.json`.

Variables injectées dans chaque surface :

- `CMUX_SURFACE_ID` (alias `CMUX_PANEL_ID`), UUID de ma surface, cible de tous les appels.
- `CMUX_WORKSPACE_ID` (alias `CMUX_TAB_ID`), UUID du workspace.
- `CMUX_BUNDLED_CLI_PATH`, chemin du binaire (`/Applications/cmux.app/Contents/Resources/bin/cmux`).

## Où vivent les fichiers

| Fichier du repo | Destination | Rôle |
|---|---|---|
| `config/cmux/cmux.json` | `~/.config/cmux/cmux.json` | Réglages de l'app (JSONC, tout commenté = valeurs de Settings) |
| `config/ghostty/config` | `~/.config/ghostty/config` | Terminal (police, thème, keybinds, intégration shell) |
| `scripts/cmux-tab.sh` | `~/.claude/scripts/` | Wrapper unique de toutes les opérations CMUX |
| `scripts/wf-state.py` | `~/.claude/scripts/` | État de workflow par surface, rend le titre d'onglet |
| `scripts/wf-*-hook.sh` | `~/.claude/scripts/` | Hooks qui écrivent cet état sans intervention du LLM |
| `settings.hooks.json` | bloc `hooks` de `~/.claude/settings.json` | Câblage des hooks et des gates |
| `commands/orchestrator.md` | `~/.claude/commands/` | Workflow d'orchestration |
| `skills/malt-surface-exchange/` | `~/.claude/skills/` | Bus d'échange entre surfaces d'un chantier |

Deux dossiers d'état ne sont pas versionnés et ne doivent jamais être placés sous `/tmp`, que macOS purge sans prévenir :

- `~/claude-exchange-llm/_phase/<UUID>.json`, état de workflow d'une surface.
- `~/claude-exchange-llm/<EPIC>/`, bus d'échange d'un chantier orchestré.

`cmux reload-config` recharge `cmux.json` et la config Ghostty sans redémarrer l'app. Sauvegarder le fichier visé en `.bak` horodaté avant édition.

## Header d'onglet, usage solo

```
~/.claude/scripts/cmux-tab.sh topic "TRY PAR EVENTID"   # posé une fois, survit aux phases et à la compaction
~/.claude/scripts/cmux-tab.sh phase IMPL                # préfixe NU, les crochets sont posés par le script
~/.claude/scripts/cmux-tab.sh sync                      # recale le header sur la branche et la MR réelles
~/.claude/scripts/cmux-tab.sh state show                # dump de l'état persistant
~/.claude/scripts/cmux-tab.sh get                       # UUID de ma surface
```

Préfixes acceptés (un préfixe hors liste est refusé) : `ORCH`, `PLAN`, `IMPL`, `PIPE`, `MR`, `ASK`, `BLOCK`, `WAIT`, `CLEAN`, `END`, `JUGE`.

Les hooks posent seuls `[MR (n)]` à la création de MR, `[PIPE (n)]` au push, `[IMPL]` à la création du worktree, `[CLEAN]` au merge, et font sortir de `[ASK]`, `[BLOCK]` ou `[WAIT]` dès que l'utilisateur répond. Restent à la charge de la session : `PLAN`, `ASK`, `BLOCK`, `WAIT`, `END`, `JUGE` et le `topic`.

## Chantier orchestré

Un seul orchestrateur par workspace. Il possède tous les fichiers d'échange et il est le seul à spawner des surfaces.

```
WF=/Users/stephenbegot/claude-exchange-llm/<EPIC>
STATUS_DIR="$WF/_status"
mkdir -p "$STATUS_DIR" "$WF/_inbox"
ORCH_SURFACE="$CMUX_SURFACE_ID"

~/.claude/scripts/cmux-tab.sh phase ORCH "<résumé chantier>"
~/.claude/scripts/cmux-tab.sh pair-init "$WF/_inbox/orchestrator.md" <<'EOF'
INBOX ORCHESTRATEUR — les surfaces appendent ici STEP/DONE/BLOCKED.
EOF
```

Arborescence obtenue, un fichier inbox par surface, chacune n'écoutant que le sien :

```
~/claude-exchange-llm/<EPIC>/
├── _inbox/orchestrator.md    inbox fixe de l'orchestrateur
├── _status/                  STATUS_DIR lu par report et await
└── <TICKET>.md               inbox de la surface, et archive des verdicts de juge
```

Chaque ticket prêt se lance en trois appels, dans cet ordre. Le prompt de départ complet vit dans le header de l'inbox, le spawn ne transporte qu'un pointeur.

```
# (a) header de l'inbox, immuable, écrit une seule fois
~/.claude/scripts/cmux-tab.sh pair-init "$WF/<T>.md" <<EOF
[ORCHESTRATION] STATUS_DIR=$STATUS_DIR TICKET=<T> ORCH_SURFACE=$ORCH_SURFACE
Inbox, le tien : $WF/<T>.md · orchestrateur : $WF/_inbox/orchestrator.md
report --notify $ORCH_SURFACE à CHAQUE transition.
<champ Prompt du ticket> puis "Ticket JIRA: <T>. Suis le WORKFLOW DE DEV."
EOF

# (b) spawn, lien seul
S=$(~/.claude/scripts/cmux-tab.sh spawn "Lis $WF/<T>.md et exécute tes instructions." "<T> <résumé>")

# (c) le spawn n'écrit plus SPAWNED
~/.claude/scripts/cmux-tab.sh report "$STATUS_DIR" <T> SPAWNED "surface=$S"
```

`spawn` ouvre la surface dans le workspace courant, avec `~/Documents/projects/malt` pour cwd (jamais un worktree) et le modèle `claude-opus-5[1m]`, surchargeable par `CMUX_SPAWN_MODEL`.

Côté surface enfant, chaque transition de cycle de vie et chaque étape se reportent :

```
~/.claude/scripts/cmux-tab.sh report --notify "$ORCH_SURFACE" "$STATUS_DIR" <T> MR_OPEN "<lien MR>"
~/.claude/scripts/cmux-tab.sh note --notify "$ORCH_SURFACE" "$WF/_inbox/orchestrator.md" \
  "<T>[dev]" "STEP:impl" "TDD rouge puis vert sur try par eventId"
```

`STATE` vaut `SPAWNED`, `IN_PROGRESS`, `MR_OPEN`, `MERGED`, `PLANNED` ou `BLOCKED`. L'état terminal est `MERGED` pour un ticket d'implémentation et `PLANNED` pour un spike de planification.

`note` prend exactement `<inbox_file> <LABEL> <EVENT> [detail]`, seul `--notify` peut le précéder. Un premier argument commençant par `-` décale tous les autres, affiche le contenu comme si tout allait bien, et écrit un fichier portant le nom du LABEL dans le répertoire courant.

L'orchestrateur ne poll pas et ne lance aucun waiter. Il rend la main, les enfants le réveillent, et un cron `*/13` sert de filet. À chaque réveil il reconstruit l'état depuis JIRA, git et `$STATUS_DIR`, jamais depuis le contenu du message de réveil.

## Réveiller une surface déjà lancée

```
~/.claude/scripts/cmux-tab.sh wake [--force] <UUID> "<message mono-ligne>"
```

Le wrapper attend que la cible ne soit plus `running`, envoie le texte puis la touche Entrée, retente trois fois, et refuse d'émettre en heures calmes (code 4). En direct avec le binaire, le `\n` doit être la séquence littérale antislash + n, pas un vrai octet de saut de ligne :

```
CMUX_QUIET=1 /Applications/cmux.app/Contents/Resources/bin/cmux send --surface "<UUID>" '<msg>\n'
```

Un ordre qui doit arrêter quelque chose s'écrit **d'abord** dans l'inbox avec `note`, le réveil ne vient qu'ensuite. Un `exit 0` de `send` prouve l'envoi, jamais la lecture.

## Pièges vérifiés

- `cmux identify --surface` ignore son argument et rend toujours le bloc focused, donc il ne sert pas à résoudre son propre workspace.
- Un `surface:N` mémorisé cesse de désigner la bonne surface après une reprise de session, et l'échec de `wake` qui en résulte est annoncé comme non fatal.
- `cmux workspace list` se bloque par intermittence au delà d'une vingtaine de surfaces, ce qui fait échouer `spawn` de façon aléatoire.
- Un `spawn` qui dépasse les 120 s du tool Bash a pu réussir. Vérifier `[ -s "$STATUS_DIR/<T>.status" ]` avant tout nouveau spawn, sinon deux agents écrivent sur la même branche.
- Une surface muette n'est pas morte, un démarrage trois heures après le spawn a déjà été observé. Avant un respawn, renommer l'ancien inbox en `<T>.dead-<surface>.md`.
- `cmux list-panels` ne montre que le workspace courant, il ne dit rien de la charge de la machine.
- `cmux notify`, `set-status` et `trigger-flash` n'agissent que sur l'interface, jamais sur l'agent.
- `await` et `await-note` restent dans le script pour compatibilité, mais le harness tue ces process sans garantie.
- `~/tmp/scratch` est partagé par toutes les surfaces, isoler par chantier sous `$HOME/tmp/scratch/<WORKFLOW>/`, en écrivant `$HOME` et non le tilde que le gate refuse.
