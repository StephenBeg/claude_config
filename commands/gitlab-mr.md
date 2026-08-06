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

### 4. Feedback de synthèse — FORMAT OBLIGATOIRE

Le feedback (chat ET commentaire général posté via `glab mr note <iid> -m "<corps>"`) suit **toujours** cette structure, dans cet ordre :

1. **Verdict binaire** : `✅ BONNE MR` ou `❌ MAUVAISE MR`. Un seul des deux, en tête, sans demi-mesure.
2. **Tableau PROS / CONS** : un tableau à deux colonnes listant les points positifs et négatifs. Un côté peut être vide — on peut très bien avoir **que des PROS** ou **que des CONS**. Ne pas forcer d'équilibre artificiel. **Chaque CON doit être accompagné d'une suggestion de fix concrète** (comment le corriger) — pas seulement le constat du problème.
3. **Cohérence conventions / architecture** : la MR respecte-t-elle les conventions et l'archi du repo ? Vérifier contre le code réel (patterns jumeaux, seeds/migrations existantes, modèles, contrats) — pas d'affirmation non vérifiée. Citer les `path:line` de référence.
4. **Résumé descriptif général** : un paragraphe qui explique ce que fait la MR, la cause racine si c'est un fix, et pourquoi le verdict — le feedback narratif complet.

Template :

```
## Review

## ✅ BONNE MR  (ou : ## ❌ MAUVAISE MR)

| ✅ PROS | ❌ CONS (+ suggestion de fix) |
|---|---|
| <point positif> | <point négatif> — **fix :** <correction proposée> |
| <point positif> | — |

### Cohérence conventions / architecture
<respect ou écart vs conventions du repo, avec path:line de référence vérifiés>

### Résumé
<paragraphe descriptif : ce que fait la MR, cause racine si fix, justification du verdict>
```

Règles :
- Le tableau accepte un côté vide (que des PROS, ou que des CONS) — c'est explicitement autorisé.
- Chaque affirmation de cohérence doit être **vérifiée contre le code réel** (déléguer l'exploration à un sous-agent si besoin), jamais supposée.
- Les findings bloquants/importants détaillés vont en commentaires inline (section 3) ; le tableau PROS/CONS les résume.

### 5. Clarté automatique

Abandonne caveman pour les commentaires postés sur la MR — écrire normalement pour que les autres reviewers comprennent sans contexte. Reprend caveman dans les réponses en chat.

## Limites

- Ne merge, ne ferme, ne rebranch jamais sans confirmation explicite.
- Ne modifie pas la description ni le titre de la MR sauf demande.
- Si le diff est trop large (500+ lignes), préviens et propose de se concentrer sur un sous-ensemble de fichiers.
- Si `glab` n'est pas installé ou pas authentifié, explique les étapes : `brew install glab` puis `glab auth login`.
