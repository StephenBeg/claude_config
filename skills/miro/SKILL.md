---
name: miro
description: Use when creating, editing, or reading Miro boards/diagrams/schemas via the Miro MCP server (mcp__miro__*). Produces clean, readable schemas — no crossing connectors, no text overlap, centered/legible blocks — and self-verifies the rendered result with a screenshot subagent before declaring done.
---

# Miro — écrire/lire des schémas propres et auto-vérifiés

Écrire ou lire des schémas Miro via le MCP `mcp__miro__*`. Objectif qualité **non négociable** : blocs lisibles, textes centrés, **zéro connecteur qui se croise**, **zéro chevauchement de texte**, espacement régulier. Toute écriture est **auto-vérifiée par screenshot** avant de dire "terminé".

## Règle d'or (RÈGLE ABSOLUE)

**Toute écriture (`diagram_create` / `layout_create` / `layout_update`) DOIT être suivie d'une vérification visuelle par un sous-agent qui screenshote le board rendu.** Pas de screenshot inspecté = tâche non terminée. Le MCP Miro n'a PAS de capture native du rendu → le screenshot passe par un navigateur (chrome-devtools/playwright), délégué à un sous-agent.

## Champs communs sur presque tous les tools

- `invocation_source: "skill"` (déclenché par ce skill).
- `is_repository: true` (cwd = repo git — cas Malt).

## Choisir l'outil d'écriture

| Besoin | Outil | Pourquoi |
|---|---|---|
| Schéma structuré standard : flowchart, UML class/sequence, ERD | **`diagram_create`** | **Auto-layout Miro** → évite mécaniquement les croisements/chevauchements. **Préférer par défaut.** |
| Layout libre : mix formes/sticky/frames/connecteurs custom | `layout_create` | Coordonnées manuelles → TOI de garantir l'anti-chevauchement |
| Corriger un board existant | `layout_read` → `layout_update` | Find-replace ciblé sur le DSL courant |

**Défaut : `diagram_create`.** N'utilise `layout_create` que si le schéma n'entre dans aucun type de diagramme, car le placement manuel est la source n°1 de croisements.

## DSL : toujours le récupérer au runtime

