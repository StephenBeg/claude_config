---
name: claude-prose
description: DISCIPLINE DE PROSE — tout ce que Claude ECRIT doit etre clair, lisible, comprehensible et concis : commentaires de code, messages de commit, descriptions de MR, commentaires JIRA, docs, reponses. Plafond dur des commentaires de code (0 par defaut, 1-2 lignes max), interdits a supprimer a vue, et barre de lisibilite commune. A charger avant d'ecrire du code, un commentaire ou un document — et a re-appliquer en relisant ses propres '+'.
---

# Prose de Claude — claire, lisible, compréhensible, concise

**Toujours applicable.** Un LLM qui vient de raisonner longuement a une pulsion forte de **déverser ce raisonnement** : en KDoc, en paragraphe d'intro, en récapitulatif. C'est le mode d'échec par défaut. Ce skill est la barre à repasser sur **chaque ligne écrite**.

Ce skill porte la **forme**. Il ne juge ni le métier (skill `malt-judge-loop` — le juge ne contrôle plus la prose) ni la cible d'un document livré (skill `writing-for-humans` — conclusion en haut, cible non technique) ni le format des questions (skill `asking-the-user`).

---

## § LA BARRE — quatre critères, dans cet ordre

1. **Clair** — une idée par phrase, le vrai nom (identifiant du code, clé JIRA, libellé écran), jamais une périphrase.
2. **Lisible** — phrases courtes, pas de subordonnées empilées, pas de jargon décoratif, pas d'analogie.
3. **Compréhensible** — le lecteur visé sait quoi faire après avoir lu. S'il doit relire, c'est raté.
4. **Concis** — **raccourcir ≠ résumer** : on ne condense pas un paragraphe, on garde le seul fait qui porte de l'information et on jette le reste. S'il n'y en a aucun, on supprime tout le bloc.

---

## § COMMENTAIRES DANS LE CODE — RÈGLE ABSOLUE

**Défaut = AUCUN commentaire. Plafond dur = 1 à 2 lignes.** Le nom, le test et le ticket JIRA portent l'explication. Le raisonnement va dans la **description de MR** et le **commentaire JIRA de tradeoffs**, jamais dans le fichier source. Un commentaire de 3 lignes ou plus est un défaut, sans exception d'« ampleur du sujet » : pas de titres markdown (`## Why this exists`), pas de listes à puces, pas de paragraphes.

**Un commentaire ne survit que s'il porte un fait impossible à lire dans le code** et dont l'ignorance ferait commettre une erreur :
- un invariant ou un piège non évident (« `exists` avale un refus en `false` — utiliser `isPresent` ») ;
- une contrainte externe que le code ne peut pas exprimer (quirk NetSuite, comportement legacy, ordre/concurrence, unité ou scale) ;
- un « pourquoi PAS la solution évidente » qui empêche une modif plausible mais fausse ;
- `TODO` / `FIXME`, message de `@Deprecated` ;
- les **directives outillage**, jamais touchées : `ktlint-disable`, `noinspection`, `language=SQL`, `eslint-disable*`, `@ts-ignore`, `prettier-ignore`, en-têtes de licence.

**Interdits, à supprimer à vue :**
- toute reformulation du nom de la classe / méthode / propriété / test ;
- toute **explication métier** — elle vit dans JIRA, pas dans le code ;
- tout **récit de ticket** : « BILL-1234 — pourquoi on a fait ça », historique, « avant ce ticket… », « used to… », verdicts de revue, justifications de choix passés ;
- toute **énumération d'appelants / d'émetteurs / de seams**, et tout renvoi au KDoc d'une autre classe ;
- `NOTE:` / `IMPORTANT:` / « Companion to… » / essais de rationalisation ;
- `@param` / `@return` / `@throws` qui ne font que répéter le nom ou le type ;
- commentaire de fin de ligne qui paraphrase la ligne ;
- `// given` / `// when` / `// then` et « ce test vérifie que… » quand le test se lit déjà ainsi ;
- code commenté.

---

## § OÙ ÇA MORD

- **Avant chaque push** : relire les lignes `+` de commentaire du diff et supprimer tout ce qui ne passe pas la barre. **C'est MOI qui le fais** — le juge ne le contrôle plus.
- **Sous-agent d'implémentation** (`malt-orchestration`) : la consigne de délégation rappelle le plafond explicitement, sinon le sous-agent produit le déversement.
- **Champ `Prompt` d'un ticket** (`/plan`, `/hotfix`) : ne jamais y demander « documenter le raisonnement en commentaire ». Le contexte du fix va dans le `Prompt`.
- **Écrits externes** (JIRA, GitLab, Notion) : même barre, **en anglais** (CLAUDE.md § LANGUE DES ÉCRITURES EXTERNES) ; pour un document lu par un humain, charger aussi `writing-for-humans`.
- **Réponses à l'utilisateur** : caveman actif par défaut (skill `caveman`) — ce skill reste la barre de fond quand caveman est désactivé.

---

## § RED FLAGS — réécrire avant d'envoyer

- Un commentaire ajouté qui dépasse 2 lignes, ou qui commence par `/**` alors que la méthode est déjà nommée.
- « En gros », « autrement dit », « c'est un peu comme », une analogie, une mise en situation.
- Un paragraphe d'intro qui annonce ce que le texte va dire, ou un récapitulatif qui redit ce qui précède.
- Une liste à puces dont chaque puce est une phrase complète redondante avec la précédente.
- Un adverbe d'emphase (« simplement », « clairement », « évidemment ») qui n'ajoute aucun fait.
