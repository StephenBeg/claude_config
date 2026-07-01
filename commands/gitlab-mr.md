---
description: Review une Merge Request GitLab — lit le diff, analyse le code, poste des commentaires ciblés et donne un verdict global.
---

Tu fais la review d'une MR GitLab via le MCP `gitlab` (serveur `glab mcp serve`).

## Entrée

$ARGUMENTS

Si aucun argument : demande l'URL ou le numéro de la MR et le projet GitLab (`namespace/repo`).

## Workflow

### 1. Récupération

```
gitlab_get_merge_request(project_id, merge_request_iid)
gitlab_list_merge_request_diffs(project_id, merge_request_iid)
gitlab_list_merge_request_notes(project_id, merge_request_iid)
```

Déduis `project_id` depuis l'URL (ex. `maltcommunity/malt` → URL-encodé si besoin) ou depuis le numéro passé.

### 2. Analyse du diff

Pour chaque fichier modifié, inspecte :
- **Correction** : bugs, cas limites, nulls non gérés, erreurs de logique
- **Sécurité** : injections, exposition de données, mauvaise gestion des permissions
- **Performance** : requêtes N+1, allocations inutiles, index manquants
- **Lisibilité** : nommage confus, duplication évitable, complexité inutile
- **Couverture** : comportements critiques sans test

### 3. Commentaires inline

Pour chaque finding significatif, poste un commentaire sur la ligne concernée :

```
gitlab_create_merge_request_note(
  project_id,
  merge_request_iid,
  body: "<finding concis>\n\n```suggestion\n<correction optionnelle>\n```",
  position: { ... }  # new_path, new_line
)
```

Format finding :
```
🔴 BLOQUANT / 🟡 IMPORTANT / 🔵 SUGGESTION : <problème en une phrase>. <raison>. <correction proposée>.
```

Ne poste pas de commentaire pour des détails stylistiques sans impact.

### 4. Commentaire général

Poste un commentaire de synthèse sur la MR :

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
- Si le MCP gitlab n'est pas disponible (glab non installé ou non auth), explique les étapes : `brew install glab` puis `glab auth login`.
