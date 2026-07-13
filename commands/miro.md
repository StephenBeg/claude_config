---
description: Crée des boards Miro propres via le MCP miro (DSL layout + diagrammes auto-layout) — texte centré, zéro chevauchement, respect des bornes de frame. S'auto-vérifie en relisant le board.
allowed-tools: mcp__miro__layout_get_dsl, mcp__miro__layout_create, mcp__miro__layout_read, mcp__miro__layout_update, mcp__miro__diagram_get_dsl, mcp__miro__diagram_create, mcp__miro__board_create, mcp__miro__board_list_items, mcp__miro__context_get, mcp__miro__context_explore
---

Tu crées ou édites un board Miro **propre et lisible** via le MCP miro. Un board "joli" = grille régulière, texte centré, aucun chevauchement, tout dans les bornes, palette et typo cohérentes.

## 0. Board cible

- URL fournie dans `$ARGUMENTS` → utilise-la.
- Sinon **demande confirmation** avant de créer un board neuf (`board_create` ou `diagram_create` sans URL en crée un). Ne crée jamais un board sans accord explicite.

## 1. Choix de l'outil — décide AVANT de dessiner

```
Contenu = flux / process / classes / séquence / ERD ?
   OUI → diagram_create (auto-layout : positionne et espace pour toi → zéro chevauchement gratuit)
   NON → layout_create (contrôle manuel : tu DOIS appliquer la discipline grille ci-dessous)
```

- **Toujours** appeler `..._get_dsl` **une seule fois** par conversation avant le premier `..._create`, puis réutiliser la spec.
- `diagram_create` gère le placement : préfère-le dès que le contenu est un graphe. N'assemble un flowchart à la main en `layout_create` que si tu as besoin d'un style que le diagramme ne permet pas.

## 2. Système de design (cohérence = "joli")

Fixe ces tokens en début de board et n'en dévie pas :

- **Grille** : pas de base `GRID = 40 px`. Toute coordonnée et dimension est un multiple de `GRID`.
- **Gouttière** : `GUTTER ≥ 80 px` entre deux items voisins (jamais collés).
- **Palette** : 1 couleur d'accent + neutres. Fills hex cohérents (ex. accent `#2D9BF0`, surface `#F5F6F8`, texte `#1A1A1A`, texte sur accent `#FFFFFF`). Réutilise les mêmes hex partout.
- **Typo** : une seule famille (ex. `font=plex_sans` ou `open_sans`). Titre `size=28`, sous-titre `size=20`, corps `size=14`. Pas plus de 3 tailles.
- **Cartouches** : SHAPE `type=round_rectangle`, `border_width=2`.

## 3. Discipline de grille (obligatoire en layout_create)

Le DSL ne recentre rien : un mauvais calcul = chevauchement ou débordement. Règles :

- **Frame d'abord.** Encadre chaque zone dans une FRAME. Les enfants utilisent des coords **relatives au coin haut-gauche de la frame** (0,0 = haut-gauche). Board-level = coords absolues, centre board = (0,0).
- **x,y = CENTRE** pour FRAME / STICKY / SHAPE / TEXT / CARD. **x,y = COIN HAUT-GAUCHE** pour DOC / TABLE (piège classique). DOC largeur fixe **800 px**, hauteur auto.
- **Bornes** (enfant de frame) : `0 ≤ x ≤ frame_w` et `0 ≤ y ≤ frame_h` sur le **centre**. Une seule violation fait échouer **tout le batch**. Garde en plus une marge : centre ≥ `w/2 + 40` des bords.
- **Placement par cellules.** Calcule une grille explicite. Pour colonne `c` (0-based) et rangée `r`, item `w×h` dans une frame avec marge `M=80` et gouttière `G=80` :
  - `cell_w = w + G`, `cell_h = h + G`
  - `cx = M + c*cell_w + w/2`
  - `cy = M + r*cell_h + h/2`
  - Dimensionne la frame : `frame_w = 2M + cols*w + (cols-1)*G`, idem hauteur.
- **Non-chevauchement** = pour toute paire, `|cx1-cx2| ≥ (w1+w2)/2 + G` **ou** `|cy1-cy2| ≥ (h1+h2)/2 + G`. Vérifie avant d'envoyer.
- **Connecteurs** : déclarés en dernier, référencent les alias. Pas de coords. `shape=elbowed` pour des liens orthogonaux nets ; `start_snap/end_snap` pour fixer le côté d'attache.

## 4. Texte centré (exigence explicite)

- SHAPE / STICKY : ajoute **`align=center valign=middle`** systématiquement (défaut = `top`, donc à forcer).
- TEXT : `align=center` et pose `x` au centre visé, `w` = largeur du bloc (Miro auto-height). Texte centré ⇒ le centre du bloc doit coïncider avec le centre de la cellule.
- Garde le texte court par item ; multi-lignes via `<p>...</p>`. Un item ne doit pas déborder de son cartouche : si le texte est long, agrandis `w`/`h` (multiples de GRID) plutôt que de laisser rogner.

## 5. Auto-vérification (NON négociable — après CHAQUE create/update)

1. `layout_read miro_url=<board ou frame>` → récupère le board réel en DSL.
2. Recalcule les **bounding boxes** (`x±w/2`, `y±h/2`; DOC/TABLE : coin haut-gauche + largeur/hauteur, DOC=800 large).
3. Contrôle :
   - **Débordement** : un item échoué dans le retour de `layout_create` (liste des items non créés) → corrige coords et rejoue.
   - **Hors bornes** : centre enfant hors `[0,frame_w]×[0,frame_h]` → repositionne.
   - **Chevauchement** : deux boxes qui s'intersectent → écarte via `layout_update`.
   - **Centrage** : titres/labels visuellement décalés → ajoute `align/valign` manquants.
4. Applique les fixes avec `layout_update` (find/replace de lignes DSL) et **re-vérifie**. Boucle jusqu'à : 0 item échoué, 0 hors-borne, 0 chevauchement.
5. Ne déclare le board terminé qu'après une passe `layout_read` propre. Rends l'URL finale.

## 6. Erreurs fréquentes

- Oublier `align=center valign=middle` → texte collé en haut-gauche du cartouche.
- Confondre centre vs coin haut-gauche pour DOC/TABLE → décalage de `w/2`, `h/2`.
- Enfant dont le centre est valide mais dont le bord sort de la frame (pas de marge) → visuellement tronqué.
- Un seul item hors bornes → **tout** le `layout_create` échoue silencieusement pour ce batch : lis toujours la liste des échecs retournée.
- Empiler DOC (800 px) sans réserver 800+ de large → chevauchement avec le voisin.
- Sauter la relecture `layout_read` : le board "à l'aveugle" n'est jamais garanti propre.

## Demande à réaliser

$ARGUMENTS
