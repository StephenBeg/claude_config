---
name: miro
description: Cree, edite et lit des boards, diagrammes et schemas Miro via le MCP Miro (mcp__miro__canvas_*), avec verification du rendu par data-rendered-bounds puis screenshot.
---

# Miro — écrire/lire des schémas propres et auto-vérifiés

Écrire ou lire des schémas Miro via le MCP `mcp__miro__*`. Objectif qualité **non négociable** : blocs lisibles, **zéro connecteur qui se croise**, **zéro chevauchement de texte**, espacement régulier.

**Le MCP est passé au protocole Canvas Composer SVG** (vérifié 2026-09-25). Les tools `diagram_create`, `layout_create`, `layout_read`, `layout_update`, `context_explore`, `context_get`, `*_get_dsl` **n'existent plus**. Tout passe par `canvas_*`.

## Champs communs sur presque tous les tools

- `invocation_source: "skill"` (déclenché par ce skill).
- `is_repository: true` (cwd = repo git — cas Malt).

## Les tools qui existent

| Besoin | Tool |
|---|---|
| Charger le protocole (OBLIGATOIRE avant d'écrire) | `canvas_get_canvas_composer_skill` |
| Guidance par format (Mermaid, slides, prototypes) | `canvas_load_format_skill` |
| Créer du contenu | `canvas_create_from_svg` |
| Itérer sur du contenu existant | `canvas_update_from_svg` |
| Découvrir / localiser | `canvas_search` (`overview`, puis `areas` / `matches`) |
| Lire une zone en SVG réinjectable | `canvas_read_as_svg` |

## Workflow d'écriture

1. `user_who_am_i` — confirmer l'auth.
2. `canvas_get_canvas_composer_skill` **sans argument** → il renvoie l'étape suivante. Puis `step="design"` (style guide Bright Paper) puis `step="dsl"` (grammaire SVG). Ne jamais écrire avant d'avoir la spec : elle est longue (~54 ko), la lire une fois et la réutiliser.
3. Pour un diagramme Mermaid : `canvas_load_format_skill(format_name="diagramming", notation="flowchart"|"entity_relationship"|"uml_class"|"uml_sequence"|"free_form")` → palette Fluoro + exemple.
4. `canvas_search(result_mode="overview")` sur le board cible pour savoir ce qui s'y trouve déjà.
5. `canvas_create_from_svg` — un seul `<svg>` racine, chaque enfant direct = un module top-level.
6. **Vérif des bounds** (ci-dessous), puis vérif visuelle par sous-agent.
7. Corriger via `canvas_update_from_svg` en repartant du `result_svg` précédent.

## Vérif des bounds — LE contrôle qui marche sans navigateur

Chaque réponse `canvas_create_from_svg` / `canvas_update_from_svg` renvoie :

- un message listant les ids dont **les dimensions mesurées diffèrent** de celles soumises ;
- un `result_svg` où chaque widget porte `data-rendered-bounds="x y width height"` en coordonnées **absolues** (même pour les enfants d'une frame : ajouter le `translate` de la frame pour comparer avec les coords authorées).

Contrôle systématique : pour chaque carte, `bounds(texte).y + bounds(texte).height <= bounds(carte).y + bounds(carte).height`. Idem titre vs sous-titre. C'est ce contrôle qui attrape les débordements, pas la relecture du SVG soumis.

**Piège mesuré** : un `<text>` en `font-size=67` sur 1600 px rend 1697 px de large et ~96 px de haut ; un `<textArea>` placé 22 px sous la *baseline* du titre le chevauche. Laisser ≥ 40 px entre baseline de titre et top du textArea suivant.

## Écrire le SVG — pièges vérifiés

- **Frame** : `<g id="f1" data-frame="Titre" transform="translate(x,y)">` + premier enfant `<rect data-type="frame" x="0" y="0" .../>`. Les coords des enfants sont **relatives** à la frame.
- **Éditer un enfant de frame** : il faut réémettre la frame **sous sa forme complète** (`data-miro-id` + `data-frame` + son `<rect data-type="frame">`). Un `<g data-miro-id>` nu est ignoré ("plain `<g>` is ignored") et l'enfant est alors traité comme déplacé en coords canvas → l'update échoue.
- **Escaping** : dans le corps Mermaid d'un `<foreignObject data-type="diagram">`, tout est XML-escapé — `--&gt;`, `&lt;br/&gt;`. Un `<br/>` brut fait rejeter tout le diagramme. Dans le corps d'un `<textArea>`, au contraire, `<b>` et `<br/>` sont du vrai markup accepté.
- **Widget diagram — PIÈGE MAJEUR, vérifié 2026-09-25.** Taille figée à 1600x900. Il est **non déplaçable** (`diagram does not support updates to: x/y`) **et non supprimable** (`diagrams cannot be deleted`). Pire : **toute mise à jour de son corps Mermaid le DÉPLACE** à une position arbitraire décidée par le serveur (mesuré : un diagramme en 6400,260 est parti en 5555,345 ; un autre en 3627,240 a atterri en -52,3876, par-dessus une frame). Conséquence : **un diagramme Mermaid est en pratique immuable**. Si son contenu doit changer, en créer un nouveau au bon endroit et demander à l'utilisateur de supprimer l'ancien à la main. Ne jamais lancer une réécriture en masse de diagrammes : on obtient N diagrammes éparpillés sans moyen de les replacer.
- **`<textArea>` porteur de markup : NE JAMAIS le mettre à jour.** Vérifié deux fois le 2026-09-25 : toute écriture sur un `<textArea>` dont le corps contient `<b>` ou `<br/>` — y compris un patch de position seule — transforme le markup en **texte littéral** (le board affiche `<b>…</b>`). Le renvoyer avec du vrai markup ne le répare pas. Seule issue : **créer un nouveau textArea** et supprimer l'ancien. Corollaire : mettre le texte riche dans des textArea qu'on ne retouchera plus, ou n'utiliser que du texte brut si le bloc doit évoluer.
- **Widget `<text>` : la largeur est FIGÉE à la création.** Remplacer le texte par une chaîne plus longue le fait wrapper sur 2, 3 ou 6 lignes dans la même largeur, et le serveur recentre verticalement (donc le `y` bouge aussi). Pour renommer un libellé : rester **plus court** que l'original, ou baisser `font-size`, et re-poser le `y` explicitement.
- **Z-index = ordre de création** : panneaux de fond d'abord, cartes ensuite, textes en dernier.
- **`data-miro-id`** : jamais inventé, jamais recopié de mémoire — uniquement repris d'un `result_svg`.
- **Suppression** : `data-deleted="true"` explicite, destructif → confirmer avec l'utilisateur avant.
- Retirer un élément du SVG **ne le supprime pas** : l'update est additif/patch.

## Grille anti-chevauchement (composition à la main)

- Échelle d'espacement Miro : 10, 20 (entre textes), 32, 64 (dans/autour d'un conteneur), 160, 320 (entre sections).
- Gabarit qui a marché : carte 420x210, gap 32, 4 cartes par rangée, panneau de fond 1840 de large avec 32 de padding, frame 1968 de large avec 64 de padding.
- Une seule famille de couleur par structure (style Bright Paper) : panneaux en teinte *faint*, cartes blanches, bordure en teinte *light* de la même famille. Max 3 familles par artefact.
- Flux directionnel unique (haut→bas ou gauche→droite) : supprime l'essentiel des croisements.

## Vérification visuelle par sous-agent

Après écriture, dispatcher un sous-agent qui ouvre le board dans un navigateur (chrome-devtools `navigate_page` + `take_screenshot`, sinon skill `playwright-cli`), fit-to-screen puis zoom, et retourne **une conclusion** : verdict PROPRE / À CORRIGER + corrections précises (bloc, coord cible, connecteur à re-router). Pas de dump d'image.

**Limite connue** : un navigateur piloté par MCP arrive sur un board Miro **non authentifié** → le sous-agent rend « BLOQUÉ: login Miro requis ». Dans ce cas la vérif des bounds est le seul contrôle automatique disponible : la faire à fond, puis **dire explicitement à l'utilisateur** que le rendu (notamment l'auto-layout Mermaid et ses croisements) n'a pas pu être contrôlé et lui demander un coup d'œil.

