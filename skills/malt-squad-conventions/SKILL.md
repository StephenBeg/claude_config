---
name: malt-squad-conventions
description: Conventions de squad Malt appliquées par /dev /plan /hotfix — labels JIRA et GitLab obligatoires, EPIC/domaine par défaut. Squad courante = Accounting/Bookkeeping. À charger dès qu'un workflow crée un ticket JIRA ou une MR (pour poser les bons labels). Changer de squad = éditer CE seul fichier ; les workflows restent inchangés.
---

# Conventions de squad — courante : **Accounting / Bookkeeping**

Les workflows (`/dev`, `/plan`, `/hotfix`) sont **domain-agnostic** : ils lisent d'ici les labels et le domaine par défaut. Travailler sur une autre squad = mettre à jour ce fichier (labels + EPIC), rien d'autre à toucher.

## Labels obligatoires

- **JIRA** — tout ticket créé (EPIC, User Story, SPIKE, tâche, bug, ticket de travail découvert) porte le label **`Accounting/Bookkeeping`** dès la création :
  ```json
  {"fields":{"labels":["Accounting/Bookkeeping"]}}
  ```
- **GitLab** — toute MR porte le label **`squad-accounting`**.

Ces deux labels sont **obligatoires** : une omission sort le ticket/la MR du radar de la squad. Les poser à la création, jamais après coup.

## EPIC / domaine par défaut

- Domaine de code : `erp/*` (accounting + netsuite). Pour l'orientation technique → skill `malt-accounting-domain`.
- EPIC de rattachement : **demander à l'utilisateur** (question à choix) ; proposer par défaut l'EPIC accounting/bookkeeping du chantier courant. Ne jamais deviner l'EPIC en silence.

## Ce qui n'est PAS une convention de squad (reste global)

Ne pas confondre avec les constantes du setup, portées par CLAUDE.md / `malt-workflow-commons` : reviewer `@stephen.begot`, projet GitLab `maltcommunity/malt/apps/malt`, champ JIRA `Prompt` (`customfield_11956`), format de titre MR `[<TICKET>]`. Ceux-là ne changent pas avec la squad.
