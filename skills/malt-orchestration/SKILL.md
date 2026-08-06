---
name: malt-orchestration
description: Comment Claude travaille sur le repo Malt — orchestration par sous-agents (thread principal = orchestrateur, déléguer exploration/recherche/analyse, CONCLUSION pas dumps), dosage du model des sous-agents (haiku/sonnet/opus selon la difficulté réelle), gestion du contexte (/clear, /compact, /rewind), et état temporaire via fichiers /tmp. À charger quand on délègue à des sous-agents, qu'on dimensionne un model, qu'on gère le contexte, ou qu'on transite de gros volumes entre étapes.
---

# Orchestration & contexte — repo Malt

## Orchestration par sous-agents

**Thread principal = orchestrateur uniquement.** Toute tâche longue ou gourmande en contexte → déléguer à un sous-agent (évite l'auto-compact : le contexte principal sature trop vite).

**Déléguer à un sous-agent :**
- Exploration / recherche code (plusieurs fichiers, localiser un domaine, comprendre une archi). Sur repo Malt : skill `malt-accounting-domain` ou note Obsidian d'abord, sous-agent si insuffisant.
- Recherche multi-fichiers, sweep de conventions, grep large.
- Analyse de gros outputs (logs, dumps, résultats de build).
- Toute tâche multi-étapes qui lirait > 2-3 fichiers entiers.

**Le sous-agent retourne une CONCLUSION, pas les dumps de fichiers** — c'est ce qui économise le contexte. Gros volume à transiter → fichier `/tmp` (cf. bas de page), le sous-agent écrit, le thread principal lit le résumé.

**Thread principal garde :** décisions, synthèses, arbitrages, édition ciblée d'un fichier déjà localisé, interaction utilisateur, dispatch + agrégation.

**Parallélisation :** sous-tâches indépendantes → plusieurs sous-agents dans le même message.

**Subagents réutilisables (`.claude/agents/`)** — les préférer aux `Agent` ad-hoc :
- **`explorer`** (`sonnet`, read-only) : localiser/explorer, retourne `path:line` + pattern jumeau, jamais de dump.
- **`reviewer`** (`opus`) : revue adverse d'un diff en contexte frais, retourne des GAPS correctness/scope.
- **`smoke-runner`** (`haiku`) : `bootRun` + verdict `BOOTED_OK`/`BOOT_FAILED`.

**Pas de sous-agent** pour une action triviale (1 fichier connu, 1 commande) ou une question conversationnelle directe. Doute sur la longueur → déléguer.

## Dosage du model des sous-agents

Chaque `Agent` créé DOIT dimensionner son `model` à la difficulté réelle — jamais sur-dimensionné. L'orchestrateur reste sur son propre model ; seul le sous-agent est calibré. **Ne concerne QUE les sous-agents `Agent`, PAS les surfaces CMUX** (`cmux-tab.sh spawn` lance un Claude complet, model géré par CMUX).

- **`haiku`** : mécanique/déterministe, zéro raisonnement — grep, lister des fichiers, extraire un texte ADF, tailer/grep un log, lookup `path:line` d'un symbole connu, appliquer un patch trivial déjà spécifié.
- **`sonnet`** : standard — exploration/localisation, lecture multi-fichiers, tests jumeaux, implémentation bornée et bien cadrée, sweep de conventions, relecture Sonar.
- **`opus`** : fort raisonnement — cause racine, design/archi, arbitrage non trivial, revue adverse, implémentation piégeuse (invariants, concurrence, event-sourcing), découpage architectural difficile.

**Défaut : commencer au model le PLUS BAS plausible**, remonter d'un cran si la tâche l'exige. Échec par manque de capacité → relancer au cran au-dessus. Jamais `opus` par réflexe sur de l'exploration ou du mécanique.

## Gestion du contexte (commandes natives)

Le contexte est la ressource rare. En complément de la délégation :
- **`/clear` entre tâches non liées.** Après 2 corrections ratées sur le même point → `/clear` + prompt plus précis (session propre > longue session encombrée).
- **Compaction** : à chaque `/compact`, préserver impérativement — fichiers modifiés, lien+numéro MR, ticket JIRA + statut, état du `/goal`, décisions/tradeoffs. `/compact <instruction>` pour cibler.
- **`/rewind`** pour tenter une approche risquée sans polluer le contexte de tentatives ratées.
- **Preuve, pas ré-exécution** : les sous-agents remontent une CONCLUSION citant la sortie réelle.

## État temporaire — fichiers /tmp

Transiter les données volumineuses entre étapes via `/tmp`. Header d'index obligatoire :

```
# TMP_INDEX
# created: <date>
# purpose: <une ligne>
# sections: [liste si multi-parties]
# cleanup: supprimer après <session|tâche X>
---
```

Nommer `/tmp/claude_<tâche>_<type>.md` ; un fichier par type de données ; supprimer en fin de tâche sauf demande de garder ; plusieurs fichiers liés → `/tmp/claude_session_index.md` qui pointe vers chacun.
