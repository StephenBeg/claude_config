---
name: malt-test-coverage
description: Use when adding or completing test coverage on already-written backend code (Malt/Kotlin) — code exists, no red-green cycle. Prioritizes a clean context by delegating pattern extraction to a subagent instead of reading large files inline.
---

# Malt Test Coverage — couvrir du code déjà écrit

Ce skill sert à **ajouter de la couverture sur du code qui existe déjà** (Sonar flag, ligne modifiée non testée, dette). Ce n'est PAS du TDD : il n'y a pas de cycle rouge-vert, le code de production est là.

Pour du **nouveau comportement** → utiliser `malt-backend-tdd` à la place.
Pour les conventions d'assertion/fixtures → `malt-backend-testing`.

---

## Principe central — CONTEXTE PROPRE

Le coût d'une tâche de couverture n'est pas l'écriture, c'est la **lecture** : il faut connaître précisément les conventions du fichier test (helpers, extension functions, ordre des lignes, façon de mocker). Lire ces gros fichiers dans le contexte principal le fait déborder → compaction → re-lecture → explosion du coût.

**Règle d'or : déléguer la collecte de patterns à un subagent. Le subagent lit beaucoup, te rend peu.**

Mauvais : lire 4000 lignes inline pour écrire 200 lignes de test.
Bon : un agent `Explore` lit 4000 lignes, rend 50 lignes de synthèse, tu écris depuis cette synthèse.

---

## Workflow

### 1. Cadrer le scope (sans lire le code en entier)

- Identifier exactement les lignes/méthodes/classes à couvrir (sortie Sonar, diff git, demande).
- `grep`/recherche symbole pour localiser : la classe sous test, son fichier de test, le test « jumeau » le plus proche (même pattern : même type de service, même structure de retour).
- NE PAS lire de fichier test > 500 lignes en entier à ce stade.

### 2. Déléguer l'extraction de patterns à un subagent

Lancer un agent `Explore` (ou `general-purpose` si écriture nécessaire) avec un prompt qui demande une **synthèse compacte**, pas un dump. Exiger des extraits courts.

Prompt-type :

> Module : `<module>`. Je dois écrire des tests pour `<méthode(s)>` dans `<classe>`.
> Lis le code de prod concerné et le fichier de test existant. Rends-moi UNIQUEMENT, en extraits courts :
> 1. Le test existant le plus proche à copier (le bloc complet, 1 seul).
> 2. La liste des helpers de test réutilisables (mocks, fixtures, builders) avec leur signature.
> 3. Les extension functions / matchers d'assertion disponibles + comment les appeler.
> 4. Tout détail non-évident : ordre des lignes (ex. credit avant debit), clés d'arguments de specs, setup obligatoire (lock, clock, feature flags).
> 5. Le point d'insertion exact (fichier + ancre) pour les nouveaux tests.
> Pas de dump de fichier entier. Synthèse only.

Si plusieurs zones indépendantes à couvrir → lancer les subagents **en parallèle** (un message, plusieurs tool calls).

### 3. Écrire depuis la synthèse

- Copier le test jumeau, adapter aux nouvelles entrées/sorties.
- Réutiliser les helpers/matchers existants — ne pas réinventer.
- Couvrir : happy path + chemins malheureux (exception, not found, précondition violée) + variations forcées (devises, flags…).
- Respecter les conventions Malt : **Kotest** (`shouldBe`, `shouldThrow<E>`), doubles `InMemory*` via fixtures quand ils existent (sinon mockk si le fichier voisin le fait déjà), `@Nested inner class` par méthode sous test.

### 4. Vérifier — vert obligatoire

- Lancer les tests ciblés (`./gradlew :<projet>:test --tests "<FQN>"`). Trouver le bon chemin projet si ambigu (`./gradlew projects | grep`).
- Si un hook ktlint bloque sur des violations préexistantes du fichier touché (ex. `class-naming` sur des classes lowercase sans suppress) → ajouter `@file:Suppress("ktlint:standard:<rule>")` en tête de fichier (fix minimal, ne pas toucher les classes existantes).
- Confirmer que chaque ligne ajoutée/modifiée est exercée. En cas de doute sur la couverture réelle → croiser avec SonarQube (skill `sonarqube`).

---

## Règles de lecture — anti-gaspillage

- **Jamais** lire un fichier > ~500 lignes en entier pour en extraire 2 symboles → `grep` la cible, lire l'offset.
- **Jamais** charger plusieurs gros fichiers de test dans le contexte principal → déléguer.
- Si une **compaction se déclenche** sur une tâche de couverture → signal d'échec de méthode : tu aurais dû déléguer. Corriger l'approche, pas continuer.
- Une lecture inline est légitime uniquement pour : fichiers courts (< 250 lignes), le bloc précis renvoyé par le subagent qu'on adapte, le point d'insertion.

---

## Anti-patterns (vécus)

| Anti-pattern | Conséquence | À la place |
|---|---|---|
| Lire `DelayedPushStrategy.kt` (1115 l.) pour 2 specs | ~1075 lignes gaspillées | grep `*Spec` + lire 30 lignes |
| Lectures partielles répétées d'un test de 2000 l. | relectures, contexte qui gonfle | 1 subagent rend la synthèse |
| Explorer au fil de l'eau | débordement → compaction → re-lecture | cadrer puis déléguer en 1 passe |
| Réécrire helpers/matchers | divergence du style maison | copier le test jumeau |

---

## Git / livraison

Suivre les règles globales : worktree, branche `TICKET-desc`, commit sans co-author, push de la branche uniquement (pas de MR). Voir CLAUDE.md global.
