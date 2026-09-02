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

### 3. Commentaires inline — STYLE OBLIGATOIRE

**Une seule phrase. Le constat, rien d'autre.** Tu écris comme l'utilisateur : un pair qui relit vite et pointe du doigt. Pas comme un rapport d'audit.

Le raisonnement qui t'a mené au finding reste **dans le chat**, pas sur la MR. L'auteur connaît son code : lui dire ce qui cloche suffit, il en déduit le pourquoi tout seul. Un commentaire long se fait répondre « that's quite a long/verbose comment » et noie les vrais problèmes.

**Forme :**
- 1 phrase, minuscule initiale, ton parlé. Une question directe (`amount ? should be currencyCode`) vaut mieux qu'une affirmation.
- **Zéro** : préfixe de sévérité (🔴/🟡/🔵), titre en gras, liste à puces, section « Fix : », justification, paragraphe d'explication.
- Le backtick pour tout identifiant. Deuxième proposition tolérée **seulement** si elle porte une preuve (`path:line`, valeur observée), jamais une explication.
- Bloc `suggestion` GitLab dès qu'une correction tient sur les lignes visées — la suggestion PORTE le fix, la phrase se contente du constat.
- La sévérité se lit à la nature du problème, pas à une étiquette. Si une seule phrase ne suffit pas à faire comprendre, c'est un point à porter dans la note de synthèse, pas un pavé inline.

**Exemples calibrés** (tous réels, tous acceptés) :
```
amount ? should be currencyCode
`hours` is ignored, it is hardcoded to 1
the `= null` is still there, you removed it on `findAggregateIdWithPendingSimulation` instead
most recent by what ? say executionDate, not occurredAt
why not stub `findLast...` too ? it silently returns null here instead of throwing like the others
```

Contre-exemple à ne jamais produire : `🔴 BLOQUANT : the index does not serve the query.` suivi de trois paragraphes d'analyse et d'une section fix.

Ne poste rien pour un détail stylistique sans impact.

**Poster** (API discussions, il faut les 3 SHA — les prendre sur la **dernière** version, `mr view` peut servir une version périmée après un repush) :

```bash
glab api "projects/:id/merge_requests/<iid>/versions" \
  | python3 -c "import json,sys; d=json.load(sys.stdin)[0]; print(d['base_commit_sha'], d['head_commit_sha'], d['start_commit_sha'])"

glab api --method POST "projects/:id/merge_requests/<iid>/discussions" \
  -H "Content-Type: application/json" --input - <<'JSON'
{
  "body": "<une phrase>\n\n```suggestion\n<correction optionnelle>\n```",
  "position": {
    "position_type": "text",
    "base_sha": "<base>", "head_sha": "<head>", "start_sha": "<start>",
    "new_path": "<path>", "new_line": <line>
  }
}
JSON
```

Vérifier le `new_line` contre le **fichier réel** de la révision, jamais contre un comptage de hunk :
`glab api "projects/:id/repository/files/<path-urlencodé>/raw?ref=<head_sha>" | grep -n "<ancre>"`.

Supprimer un de tes commentaires : `glab api --method DELETE "projects/:id/merge_requests/<iid>/discussions/<discussion_id>/notes/<note_id>"`.

### 4. Feedback de synthèse — FORMAT OBLIGATOIRE

**Deux destinataires, deux longueurs.** La structure complète ci-dessous est pour **le chat** (l'utilisateur, qui veut le raisonnement). Ce qui est **posté sur la MR** est la version condensée décrite en fin de section — même verdict, mêmes findings, sans le narratif.

Structure du feedback **en chat**, dans cet ordre :

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

**Version postée sur la MR** (`glab mr note create <iid> -m "<corps>"`) — quelques lignes, pas de tableau, pas de narratif :

```
Verdict en une ligne.

<Ce qui bloque : 1 à 3 phrases max, une par problème, chacune renvoyant au commentaire inline qui le porte.>

<Le reste, tout mineur : "N commentaires inline ci-dessus (<3-4 mots par point>)".>

<État de la pipeline si pertinent.>
```

Le détail vit dans les commentaires inline. La note générale ne fait que hiérarchiser.

### 5. Round de recheck

Quand on te redemande une review après corrections : refetch le diff **et** les réponses de l'auteur (`notes?sort=asc`), puis poste une note courte structurée en trois temps — **corrigé** (une phrase de liste), **tu avais raison / j'avais tort** le cas échéant, **reste**. Ne repose pas les findings déjà clos, ne réécris pas la synthèse complète.

Quand l'auteur réfute un finding avec un argument valable, le dire explicitement et retirer le finding — c'est plus utile qu'une défense. Vérifier son argument contre le code avant de céder comme avant d'insister.

Si la pipeline est rouge, lire la vraie cause avant de la reporter (jobs enfants via `/bridges`, puis `trace`) : un `Quality Gate check timeout exceeded` alors que le trace conclut `quality gate status is OK` est un flake d'infra, pas un défaut de la MR — le signaler comme tel.

### 6. Clarté automatique

Abandonne caveman pour ce qui est posté sur la MR — écrire normalement, en **anglais**, pour que les autres reviewers comprennent sans contexte. « Normalement » veut dire lisible, pas verbeux : la contrainte d'une phrase de la section 3 reste prioritaire. Reprends caveman dans les réponses en chat.

## Limites

- Ne merge, ne ferme, ne rebranch jamais sans confirmation explicite.
- Ne modifie pas la description ni le titre de la MR sauf demande.
- Si le diff est trop large (500+ lignes), préviens et propose de se concentrer sur un sous-ensemble de fichiers.
- Si `glab` n'est pas installé ou pas authentifié, explique les étapes : `brew install glab` puis `glab auth login`.
