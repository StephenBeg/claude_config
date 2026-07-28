---
description: Interagit avec GitLab via glab CLI — auth, MRs, issues, pipelines, diffs.
---

# GitLab CLI Skill

Interagis avec GitLab en utilisant **`glab` CLI via Bash uniquement**. Le MCP GitLab est désactivé (il injectait ~250 tools dans chaque requête → coût contexte énorme). N'utilise jamais d'outils `gitlab_*` / `glab_*` MCP ; toutes les opérations passent par des commandes `glab ...` exécutées dans Bash.

## Entrée

$ARGUMENTS

Sans argument : demande ce que l'utilisateur veut faire (lister MRs, voir une MR, etc.).

## Workflow

### 0. Vérification prérequis

```bash
# Vérifier installation
glab --version

# Si non installé
brew install glab   # macOS
# ou: sudo apt install glab  # Linux

# Vérifier auth
glab auth status

# Si non authentifié — interactif (demander à l'utilisateur de lancer)
glab auth login --hostname gitlab.com
# Pour GitLab self-hosted Malt :
# glab auth login --hostname gitlab.maltpro.net
```

**Si `glab` n'est pas installé ou pas auth**, guide l'utilisateur étape par étape avant de continuer.

### 1. Fetch MRs

```bash
# Mes MRs assignées
glab mr list --assignee=@me

# MRs à reviewer
glab mr list --reviewer=@me

# Toutes les MRs ouvertes
glab mr list

# Voir une MR spécifique
glab mr view <number>

# Voir MR en JSON
glab mr view <number> --output=json

# Checkout local
glab mr checkout <number>
```

### 2. Fetch Issues

```bash
# Mes issues assignées
glab issue list --assignee=@me

# Issue spécifique
glab issue view <number>
```

### 3. Pipelines CI/CD

```bash
# Status pipeline courant
glab ci status

# Vue interactive
glab pipeline ci view

# Logs d'un job
glab ci trace

# Relancer pipeline
glab ci retry
```

### 4. API directe (avancé)

```bash
# Lister MRs d'un projet
glab api "projects/:id/merge_requests?state=opened&per_page=20"

# Diff d'une MR
glab api "projects/:id/merge_requests/<iid>/diffs"

# Discussions non résolues
glab api "projects/:id/merge_requests/<iid>/discussions?per_page=100" | \
  jq '[.[] | select(.notes[0].resolvable == true and .notes[0].resolved == false)]'

# Notes d'une MR
glab api "projects/:id/merge_requests/<iid>/notes?per_page=100"
```

### 5. MCP GitLab (si disponible)

Si les outils `gitlab_*` sont disponibles via MCP (`glab mcp serve`), utilise-les :

```
gitlab_get_merge_request(project_id, merge_request_iid)
gitlab_list_merge_request_diffs(project_id, merge_request_iid)
gitlab_list_merge_request_notes(project_id, merge_request_iid)
gitlab_get_project(project_id)
```

## Raccourcis utiles

| Action | Commande |
|--------|----------|
| Mes MRs | `glab mr list --assignee=@me` |
| À reviewer | `glab mr list --reviewer=@me` |
| Voir MR | `glab mr view <n>` |
| Checkout MR | `glab mr checkout <n>` |
| Approuver | `glab mr approve <n>` |
| Status CI | `glab ci status` |
| Mes issues | `glab issue list --assignee=@me` |

## Hors contexte git

```bash
# Spécifier le repo explicitement
glab mr list -R maltcommunity/malt
glab issue list -R maltcommunity/malt
```

## Output JSON pour parsing

```bash
glab mr list --output=json | jq '.[] | {iid: .iid, title: .title, author: .author.username}'
```

## Limites

- Ne merge, ne ferme, ne supprime jamais sans confirmation explicite.
- Si `glab` n'est pas installé : guide installation puis auth avant toute opération.
- Pour GitLab self-hosted Malt : `export GITLAB_HOST=gitlab.maltpro.net` ou `glab auth login --hostname gitlab.maltpro.net`.
