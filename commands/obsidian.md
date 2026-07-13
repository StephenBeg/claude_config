---
description: Vault Obsidian local (obsidian/notes) — capture un dump brut en notes graph durables OU recherche/synthèse/génération de documents depuis le vault. Détecte le mode selon l'intention.
allowed-tools: Bash
---

Tu opères sur le vault Obsidian local `obsidian/notes`, traité comme un **graphe typé** (pas une arborescence de dossiers).

## 0. Détection du mode

Lis `$ARGUMENTS` et choisis :

- **CAPTURE** — l'entrée est un dump brut (idées, notes de réunion, tâches, fragments) à transformer en notes durables. Va en section A.
- **RECHERCHE** — l'entrée est une question, une demande de synthèse, ou une demande de document (RFC/ADR/brief). Va en section B.

Si ambigu (les deux sont plausibles) : une seule question de clarification en chat, puis procède.

## Inspection commune (toujours en premier)

```shell
cd obsidian/notes && obsidian read path="_INDEX.md"          # carte agent-first du vault
cd obsidian/notes && obsidian tags counts format=json
```

---

# A. MODE CAPTURE

## A.1 Analyse du dump

Décompose en :
- **Entités/nœuds** : company, squad, team, personne, outil, système, domaine, projet, décision, question
- **Relations/arêtes** : appartient à, utilise, intègre, dépend de, rapporte à, remplace, est lié à
- **Types atomiques** : idée, tâche, décision, question, référence, contexte de réunion

## A.2 Inspection avant écriture

```shell
cd obsidian/notes && obsidian files ext=md
cd obsidian/notes && obsidian search:context query="<terme-clé>" limit=15
cd obsidian/notes && obsidian backlinks path="<note-existante-probable>.md" format=json
```

Réutilise les notes existantes. Crée une note neuve seulement si l'entité mérite un nœud graph stable indépendant.

## A.3 Modélisation graph-first

- **Nœud racine Malt** : `[[Malt]]` est le point d'entrée du contexte entreprise. Pas de nœud `[[Entreprise]]` générique sauf demande explicite.
- **Hiérarchie** : `[[Malt]] → [[Squads]] → [[Billing]]`, pas un titre monolithique `Malt - Squad Billing`.
- **Univers** : `[[Transaction]]` et `[[Staffing]]` sont des nœuds de classification, pas des parents de stockage.
- **Pas de sur-liaison** : si `[[Malt]] → [[Squads]] → [[Billing]]` est clair, pas de lien direct `[[Malt]] → [[Billing]]`.
- **Réciprocité** : en créant un enfant, ajoute le backlink depuis le parent dans la même opération.
- **Orphelins** : toute note durable lie au moins un nœud de contexte fort. Seul `00 Inbox/` peut contenir des orphelins.

## A.4 Frontmatter + structure de note

```markdown
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

# Titre Durable

Reformulation concise en français.

## Points clés

- Un point par bullet, avec [[wikilinks]] vers les concepts importants.

## Actions

- [ ] Tâche concrète si présente.

## Related

- [[Note Existante]]
```

- `summary` (1 ligne) et `up` (`"[[Parent]]"`) sont **obligatoires** sur toute note durable : ils rendent le vault traversable sans lire les corps. `up` reflète la section `## Parent`.
- Champs de relation frontmatter pour les arêtes stables : `collection`, `universe`, `parent`, `tools`, `systems`, `projects`, `related`.
- `## Related` seulement pour des liens non-hiérarchiques significatifs ; n'y duplique pas les liens déjà en frontmatter/corps.

## A.5 Règles de rédaction

- Français sauf si le dump source est clairement dans une autre langue.
- Titre noun-like et durable, pas une phrase complète.
- Ne garde le dump source (`## Capture brute`) que si le libellé exact est citable/sensible.
- Fusion dans une note existante : sous un heading daté `## YYYY-MM-DD - Capture`.
- Préfère une note solide à plusieurs notes légères, sauf concepts clairement indépendants.

## A.6 Métadonnées et index

Pour chaque note durable créée/déplacée :
- Renseigne `summary` et `up` (via `obsidian property:set ... type=text`).
- Ajoute la note à `_INDEX.md` dans la bonne catégorie (ligne `[[Note]] — summary — chemin`).

## A.7 Validation (obligatoire après chaque écriture)

```shell
cd obsidian/notes && obsidian read path="<chemin-note-créée.md>"
cd obsidian/notes && obsidian links path="<chemin-note-créée.md>"
cd obsidian/notes && obsidian orphans   # la nouvelle note ne doit PAS être orpheline
```

---

# B. MODE RECHERCHE

## B.1 Traduction de la question

Identifie : mots-clés/synonymes, tags probables (`company/malt`, `team/billing`, `topic/netsuite`…), dossiers probables (`10 Projects/`, `20 Areas/Malt/`, `30 Resources/`…), noms de notes probables.

## B.2 Recherche large puis ciblée

```shell
cd obsidian/notes && obsidian search:context query="<terme-1>" limit=20
cd obsidian/notes && obsidian search:context query="<terme-2>" limit=20
cd obsidian/notes && grep -rh '^summary:' . --include='*.md' | grep -v .obsidian   # repérer par résumé
```

## B.3 Lecture et traversée du graphe

```shell
cd obsidian/notes && obsidian read path="<note.md>"
cd obsidian/notes && obsidian links path="<note.md>"
cd obsidian/notes && obsidian backlinks path="<note.md>" format=json
cd obsidian/notes && obsidian outline path="<note.md>"
```

Graphe typé : suis les champs de relation (`up`, `collection`, `universe`, `parent`, `tools`, `systems`, `projects`, `related`) autant que les wikilinks inline. `up` = parent direct ; `grep -rh '^up:'` reconstruit l'arbre. Note mal placée en dossiers mais bien liée → fais confiance aux liens graph. Explique via chemins graph : `[[Malt]] → [[Squads]] → [[Billing]] → [[Oracle NetSuite]]`.

## B.4 Réponse

- Français sauf demande contraire.
- Distingue **ce que dit le vault** vs **ce que tu inférences**.
- Cite avec chemin relatif : `Source : 20 Areas/Malt/Squads/Billing.md#Section`. Ne cite que des notes réellement lues.
- Signale quand le vault manque de preuves. Pas de recherche web sauf demande explicite.

## B.5 Génération de document (RFC, ADR, brief)

Seulement si l'utilisateur demande un artifact Obsidian ; sinon réponds en chat.

Avant d'écrire :
```shell
cd obsidian/notes && obsidian search:context query="<sujet>" limit=20
cd obsidian/notes && obsidian search query="decision <sujet>" format=json
```
Identifie projets liés, décisions antérieures, alternatives, contraintes.

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
- Stocke dans le dossier projet pertinent, sinon `30 Resources/`.
- Mets à jour les backlinks depuis les notes liées après création.

---

## Clarification (les deux modes)

Pose une question (max 3, courtes, en chat) uniquement si :
- La même idée/le même sujet pourrait appartenir à plusieurs projets actifs et le choix change le stockage ou la réponse.
- Contenu potentiellement sensible, destination/confidentialité incertaine.
- Sens trop vague pour reformuler sans inventer, ou vault sans preuve alors qu'une réponse ancrée est attendue.

Si seuls des détails mineurs manquent : procède (mode RECHERCHE : ajoute `## Questions ouvertes`).

## Entrée à traiter

$ARGUMENTS
