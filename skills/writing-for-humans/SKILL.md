---
name: writing-for-humans
description: À charger AVANT de rédiger tout document destiné à être LU par un humain — RFC, note ou page Notion, description et commentaire JIRA, description de MR, compte rendu, analyse, doc markdown livré, message Slack long — en français comme en anglais.
---

# Écrire un document lu par un humain

Le lecteur par défaut est **non technique** et ne lira que le début. Le document sert **une décision**, il n'est pas la restitution de mon exploration.

## Le gabarit

1. **Une phrase de conclusion en haut** : ce que le document dit, demande ou décide. Le lecteur doit pouvoir s'arrêter là.
2. **Le corps, uniquement sur le sujet annoncé.** Une idée par paragraphe, 3 à 5 lignes, du blanc entre les blocs.
3. **Ce qu'on fait ensuite**, quand il y a une décision : qui tranche quoi, et quand.

## Le filtre de périmètre — avant chaque paragraphe

> Quelle décision de **CE** document change si je supprime ce paragraphe ?

Aucune → il dégage. Cela vaut aussi pour les faits **exacts** trouvés en explorant : un autre projet, un autre pays, l'historique d'un enum voisin, un précédent d'une autre squad. Ils restent dans ma réponse à l'utilisateur, jamais dans le document.

## Longueur

| Document | Cible | Ce qui y va |
|---|---|---|
| Commentaire JIRA | 100 mots | le fait nouveau, la décision, rien d'autre |
| Description JIRA | 150 mots | le besoin vu de l'utilisateur final, la DoD |
| Description de MR | 200 mots | ce qui change, pour qui, comment le vérifier |
| Compte rendu, analyse | 400 mots | la conclusion, les chiffres qui la portent |
| RFC, note de décision | 2 pages | le problème, les options, la reco |

La longueur est celle du **sujet**, jamais celle de mon exploration. Un chapitre de plus n'est pas une preuve de sérieux.

## Le vocabulaire du projet

**Un concept = un mot, celui du projet**, tenu à l'identique du début à la fin. Le mot vient du ticket, du code, de l'écran ou de ce que l'utilisateur a écrit. Deux noms pour la même chose dans un même document rendent le document illisible, et varier le vocabulaire « pour le style » est une faute, pas une élégance. Un terme interne indispensable se définit une fois, en une demi-phrase, à sa première apparition.

## Cible technique

Par défaut, une phrase dit **l'effet observable** (ce que voit l'utilisateur final, ce que change la donnée, le délai, la réversibilité), pas le mécanisme. Le détail technique va en annexe, en toggle ou en sous-page.

Si l'utilisateur précise que **la cible est technique**, la profondeur technique est permise dans le corps : noms de classes, `path:line`, schémas, requêtes. Le gabarit, les longueurs et les tics restent inchangés.

## Tics d'écriture IA — à supprimer

- **Le tiret cadratin ou demi-cadratin en incise.** Une incise se rend avec une virgule, des parenthèses, ou une phrase séparée.
- **Le point-virgule.** Le remplacer par un point.
- **Les tournures de balancier** : « ce n'est pas X, c'est Y », « il ne s'agit pas seulement de… », « plus qu'un X, un Y ».
- **Les formules de transition creuses** : « en résumé », « il est important de noter que », « il convient de », « plongeons dans ».
- **L'emphase décorative** : du gras sur des mots au hasard, des emoji dans les titres, des énumérations à rallonge.
- **Les tableaux à deux colonnes.** Un tableau se justifie à partir de trois colonnes. À deux, c'est une puce étiquetée : `- **Label.** Explication.`

Contrôle avant livraison, sur le fichier rédigé (ignorer les occurrences à l'intérieur des blocs de code) :

```
grep -nE '—|–|;|[Ee]n résumé|important de noter|il convient de|[Pp]longeons' doc.md
```

## Zéro métadonnée de construction

Le document est un **livrable final** : le lecteur n'a aucun indice sur la façon dont il a été rédigé. Bannis du texte publié : les chapeaux qui décrivent ce que la section doit contenir, les cases à cocher de rédaction, les placeholders « à écrire », les commentaires sur le document lui-même, toute reformulation de la consigne reçue.

## Red flags — réécrire avant de livrer

- La conclusion n'est pas dans les deux premières lignes.
- Un paragraphe qui ne sert aucune décision de ce document.
- Deux mots différents pour le même concept.
- Un tiret cadratin, un point-virgule, un tableau à deux colonnes.
- Un détail technique dans le corps alors que la cible n'a pas été dite technique.
- Le document est plus long que la cible de son type.

## Langue

Tout ce qui part vers JIRA, GitLab ou Notion s'écrit en **anglais** (seule exception : le champ JIRA `Prompt`). Les règles ci-dessus sont identiques dans les deux langues.
