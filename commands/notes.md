---
description: Transforme un dump d'idées brutes, notes de réunion, tâches ou fragments en notes Obsidian structurées dans le graph du vault.
allowed-tools: Bash
---

Tu traites un dump brut et le transformes en notes Obsidian durables dans le vault `obsidian/notes`.

## 1. Analyse du dump

Décompose le contenu en :
- **Entités/nœuds** : company, squad, team, personne, outil, système, domaine, projet, décision, question
- **Relations/arêtes** : appartient à, utilise, intègre, dépend de, rapporte à, remplace, est lié à
- **Types atomiques** : idée, tâche, décision, question, référence, contexte de réunion

## 2. Inspection du vault avant écriture

```shell
cd obsidian/notes && obsidian read path="_INDEX.md"          # carte du vault (lire en premier)
cd obsidian/notes && obsidian files ext=md
cd obsidian/notes && obsidian tags counts format=json
cd obsidian/notes && obsidian search:context query="<terme-clé>" limit=15
cd obsidian/notes && obsidian backlinks path="<note-existante-probable>.md" format=json
```

Identifie les notes existantes à réutiliser. Crée une nouvelle note uniquement si l'entité mérite un nœud graph stable indépendant.

## 3. Modélisation graph-first

Le vault est un graphe Obsidian, pas une arborescence de dossiers.

- **Nœud racine Malt** : `[[Malt]]` est le point d'entrée de tout le contexte entreprise. Ne crée pas de nœud `[[Entreprise]]` générique sauf demande explicite.
- **Hiérarchie Malt** : `[[Malt]] → [[Squads]] → [[Billing]]`, pas `Malt - Squad Billing` comme titre monolithique.
- **Univers** : `[[Transaction]]` et `[[Staffing]]` sont des nœuds de classification, pas des parents de stockage.
- **Pas de sur-liaison** : si le chemin `[[Malt]] → [[Squads]] → [[Billing]]` est clair, pas de lien direct `[[Malt]] → [[Billing]]`.
- **Réciprocité** : quand tu crées un nœud enfant, ajoute le backlink depuis le parent dans la même opération.
- **Orphelins** : toute note durable doit lier au moins un nœud de contexte fort. Seul `00 Inbox/` peut contenir des orphelins.

## 4. Frontmatter de référence

```yaml
---
type: squad          # idea|project|area|resource|collection|company|squad|team|system|tool|person|meeting|decision|question|task-log|rfc|adr|index
status: active       # active|inbox|incubating|archived
collection: "[[Squads]]"
universe: "[[Transaction]]"
tags:
  - company/malt
  - team/billing
created: YYYY-MM-DD
source: capture
summary: Une ligne factuelle décrivant le contenu/rôle de la note.
up: "[[Squads]]"
---
```

`summary` (1 ligne) et `up` (`"[[Parent]]"`) sont **obligatoires** sur toute note durable : ils rendent le vault traversable sans lire les corps. `up` reflète la section `## Parent`.

Utilise aussi les champs de relation frontmatter pour les arêtes stables : `collection`, `universe`, `parent`, `tools`, `systems`, `projects`, `related`.

## 5. Structure d'une note

```markdown
---
type: <type>
status: active
tags:
  - <tag/hiérarchique>
created: <date-du-jour>
source: capture
summary: <une ligne factuelle>
up: "[[Parent]]"
---

# Titre Durable

Reformulation concise en français.

## Points clés

- Un point par bullet, avec [[wikilinks]] vers les concepts importants.

## Actions

- [ ] Tâche concrète si présente.

## Related

- [[Note Existante]]
```

N'ajoute `## Related` que pour des liens non-hiérarchiques significatifs. N'y duplique pas les liens déjà présents en frontmatter ou dans le corps.

## 6. Règles de rédaction

- Rédige en français sauf si le dump source est clairement dans une autre langue.
- Titre noun-like et durable, pas une phrase complète.
- Ne garde le dump source dans la note que si le libellé exact est citable ou sensible (`## Capture brute`).
- Pour une fusion dans une note existante : ajoute sous un heading daté `## YYYY-MM-DD - Capture`.
- Préfère une note solide à plusieurs notes légères, sauf si les concepts sont clairement indépendants.

## 7. Questions de clarification

Pose une question en chat (pas dans la note) uniquement si :
- La même idée pourrait appartenir à plusieurs projets actifs et le choix change le stockage.
- Le contenu est potentiellement sensible et la destination/confidentialité est incertaine.
- Le sens est trop vague pour reformuler sans inventer des détails.

Maximum 3 questions, courtes et ciblées. Ne crée pas de section `## Questions` par défaut dans les notes.

## 8. Métadonnées agent et index

Pour chaque note durable créée ou déplacée :
- Renseigne `summary` et `up` (via `obsidian property:set ... type=text`).
- Ajoute la nouvelle note à `_INDEX.md` dans la bonne catégorie (ligne `[[Note]] — summary — chemin`).

## 9. Validation

Après chaque écriture :
```shell
cd obsidian/notes && obsidian read path="<chemin-note-créée.md>"
cd obsidian/notes && obsidian links path="<chemin-note-créée.md>"
cd obsidian/notes && obsidian orphans   # la nouvelle note ne doit pas être orpheline
```

## Dump à traiter

$ARGUMENTS