## Lire un board existant

- `canvas_search(result_mode="overview")` sans patterns — inventaire. Jamais de regex attrape-tout.
- `canvas_search(result_mode="areas"|"matches", patterns=[...])` pour cibler.
- `canvas_read_as_svg` avec les 4 champs de scope (ou `widget_ids`) une fois la zone identifiée. Échoue au-dessus de 500 widgets.

## Erreurs fréquentes

| Erreur | Correctif |
|---|---|
| Appeler `diagram_create` / `layout_*` | Ils n'existent plus → `canvas_create_from_svg` |
| Écrire sans charger le composer skill | `canvas_get_canvas_composer_skill` puis `step=design` puis `step=dsl` |
| Patcher un enfant de frame via un `<g>` nu | Réémettre la frame complète (`data-frame` + rect de fond) |
| `<br/>` brut dans un corps Mermaid | `&lt;br/&gt;` |
| Déclarer terminé sans contrôler les bounds | Comparer `data-rendered-bounds` texte vs carte |
| Créer un board sans confirmer | `board_create` = irréversible → confirmer |

## Red flags — STOP

- "Les dimensions ont l'air bonnes" → lire `data-rendered-bounds`, pas le SVG soumis.
- "Je place les blocs approximativement" → grille régulière, sinon chevauchements.
- "Le screenshot a échoué, tant pis" → le dire à l'utilisateur, ne pas déclarer PROPRE.
