---
description: Crée un commit contextualisé — vérifie le worktree (et en crée un si absent), puis commit avec un message adapté au contexte de la session.
---

## Objectif

Créer un commit propre avec un message adapté au contexte de la session.
Ne jamais push — c'est toujours l'humain qui push.

## Input

$ARGUMENTS

Si un argument est fourni, l'utiliser comme message de commit (ou comme hint pour le générer).

## Workflow

### 1. Vérifier la branche courante

```bash
git branch --show-current
```

### 2. Si sur `master` — créer un worktree dédié

Si la branche est `master` :
- Demander à l'utilisateur le nom de ticket/branche cible si pas évident depuis le contexte
- Créer le worktree **hors du repo**, **base `origin/master`** (cf. CLAUDE.md GIT WORKFLOW — sans `origin/master`, git prend le HEAD courant) :
  ```bash
  git fetch origin master
  git worktree add ~/worktrees/malt/TICKET -b TICKET-description origin/master
  ```
- Travailler depuis ce worktree pour la suite
- Rappeler à l'utilisateur qu'il faudra push depuis ce worktree

Si déjà sur une branche feature : continuer directement.

### 3. Analyser les changements

```bash
git status
git diff --stat
git diff
```

Identifier :
- Fichiers modifiés / ajoutés / supprimés
- Portée fonctionnelle des changements (feature, fix, refactor, test, chore...)
- Ticket associé (depuis le nom de branche ou le contexte de session)

### 4. Générer le message de commit

Format conventionnel :
```
<type>(<scope>): <résumé concis en anglais>
```

Types : `feat`, `fix`, `test`, `refactor`, `chore`, `docs`

Exemples :
- `test(netsuite-rest-auth): add encode() edge-case coverage (RFC 3986)`
- `fix(netsuite-client-router): use Kotlin by delegation (Sonar S6517)`
- `feat(deposit-idempotency): add NS-side depositExists guard`

Règles :
- Message en anglais
- Pas de co-author Claude
- Pas de "Added by AI" ou équivalent
- Scope = module ou composant principal touché

### 5. Stager et committer

```bash
git add <fichiers pertinents>
git commit -m "<message généré>"
```

Préférer `git add <fichiers>` explicite à `git add -A` pour éviter d'inclure des fichiers sensibles ou non liés.

### 6. Confirmer

Afficher le résultat de `git log --oneline -3` pour que l'utilisateur voie le commit.
Rappeler : **ne pas push** — c'est à l'utilisateur de faire `git push origin <branche>`.

## Limites

- **Jamais de `git push`** dans ce skill.
- Si les changements touchent plusieurs tickets distincts, proposer de splitter en plusieurs commits.
- Si aucun changement détecté (`git status` clean), informer l'utilisateur et ne rien faire.
- Jamais ajouter `Co-Authored-By: Claude` ou toute variante dans le commit.
