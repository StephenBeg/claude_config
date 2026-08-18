---
name: jira-done
description: Use when finishing a development task — posts a comment on the Jira ticket summarising what was done, then transitions it to In Review (MR open) or Done (MR merged).
---

# Jira Done — clore un ticket après livraison

Met à jour le ticket Jira de la session : commentaire résumé + transition de statut.

## Workflow

### 1. Identifier le ticket

Cherche dans cet ordre :
1. Titre de la session (format `TICKET-123 ...`)
2. Nom de la branche git courante (`git branch --show-current`)
3. Messages de commits récents (`git log --oneline -5`)

Extrait le ticket ID (ex: `BILL-2443`). Si ambigu, demande.

### 2. Déterminer le statut cible

```bash
# MR mergée ?
glab mr list --merged --source-branch $(git branch --show-current) --output json | head -5
```

- MR mergée → statut cible : **Done**
- MR ouverte / branche pushée → statut cible : **In Review**
- Pas encore pushé → statut cible : **In Review** (demander confirmation)

### 3. Rédiger le commentaire

En anglais. Format :

```
## Done

<1-3 bullet points: ce qui a été fait, pourquoi>

**Branch:** `<branch-name>`
**MR:** <url si disponible, sinon omis>
**Feature flag:** <flag name ou None>
```

Tirer le contenu du contexte de la session (commits, conversation, plan). Ne pas inventer.

### 4. Poster le commentaire

```
mcp__atlassian__addCommentToJiraIssue
  cloudId: "aca47d88-0bd1-419a-bb78-2e7aeb2ce594"
  issueIdOrKey: "<TICKET-ID>"
  commentBody: "<commentaire>"
  contentFormat: "markdown"
```

### 5. Trouver et appliquer la transition

```
mcp__atlassian__getTransitionsForJiraIssue
  cloudId: "aca47d88-0bd1-419a-bb78-2e7aeb2ce594"
  issueIdOrKey: "<TICKET-ID>"
```

Cherche dans les transitions disponibles :
- Pour **In Review** : transition dont le nom contient "Review", "Code Review", "In Review"
- Pour **Done** : transition dont le nom contient "Done", "Closed", "Terminé"

Si plusieurs candidats, prends le plus spécifique. Si aucun ne correspond, liste les transitions et demande à l'utilisateur.

```
mcp__atlassian__transitionJiraIssue
  cloudId: "aca47d88-0bd1-419a-bb78-2e7aeb2ce594"
  issueIdOrKey: "<TICKET-ID>"
  transition: { id: "<transition-id>" }
```

### 6. Confirmer

Affiche :
- Ticket mis à jour : lien `https://malt-community.atlassian.net/browse/<TICKET-ID>`
- Statut → `<nouveau statut>`

## Erreurs fréquentes

| Problème | Solution |
|---|---|
| Ticket non trouvé | Vérifier le format (BILL-2443 pas bill-2443) |
| Transition non disponible | Afficher toutes les transitions disponibles, demander |
| Pas de MR trouvée | Utiliser "In Review" par défaut |
| cloudId invalide | Utiliser `aca47d88-0bd1-419a-bb78-2e7aeb2ce594` (malt-community.atlassian.net) |
