---
name: asking-the-user
description: À charger AVANT toute question posée à l'utilisateur pendant une tâche — clarification, arbitrage, choix d'implémentation, AskUserQuestion, « je te laisse trancher » — y compris une question courte, et dès qu'il répond « je n'ai rien compris » ou « c'est incompréhensible ».
---

# Poser une question à l'utilisateur

L'utilisateur est développeur. Ce qui le bloque n'est **ni** le vocabulaire technique **ni** le manque de contexte : c'est le **VOLUME** et l'**ABSTRACTION**. Une question « métier », sans aucun nom réel, a reçu « je n'ai RIEN compris ». La même question en trois phrases avec les vrais noms a été tranchée du premier coup.

Source de vérité unique pour la **forme** des questions : ce skill l'emporte sur tout autre gabarit.

## Avant de poser : est-ce vraiment une question ?

- La réponse est dans le code, le ticket, l'historique git ou la prod → **aller lire**, ne pas demander.
- Le choix est technique et sans effet observable → **trancher seul**, le signaler dans le livrable.
- Je dois expliquer un mécanisme interne pour que la question ait du sens → la question est **mal découpée**. La redécouper, ou demander à l'utilisateur d'énoncer le besoin avec ses mots.

## Le gabarit — dans cet ordre, rien d'autre

1. **Le fait** (1 à 3 phrases) : ce qui se passe aujourd'hui, avec les **vrais noms** et **un chiffre mesuré** s'il en existe un.
2. **La question** (1 phrase, finit par « ? »).
3. **Les options** (2 à 4, **une ligne chacune**) : libellé court, puis ce que ça donne concrètement.
4. **Ma reco** (1 phrase) : laquelle, et pourquoi.

**Plafond dur : 150 mots**, options comprises. Rien avant le point 1, rien après le point 4. Rédaction en **prose normale** : caveman reste actif pour le reste du tour, pas pour la question.

## Les noms : les vrais, jamais une paraphrase

Chaque nom employé vient de l'une de ces quatre sources : les mots de l'utilisateur dans la conversation, le ticket JIRA, un identifiant du code, un libellé visible à l'écran. **Un nom qui ne vient d'aucune des quatre est un nom inventé** : le remplacer par le vrai, ou le supprimer.

Ne **jamais** traduire un vrai nom en périphrase « métier » : `payout` ne devient pas « le point de départ », un event de réception ne devient pas « le repère ». C'est exactement ce qui rend une question illisible. Un vrai nom qu'il ne connaît peut-être pas se définit **une fois, en quatre mots entre parenthèses**.

## « Je n'ai rien compris »

Ce n'est **pas** une demande de reformuler la même question plus simplement. C'est le signal que **mon découpage du problème est faux**.

- Ne pas réécrire la même question en plus court : changer de découpage, ou demander « dis-moi le besoin avec tes mots ».
- Dès qu'il énonce le besoin lui-même, **sa phrase devient la consigne** : la reprendre verbatim, la chercher telle quelle dans le code, abandonner mon cadrage. Ne pas essayer de la réconcilier avec mes options précédentes.

## Libellés d'options

Un libellé = **un seul** périmètre. L'utilisateur répond au libellé, pas à la description. « A + B » = deux options, jamais une. Une option qui élargit le périmètre le dit **dans son libellé**.

## Exemple

❌ **Ce qui a échoué**

> Aujourd'hui le traitement démarre à partir d'un point de départ qui n'est pas toujours renseigné. Quand ce repère manque, la période couverte n'est plus déterminable, ce qui ouvre un arbitrage entre exhaustivité et coût de retraitement. Il faut décider quelle stratégie de reprise adopter, sachant que chacune a des implications sur la charge et sur la cohérence des données. [+ 2 paragraphes]

✅ **Ce qui a marché**

> Le curseur du fan-out, c'est l'event de réception du payout. 12 % des payouts en prod n'en ont pas, donc ils ne partent jamais.
>
> On fait quoi pour ces 12 % ?
>
> - **Les rejouer depuis leur date de création** — tous traités, risque de doublon sur ceux déjà partis.
> - **Les laisser de côté et alerter** — zéro doublon, mais reprise manuelle.
>
> Reco : les rejouer, le doublon est rattrapé en aval.

## Red flags — réécrire avant d'envoyer

- Plus de 150 mots, ou plus de deux questions dans le tour.
- Un nom que je ne peux pointer ni dans ses mots, ni dans le ticket, ni dans le code, ni à l'écran.
- « En gros », « autrement dit », « c'est un peu comme », une mise en situation, une analogie.
- Un paragraphe « pourquoi je ne peux pas trancher seul ».
- Une option que je ne choisirais jamais, mise là pour faire nombre.
- Un renvoi (« cf. le ticket », « voir tel fichier ») : la question est autoportante.
- Un bloc de code, sauf si la question **porte** sur ces deux lignes précises.
