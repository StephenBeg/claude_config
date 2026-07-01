---
description: Recherche, synthèse et réponse depuis le vault Obsidian, traversée du graphe, génération de RFC/ADR et documents structurés.
allowed-tools: Bash
---

Tu réponds à une question ou génères un document en exploitant le vault Obsidian local `obsidian/notes`.

## 1. Traduction de la question en termes de recherche

Identifie :
- Mots-clés et synonymes
- Tags probables (`company/malt`, `team/billing`, `topic/netsuite`…)
- Dossiers probables (`10 Projects/`, `20 Areas/Malt/`, `30 Resources/`…)
- Noms de notes probables

## 2. Recherche large en premier

Commence par lire la carte du vault, puis cible la recherche :

```shell
cd obsidian/notes && obsidian read path="_INDEX.md"          # carte agent-first (lire en premier)
cd obsidian/notes && obsidian search:context query="<terme-1>" limit=20
cd obsidian/notes && obsidian search:context query="<terme-2>" limit=20
cd obsidian/notes && obsidian tags counts format=json
cd obsidian/notes && grep -rh '^summary:' . --include='*.md' | grep -v .obsidian   # repérer les notes pertinentes par résumé
```

## 3. Lecture et traversée du graphe

Lis les notes les plus pertinentes, puis explore :

```shell
cd obsidian/notes && obsidian read path="<note.md>"
cd obsidian/notes && obsidian links path="<note.md>"
cd obsidian/notes && obsidian backlinks path="<note.md>" format=json
cd obsidian/notes && obsidian outline path="<note.md>"
```

Traite le vault comme un graphe typé. Suis les champs frontmatter de relation (`up`, `collection`, `universe`, `parent`, `tools`, `systems`, `projects`, `related`) autant que les wikilinks inline. `up` donne le parent direct ; `grep -rh '^up:'` reconstruit l'arbre complet. Si une note semble mal placée dans les dossiers mais a des liens clairs, fais confiance aux liens graph.

Quand tu expliques un sujet, préfère les chemins graph : `[[Malt]] → [[Squads]] → [[Billing]] → [[Oracle NetSuite]]`.

## 4. Réponse

- Réponds en français sauf demande contraire.
- Distingue clairement : **ce que dit le vault** vs **ce que tu inférences**.
- Cite les notes avec leur chemin relatif : `Source : 20 Areas/Malt/Squads/Billing.md#Section`.
- Ne cite que des notes que tu as effectivement lues.
- Signale quand le vault manque de preuves suffisantes.
- Ne fais pas de recherche web sauf si l'utilisateur le demande explicitement.

## 5. Génération de documents (RFC, ADR, brief, synthèse)

Génère un document uniquement si l'utilisateur en demande un artifact Obsidian. Sinon, réponds en chat.

**Avant d'écrire un RFC ou ADR :**
```shell
cd obsidian/notes && obsidian search:context query="<sujet>" limit=20
cd obsidian/notes && obsidian search query="decision <sujet>" format=json
```
Identifie projets liés, décisions antérieures, alternatives, et contraintes.

### Template RFC

```markdown
---
type: rfc
status: draft
tags:
  - topic/<sujet>
created: YYYY-MM-DD
---

# RFC : Titre

## Résumé

## Contexte

## Objectifs

## Hors périmètre

## Proposition

## Alternatives envisagées

## Risques et compromis

## Déploiement ou prochaines étapes

## Questions ouvertes

## Références
```

### Template ADR

```markdown
---
type: adr
status: proposed
tags:
  - topic/<sujet>
created: YYYY-MM-DD
---

# ADR : Titre de la décision

## Statut

Proposé | Accepté | Remplacé par [[ADR suivant]]

## Contexte

## Décision

## Conséquences

## Alternatives envisagées

## Références
```

**Règles documents :**
- Titre court et cherchable.
- Cite les notes vault dans `Références` avec wikilinks.
- Marque explicitement les hypothèses non supportées par le vault.
- Stocke les documents durables dans le dossier projet pertinent, sinon `30 Resources/`.
- Mets à jour les backlinks depuis les notes liées après création.

## 6. Clarification

Pose une question si :
- Le type de document demandé est ambigu et changerait significativement la structure.
- Plusieurs projets correspondent au même sujet.
- Le vault n'a pas de preuves et l'utilisateur attend une réponse ancrée dans le vault.

Si seuls des détails mineurs manquent, procède et ajoute une section `## Questions ouvertes`.

## Question ou demande

$ARGUMENTS
