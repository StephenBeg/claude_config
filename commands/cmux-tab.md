---
description: Renomme l'onglet cmux de CLAUDE (pas celui de l'utilisateur) — phase de workflow ou titre libre. Le résumé décrit CE QU'ON FAIT, pas "impl du ticket X".
---

## Objectif

Manipuler le titre de l'onglet cmux **dans lequel tourne Claude**, via `~/.claude/scripts/cmux-tab.sh`.

Le script cible la surface du process courant (`CMUX_SURFACE_ID`), donc il renomme **toujours l'onglet de Claude**, jamais l'onglet actuellement au focus de l'utilisateur.

## Input

$ARGUMENTS

## Usage

```
~/.claude/scripts/cmux-tab.sh phase <PREFIX> "<résumé 3-4 mots>"
~/.claude/scripts/cmux-tab.sh set "<titre libre>"
~/.claude/scripts/cmux-tab.sh get
~/.claude/scripts/cmux-tab.sh spawn "<prompt>" ["<titre>"] ["<cwd>"] ["<status_dir>"] ["<ticket>"]
~/.claude/scripts/cmux-tab.sh report <status_dir> <ticket> <STATE> ["<detail>"]
~/.claude/scripts/cmux-tab.sh await  <status_dir> [--timeout <s>] [--interval <s>] <ticket> [<ticket>...]
~/.claude/scripts/cmux-tab.sh status <status_dir> [<ticket>]
```

`<PREFIX>` ∈ `PLAN | IMPL | TO REVIEW | END`.
`<STATE>` ∈ `SPAWNED | IN_PROGRESS | MR_OPEN | MERGED | BLOCKED`.

## `spawn` — nouvel onglet claude (opus 4.8) + prompt

`spawn` crée un **nouvel onglet dans le workspace COURANT** (`new-surface`, pas un nouveau workspace), y lance `claude --model claude-opus-4-8` avec le prompt fourni (via `send`), et lui donne le focus.

- `<prompt>` (requis) : envoyé tel quel à claude (shell-safe via `printf %q`).
- `<titre>` (optionnel, défaut `claude opus`) : nom de l'onglet.
- `<cwd>` (optionnel, défaut `~/Documents/projects/malt`) : working directory de l'onglet.
- `<status_dir>` + `<ticket>` (optionnels, **ORCHESTRATION**) : si fournis, `spawn` (1) **préfixe le prompt** d'un préambule qui apprend à l'enfant à reporter son statut via `report`, et (2) écrit immédiatement l'état `SPAWNED`. C'est le mode utilisé par le WORKFLOW DE PLAN pour superviser des tickets dépendants.

**RÈGLE ABSOLUE — cwd d'un spawn de WORKFLOW DE DEV = `~/Documents/projects/malt`.** Toute surface ouverte pour lancer un WORKFLOW DE DEV DOIT pointer sur le repo principal malt (c'est déjà le défaut du script). Jamais un worktree ni le `$PWD` du Claude appelant : l'agent de dev démarre dans le repo principal et y crée son propre worktree (cf. CLAUDE.md « GIT WORKFLOW »). Ne pas passer de `<cwd>` custom pour un spawn de dev — laisser le défaut.

Exemple :
```
~/.claude/scripts/cmux-tab.sh spawn "Analyse le module X et propose un refacto" "REFACTO X" ~/Documents/projects/malt
```

Usage : déléguer une tâche parallèle à une instance claude fraîche dans un onglet dédié, sans quitter la session courante.

### Ciblage du workspace (robustesse)

