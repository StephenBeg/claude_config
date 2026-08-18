---
name: malt-orchestration
description: Comment Claude travaille sur le repo Malt — orchestration par sous-agents (thread principal = orchestrateur, déléguer exploration/recherche/analyse, CONCLUSION pas dumps), dosage du model des sous-agents (haiku/sonnet/opus selon la difficulté réelle), gestion du contexte (/clear, /compact, /rewind), et état temporaire via fichiers de travail sous ~/tmp/scratch (JAMAIS /tmp, purgé par macOS). À charger quand on délègue à des sous-agents, qu'on dimensionne un model, qu'on gère le contexte, ou qu'on transite de gros volumes entre étapes.
---

# Orchestration & contexte — repo Malt

## Orchestration par sous-agents

**Thread principal = orchestrateur uniquement.** Toute tâche longue ou gourmande en contexte → déléguer à un sous-agent (évite l'auto-compact : le contexte principal sature trop vite).

**Déléguer à un sous-agent :**
- Exploration / recherche code (plusieurs fichiers, localiser un domaine, comprendre une archi). Sur repo Malt : skill `malt-accounting-domain` ou note Obsidian d'abord, sous-agent si insuffisant.
- Recherche multi-fichiers, sweep de conventions, grep large.
- Analyse de gros outputs (logs, dumps, résultats de build).
- Toute tâche multi-étapes qui lirait > 2-3 fichiers entiers.

**Le sous-agent retourne une CONCLUSION, pas les dumps de fichiers** — c'est ce qui économise le contexte. Gros volume à transiter → fichier `~/tmp/scratch/` (cf. bas de page ; jamais `/tmp`), le sous-agent écrit, le thread principal lit le résumé.

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

## Délégation de l'implémentation — plan Opus → exécution moins chère (RÈGLE ABSOLUE)

**La surface `/dev` ou `/hotfix` tourne en Opus. Opus est cher : il doit servir au RAISONNEMENT (plan, cause racine, archi, arbitrage, revue), PAS à taper du code déterministe.** Symptôme d'anti-pattern : la consommation d'une session `/dev`/`/hotfix` est 100 % Opus → c'est qu'Opus a écrit les tests et le code inline au lieu de déléguer.

**Protocole obligatoire dès que le comportement à écrire est cadré :**

1. **Opus (surface) produit un PLAN D'IMPLÉMENTATION PRÉCIS** — le contrat de délégation. Assez détaillé pour qu'un `sonnet` l'exécute sans rien inventer : fichiers exacts (`path:line`), signatures, pattern jumeau à copier (`path:line` du test/impl existant à imiter), liste des tests à écrire (titres validés au GATE) + ce que chacun doit exercer, invariants/pièges. C'est CE plan qui reste dans le contexte Opus — pas le code produit.
2. **Opus délègue tests + implémentation à un sous-agent `sonnet`** (voir Dosage) qui exécute le plan : écrit les tests, le code de prod, boucle rouge→vert, et retourne une **CONCLUSION** (fichiers touchés, sortie de test verte citée, écarts au plan). L'agent d'impl a accès en écriture (Edit/Write/Bash) — cf. `[[feedback_explore_agent_can_write_via_bash]]`.
3. **Découper** si le diff couvre plusieurs zones indépendantes → un sous-agent par zone (parallèle, même message).
4. **Opus reprend la main** pour vérifier (revue adverse, `/goal`, smoke-run) et arbitrer — jamais pour taper le code lui-même.

**Garder sur Opus (NE PAS déléguer) :** le plan précis lui-même, le GATE liste-de-tests utilisateur, l'escalade archi/tradeoff, la revue adverse, la cause racine d'un bug tordu, et **l'implémentation réellement piégeuse** (invariants subtils, concurrence, event-sourcing non trivial) — là où un `sonnet` échouerait, cf. Dosage `opus`. Le critère de délégation = **exhaustif + déterministe** : si le plan est assez précis pour être exécuté mécaniquement, il DOIT partir en `sonnet`.

**Défaut d'exécution = `sonnet`** (impl bornée et bien cadrée). `haiku` si purement mécanique (patch déjà spécifié à la ligne près). Remonter `opus` seulement si l'exécution révèle un piège que le plan n'avait pas tranché — et alors re-planifier, pas coder inline en douce.

**Tâches de plomberie déléguées aussi (ne PAS les faire en Opus inline) :**
- **`haiku` — mises à jour JIRA** : transitions de statut (`In Progress` → `Review` → `To Validate`), auto-assignation, pose de labels, ajout d'un commentaire déjà rédigé. Appels API déterministes (curl `/rest/api/3/...`), zéro raisonnement. Opus fournit la valeur (statut cible, texte du commentaire), `haiku` exécute l'appel.
- **`haiku` — récupération Datadog / Sentry** : lancer une requête (`/datadog` `pup`, ou fetch d'une issue Sentry) et remonter les logs/traces/stacktrace/métriques bruts pertinents en CONCLUSION. Extraction mécanique, filtrée sur la fenêtre/le service demandés. Opus fournit la requête cible et **interprète** le résultat (cause racine) — le fetch reste en `haiku`.
- **`sonnet` — suivi de MR / pipeline** : lookup de statut de pipeline, lecture des notes de MR, diagnostic d'un job rouge, boucle d'attente (skill `malt-pipeline-followup`). Opus ne reprend la main que pour un arbitrage (fix non trivial d'un job cassé, désaccord sur un commentaire de review). Le polling et le triage mécanique restent en `sonnet`.

Ne réserver à Opus, dans la plomberie, que la **rédaction** d'un texte à enjeu (description de MR, commentaire de réponse à une review, contenu d'un ticket) et l'**arbitrage** — jamais l'appel API ni le poll eux-mêmes.

## Gestion du contexte (commandes natives)

Le contexte est la ressource rare. En complément de la délégation :
- **`/clear` entre tâches non liées.** Après 2 corrections ratées sur le même point → `/clear` + prompt plus précis (session propre > longue session encombrée).
- **Compaction** : à chaque `/compact`, préserver impérativement — fichiers modifiés, lien+numéro MR, ticket JIRA + statut, état du `/goal`, décisions/tradeoffs. `/compact <instruction>` pour cibler.
- **`/rewind`** pour tenter une approche risquée sans polluer le contexte de tentatives ratées.
- **Preuve, pas ré-exécution** : les sous-agents remontent une CONCLUSION citant la sortie réelle.

## État temporaire — fichiers de travail sous `~/tmp/scratch/`

**RÈGLE ABSOLUE — JAMAIS `/tmp` (ni `/private/tmp`, ni `/var/folders`).** macOS purge ces dossiers sans prévenir : un chantier long y a déjà perdu tous ses fichiers d'état en cours de route. **Tout fichier que Claude écrit hors repo vit sous le répertoire utilisateur.**

| Nature | Emplacement |
|---|---|
| Scratch / transit de gros volumes entre étapes | `~/tmp/scratch/` |
| Journal de session quotidien (`/end`, `/daily`) | `~/tmp/YYYY-MM-DD.md` |
| Bus d'échange + `STATUS_DIR` d'un chantier orchestré | `~/claude-exchange-llm/<WORKFLOW>/` (skill `malt-surface-exchange`) |
| Mémoire persistante | `~/.claude/projects/<projet>/memory/` |

Seule exception tolérée : un fichier consommé **dans la même commande** que celle qui l'a créé (`mktemp` d'un pipe). Dès qu'un fichier doit survivre à un tour, il va sous `~/tmp/scratch/`.

Transiter les données volumineuses entre étapes via `~/tmp/scratch/`. Header d'index obligatoire :

```
# TMP_INDEX
# created: <date>
# purpose: <une ligne>
# sections: [liste si multi-parties]
# cleanup: supprimer après <session|tâche X>
---
```

Nommer `~/tmp/scratch/claude_<tâche>_<type>.md` (`mkdir -p ~/tmp/scratch` au besoin) ; un fichier par type de données ; supprimer en fin de tâche sauf demande de garder ; plusieurs fichiers liés → `~/tmp/scratch/claude_session_index.md` qui pointe vers chacun.