Le DSL exact (types d'items, syntaxe connecteurs `alias -> alias`, couleurs/shapes valides, exemple) **n'est pas connu à l'avance**. Avant CHAQUE `*_create` :

- `layout_get_dsl` (aucun param) avant `layout_create`.
- `diagram_get_dsl` (`miro_url`, `diagram_type`) avant `diagram_create`.

Appeler **1 fois par type**, réutiliser la spec dans la conversation. Ne jamais deviner la syntaxe.

## Workflow d'écriture

1. `user_who_am_i` — confirmer l'auth.
2. Board cible : `board_search_boards` (query) pour retrouver un board existant. Sinon `board_create` — **action irréversible, confirmer avec l'utilisateur** (idem création implicite via `diagram_create` sans `miro_url`).
3. Récupérer le DSL (`*_get_dsl`, cf. ci-dessus).
4. Écrire (`diagram_create` de préférence).
5. **Vérif logique** : `context_get` sur l'URL de l'item (`?moveToWidget=<id>`) → renvoie du **Mermaid** = contrôle structurel fiable (nœuds/relations présents).
6. **Vérif visuelle par sous-agent** (obligatoire, section dédiée ci-dessous).
7. Corriger via `layout_update` (après `layout_read`) jusqu'à ce que le screenshot soit propre.

## Règles anti-chevauchement pour `layout_create` (coordonnées manuelles)

`layout_create` n'a pas d'auto-layout — appliquer ces règles explicitement :

- **Grille régulière** : board center = (0,0). Aligner les blocs sur une grille (ex. pas de 300px en x, 200px en y). Ne jamais poser deux blocs à des coordonnées "à peu près".
- **Espacement** : ≥ 150px de gap entre blocs voisins ; largeur de bloc = largeur texte + marge, pas plus serré.
- **Texte centré** : renseigner l'alignement centré (h+v) sur chaque bloc porteur de texte ; dimensionner le bloc pour que le texte ne déborde pas (pas de troncature).
- **Flux directionnel** : orienter les connecteurs dans un sens unique (haut→bas ou gauche→droite). Un flux monotone supprime la majorité des croisements.
- **Pas de connecteur qui traverse un bloc** : router en réservant des couloirs libres entre les colonnes/lignes de la grille.
- **Frames d'abord** : placer les frames, puis les items (avec `parent`), puis les connecteurs (référencent les alias).
- **Coords dans un frame** : avec `?moveToWidget=<frame_id>`, (0,0) = coin haut-gauche du frame ; l'item doit tenir dedans.
- **Taille DSL max 50000 chars** → découper les gros schémas.

`diagram_create` gère tout ça seul : pour un schéma structuré, laisse Miro placer.

## Vérification visuelle par sous-agent (RÈGLE ABSOLUE)

Après CHAQUE écriture, dispatcher un **sous-agent** dédié (économie de contexte : les screenshots et l'analyse ne polluent pas le thread principal). Le sous-agent :

1. Ouvre l'URL du board dans un navigateur via `mcp__chrome-devtools__navigate_page` (ou playwright `browser_navigate`), attend le rendu.
2. `take_screenshot` du board (zoomer/fit si besoin pour tout cadrer).
3. **Inspecte le screenshot** et retourne une CONCLUSION structurée (pas le dump image) :
   - Connecteurs qui se croisent ? (liste des paires)
   - Texte qui déborde / est tronqué / se chevauche ? (quels blocs)
   - Textes non centrés ? Blocs mal espacés / superposés ?
   - Verdict : **PROPRE** ou **À CORRIGER** + liste précise de corrections (bloc, ancien→nouveau x/y/width, ou connecteur à re-router).

Prompt type pour le sous-agent :

> Ouvre `<board_url>` dans le navigateur (chrome-devtools navigate_page puis take_screenshot, fit-to-screen). Inspecte VISUELLEMENT le schéma. Cherche : connecteurs qui se croisent, texte qui déborde/se chevauche/tronqué, textes non centrés, blocs superposés ou mal espacés. Retourne UNIQUEMENT une conclusion : verdict PROPRE/À CORRIGER + liste précise des corrections (bloc + coord/width cibles, connecteurs à re-router). Pas de dump du screenshot.

Si verdict = À CORRIGER → appliquer via `layout_update` (find-replace sur les lignes fautives après `layout_read`) puis **re-dispatcher un sous-agent de vérif**. Boucler jusqu'à PROPRE. Déclarer terminé seulement sur un verdict PROPRE.

## Lire un board existant

- `context_explore` (`miro_url`) — inventaire haut-niveau : frames, docs, tables, diagrams (titres + URLs). **Première étape de découverte.**
- `context_get` (`miro_url`) — contenu textuel ; board nu = overview IA ; `?moveToWidget=<id>` = contenu de l'item (diagram→Mermaid, frame→résumé, doc→Markdown, table→data).
- `layout_read` (`miro_url`, `mode` structured/full) — items en DSL réinjectable dans `layout_update`. Les ids retournés sont des URLs Miro réutilisables.
- `board_list_items` — items paginés bruts (capé à 50 si filtré par parent).

## Erreurs fréquentes

| Erreur | Correctif |
|---|---|
| Deviner le DSL sans `*_get_dsl` | Toujours récupérer la spec au runtime, 1×/type |
| Utiliser `layout_create` pour un flowchart | Utiliser `diagram_create` (auto-layout anti-croisement) |
| Déclarer terminé sans screenshot | Vérif visuelle par sous-agent obligatoire avant "fini" |
| `layout_update` sans `layout_read` | `old_string` doit matcher le DSL courant exact |
| Créer un board sans confirmer | `board_create` / board implicite = irréversible → confirmer |
| Chercher un screenshot via `image_get_data` | Ne marche que sur des items IMAGE ; rendu board = browser |
| Blocs collés / texte tronqué | Grille + gap ≥150px + bloc dimensionné au texte + centrage |

## Red flags — STOP

- "Le schéma a l'air bon, pas besoin de screenshot" → NON, vérif visuelle obligatoire.
- "J'utilise layout_create, c'est plus flexible" pour un diagramme standard → utilise `diagram_create`.
- "Je place les blocs approximativement" → grille régulière, sinon chevauchements.