Le script résout le workspace de Claude **indépendamment du focus utilisateur** en re-mappant `$CMUX_WORKSPACE_ID` (UUID d'env stable, propre au process) vers son short ref `workspace:N` à chaque appel :
```
cmux workspace list --id-format both | grep -F "$CMUX_WORKSPACE_ID" | grep -o 'workspace:[0-9]*'
```
Re-mapper à chaque appel = robuste au réordonnancement des workspaces (le short ref bouge) ET indépendant du focus.

**PIÈGE — ne PAS utiliser `cmux identify --surface`** : la commande **ignore l'argument `--surface`** et renvoie toujours le bloc `focused` (= workspace au focus utilisateur). L'employer pour résoudre le workspace faisait ouvrir/renommer les surfaces dans le **mauvais workspace** dès que le focus bougeait.

Si un jour `spawn`/`phase` renvoie `workspace de Claude introuvable` : vérifier que `$CMUX_WORKSPACE_ID` est exporté et matche une ligne de `cmux workspace list --id-format both`. Fallback ultime = workspace `[selected]` (suit le focus, dernier recours).

### Fan-out WORKFLOW DE PLAN → GO IMPLEMENTATION (avec dépendances)

C'est l'outil du `GO IMPLEMENTATION` (voir CLAUDE.md « WORKFLOW DE PLAN »). Une fois les tickets JIRA créés et le GO reçu, le Claude de plan devient **orchestrateur superviseur** : il spawn les tickets **racines** (sans dépendance), écoute leurs statuts, et déclenche automatiquement les tickets dépendants quand leur(s) parent(s) sont `MERGED`.

**Spawn d'un ticket (mode orchestré) :**
```
~/.claude/scripts/cmux-tab.sh spawn \
  "<bloc PROMPT du ticket>. Ticket JIRA: TICKET-XXX. Suis le WORKFLOW DE DEV." \
  "TICKET-XXX <résumé>" \
  ~/Documents/projects/malt \
  "$STATUS_DIR" \
  TICKET-XXX
```

- `<prompt>` = le **bloc `PROMPT` (FR)** de la description du ticket + numéro JIRA + consigne de suivre le WORKFLOW DE DEV. (Le préambule "report ton statut" est ajouté automatiquement par `spawn` grâce à `status_dir`+`ticket`.)
- `<cwd>` = `~/Documents/projects/malt` (repo principal, obligatoire).
- `$STATUS_DIR` = dossier partagé de statuts, créé une fois par l'orchestrateur, ex. `/tmp/claude_plan_<EPIC>_status`.
- Chaque surface = un Claude Opus 4.8 autonome qui traite son ticket de bout en bout **et reporte son statut** via `report`.

**Boucle de supervision de l'orchestrateur :**
```
STATUS_DIR=/tmp/claude_plan_<EPIC>_status   # créer le dossier + header TMP_INDEX
# 1. spawn tous les tickets racines (DEPENDS_ON vide)
# 2. pour chaque ticket en vol : lancer un await EN BACKGROUND
~/.claude/scripts/cmux-tab.sh await "$STATUS_DIR" TICKET-XXX   # run_in_background: true
# 3. à chaque sortie d'un await (ticket MERGED), le harness re-réveille Claude :
#    - recalculer les tickets dont TOUS les DEPENDS_ON sont MERGED
#    - les spawn + lancer leur await en background
# 4. répéter jusqu'à drainage complet du DAG, puis stop (terminal laissé ouvert)
```

- **`await` DOIT tourner en background** (`run_in_background: true`) : il bloque parfois des heures ; le harness re-réveille Claude à sa sortie. Ne jamais l'appeler en foreground (cap 10 min du tool Bash).
- **`await` sort en code 3 si un ticket passe `BLOCKED`** → l'orchestrateur surface le blocage à l'utilisateur (onglet `[ASK]`) et NE spawn PAS les dépendants de ce ticket.
- Le Claude de plan ne s'arrête **qu'après drainage du DAG** (ou blocage), en laissant sa surface ouverte (logs relisibles).

### Protocole de statut (enfant ↔ orchestrateur)

Fichier `$STATUS_DIR/<TICKET>.status`, une ligne `STATE|timestamp|detail`, écriture atomique (rename). L'enfant (WORKFLOW DE DEV) appelle `report` à chaque transition :

| STATE | Quand (étape WORKFLOW DE DEV) | detail |
|---|---|---|
| `SPAWNED` | écrit automatiquement par `spawn` | ref surface |
| `IN_PROGRESS` | worktree + branche créés (étape 2) | — |
| `MR_OPEN` | MR créée (étape 6) | lien MR |
| `MERGED` | MR mergée par l'humain → To Validate (étape 11) | lien MR |
| `BLOCKED` | blocage nécessitant l'humain | raison |

L'orchestrateur lit ces états via `await` (bloquant) ou `status` (snapshot).

## RÈGLE ABSOLUE — le résumé décrit CE QU'ON FAIT

Le résumé (3-4 mots) doit décrire le **contenu réel** de la tâche, PAS répéter le mot "impl" ni le numéro de ticket seul.

- ❌ `IMPL BILL-2607 impl`
- ❌ `PLAN BILL-2607 ticket`
- ✅ `IMPL TRY PAR EVENTID`
- ✅ `PLAN RETRY WRITE DISCARDED`

Le résumé reste **identique** entre `PLAN` et `IMPL` ; seul le préfixe change.

## Comportement

1. Si `$ARGUMENTS` commence par un préfixe connu (`PLAN`/`IMPL`/`TO REVIEW`/`END`) → `phase <PREFIX> "<reste>"`.
2. Sinon, si `$ARGUMENTS` = `get` → afficher la surface courante.
3. Sinon → `set "<$ARGUMENTS>"` (titre libre).
4. Sans argument : déduire le préfixe de la phase de workflow en cours et un résumé de 3-4 mots décrivant le travail réel.

Si le résumé fourni ressemble à "impl"/"ticket"/juste un numéro → le remplacer par un vrai résumé du contenu du ticket.
