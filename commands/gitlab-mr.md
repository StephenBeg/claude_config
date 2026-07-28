---
description: Review une Merge Request GitLab — lit le diff, analyse le code, poste des commentaires ciblés et donne un verdict global.
---

Tu fais la review d'une MR GitLab via **`glab` CLI (Bash)**. Le MCP GitLab est désactivé — n'utilise jamais d'outils `gitlab_*` / `glab_*`.

## Entrée

$ARGUMENTS

Si aucun argument : demande l'URL ou le numéro de la MR et le projet GitLab (`namespace/repo`).

## Workflow

### 1. Récupération

```bash
glab mr view <iid> -R <namespace/repo> --output=json      # metadata + description
glab mr diff <iid> -R <namespace/repo>                      # diff complet
glab api "projects/:id/merge_requests/<iid>/notes?per_page=100" --paginate   # notes existantes
```

`-R <namespace/repo>` est optionnel si tu es déjà dans le repo. Déduis l'iid et le repo depuis l'URL passée.

### 2. Analyse du diff

Pour chaque fichier modifié, inspecte :
- **Correction** : bugs, cas limites, nulls non gérés, erreurs de logique
- **Sécurité** : injections, exposition de données, mauvaise gestion des permissions
- **Performance** : requêtes N+1, allocations inutiles, index manquants
- **Lisibilité** : nommage confus, duplication évitable, complexité inutile
- **Couverture** : comportements critiques sans test

### 3. Commentaires inline

Pour chaque finding significatif, poste un commentaire sur la ligne concernée :

Commentaire inline (ancré à une ligne du diff) via l'API discussions — il faut les 3 SHA :

```bash
# récupérer base_sha / head_sha / start_sha
glab mr view <iid> --output=json | grep -oP '"(base_sha|head_sha|start_sha)":\s*"\K[0-9a-f]{40}'

glab api --method POST "projects/:id/merge_requests/<iid>/discussions" \
  -H "Content-Type: application/json" --input - <<'JSON'
{
  "body": "<finding concis>\n\n```suggestion\n<correction optionnelle>\n```",
  "position": {
    "position_type": "text",
    "base_sha": "<base>", "head_sha": "<head>", "start_sha": "<start>",
    "new_path": "<path>", "new_line": <line>
  }
}
JSON
```

Format finding :
```
🔴 BLOQUANT / 🟡 IMPORTANT / 🔵 SUGGESTION : <problème en une phrase>. <raison>. <correction proposée>.
```

Ne poste pas de commentaire pour des détails stylistiques sans impact.

### 4. Commentaire général

Poste un commentaire de synthèse sur la MR via `glab mr note <iid> -m "<corps>"` :

```
## Review

**Verdict** : ✅ Approuvé / ⚠️ Approuvé avec réserves / ❌ Changements requis

**Résumé** : [2-3 phrases sur le contenu de la MR]

**Points bloquants** : [liste ou "aucun"]

**Points importants** : [liste ou "aucun"]

**Suggestions** : [liste ou "aucun"]

**Ce qui est bien** : [1-2 points positifs sincères]
```

### 5. Clarté automatique

Abandonne caveman pour les commentaires postés sur la MR — écrire normalement pour que les autres reviewers comprennent sans contexte. Reprend caveman dans les réponses en chat.

## Limites

- Ne merge, ne ferme, ne rebranch jamais sans confirmation explicite.
- Ne modifie pas la description ni le titre de la MR sauf demande.
- Si le diff est trop large (500+ lignes), préviens et propose de se concentrer sur un sous-ensemble de fichiers.
- Si `glab` n'est pas installé ou pas authentifié, explique les étapes : `brew install glab` puis `glab auth login`.
