---
name: malt-judge-loop
description: Protocole du JUGE METIER en sous-agent : UN SEUL round de controle radical-honesty, a UN SEUL checkpoint, juste avant la livraison (push, ou SPIKE DONE pour /plan). Perimetre strictement metier (besoin couvert, meilleure solution, pieges du domaine, cas de test metier). NEEDS_WORK -> corriger chaque GAP avec preuve lisible puis escalader [ASK], jamais de round 2 automatique. Fichier de compte rendu SURFACE_FILE. Source de verite unique — invoque par /dev, /hotfix, /plan.
---

# Judge — sous-agent MÉTIER frais, UN SEUL round avant livraison

Rend le **LLM-as-judge** **traçable** (compte rendu écrit, contexte frais) sans le rendre coûteux : **un seul passage, au dernier moment utile**, au lieu d'une boucle de rounds répétée à deux checkpoints.

**PÉRIMÈTRE — MÉTIER UNIQUEMENT (RÈGLE ABSOLUE).** Le juge ne contrôle QUE : (1) le besoin est-il réellement couvert, (2) y avait-il mieux à faire, (3) quels pièges du domaine sont ignorés, (4) les cas de test métier sont-ils les bons et en manque-t-il. **Tout le reste est hors de son périmètre** — ktlint, style, nommage, commentaires, compilation, tests rouges, coverage chiffrée, imports, micro-perf : ces défauts sont attrapés par les hooks, les gates et la pipeline sans lui. **Il ne lance ni build ni test** : le vert est exigé par le gate `pre-push`, pas par le juge. Un GAP non métier remonté par un juge est une faute — le traiter comme du bruit, pas comme un blocage.

**Le juge n'est PAS une surface CMUX.** C'est un **sous-agent `judge`** lancé par la surface elle-même (dev/hotfix/plan), en contexte frais. Son compte rendu est écrit dans le **fichier de compte rendu de la surface** — `SURFACE_FILE` (§ FICHIER DE COMPTE RENDU) ; le rôle exact de ce fichier (inbox orchestrée ou fichier solo) est défini par le skill `malt-surface-exchange`, invoqué séparément quand le contexte est orchestré/multi-surface.

Toutes les sections sont des **RÈGLES ABSOLUES**.

---

## § ROUND JUGE UNIQUE — un seul checkpoint, un seul passage

**S'applique EN SOLO COMME EN ORCHESTRÉ.** Le juge est un **sous-agent `judge`** (`Agent` tool, `subagent_type: "judge"`), lancé **par la surface elle-même**, en contexte frais, **synchrone** (`run_in_background: false` — on a besoin du verdict pour continuer). Il **remplace** le subagent `reviewer` à ce checkpoint.

**RÈGLE ABSOLUE — UN SEUL CHECKPOINT, À LA TOUTE FIN.**
- `/dev` : step 4, `CHECKPOINT=pre-push` — **juste avant le push**, code écrit et tests verts.
- `/hotfix` : step 7b, `CHECKPOINT=hotfix-verify` — même position.
- `/plan` : step 10, `CHECKPOINT=plan-gate` — avant de passer le SPIKE en DONE (il n'y a pas de push à juger).

**Il n'existe PLUS de gate juge pré-implémentation** (`dev-plan-gate`, `hotfix-plan-gate` : supprimés). Un plan d'impl ou une cause racine douteuse se tranche avec l'utilisateur (§ DÉCISIONS D'ARCHI & TRADEOFFS du skill `malt-workflow-commons`), pas avec un juge.

**RÈGLE ABSOLUE — UN SEUL ROUND.** Un appel `Agent` unique, en contexte frais. Pas de boucle, pas de round 2 automatique, jamais de `SendMessage` vers un juge déjà utilisé. Le coût d'un juge est la raison de cette borne : elle n'est pas négociable au cas par cas.

**Fichier de compte rendu (`SURFACE_FILE`).** Avant le round, poser :
- **orchestré** (skill `malt-surface-exchange`) → `SURFACE_FILE="$WF/<T>.md"` (l'inbox propre de la surface) ;
- **solo** → `SURFACE_FILE=/Users/stephenbegot/claude-exchange-llm/_solo/<TICKET>.md`, créé si absent (`mkdir -p` + `pair-init`, header = ticket + « mode solo »).

C'est **le juge** qui y append son compte rendu (`JUDGE-VERDICT: …` + preuves). La surface ne recopie rien.

**Protocole :**
1. **Lancer le juge** avec un prompt **auto-suffisant** (il vérifie tout lui-même, il n'a AUCUN contexte) :
   ```
   Agent(subagent_type: "judge", run_in_background: false, description: "judge <T>", prompt:
     "CHECKPOINT=<pre-push | hotfix-verify | plan-gate>  ROUND=1  TICKET=<T>
      WORKTREE=<chemin absolu>  BRANCH=<branche>   (plan-gate : UMBRELLA + clés des tickets créés + DAG, pas de diff)
      REPORT_FILE=<SURFACE_FILE>
      CONSIGNE=<le champ Prompt / la consigne exacte, verbatim>
      CE QUE JE PRÉTENDS AVOIR FAIT=<…, avec les CAS MÉTIER censés être couverts par les tests>")
   ```
2. **Lire le verdict retourné** (et le compte rendu dans `SURFACE_FILE`) :
   - `VERDICT: OK` → checkpoint franchi, pousser (le hook enregistre le verdict, le gate `pre-push` s'ouvre).
   - `VERDICT: NEEDS_WORK` → § APRÈS UN NEEDS_WORK ci-dessous. **Ne pas relancer un juge de sa propre initiative.**
3. **Notifier** (mode orchestré, skill `malt-surface-exchange` § NOTIFICATION) : `note "$WF/_inbox/orchestrator.md" "<T>[dev]" "STEP:judge" "OK|NEEDS_WORK (<résumé>)"`.

Le passage est **entièrement contenu dans la surface** : aucune attente inter-surfaces, aucun `await-note`.

**HEURES CALMES 20h–7h** (CLAUDE.md) : un round de juge est un appel synchrone borné, pas un poll — il est autorisé. Ce qui reste interdit dans la plage : programmer un réveil/poll après le verdict.

---

## § APRÈS UN NEEDS_WORK — corriger avec preuve, puis ESCALADER

Le round est unique : un `NEEDS_WORK` **ne se rattrape pas** par un second juge lancé tout seul. La suite est fixe :

1. **Trier les GAPS.** Un GAP hors périmètre métier (lint, style, commentaire, test rouge, coverage) est du bruit : le noter et passer — les hooks et la CI s'en chargent.
2. **Traiter toute l'étendue de chaque GAP métier**, pas seulement l'exemple cité (le juge dit « cas limite X non testé sur la méthode Y » → couvrir aussi les cas analogues de la même méthode).
3. **Produire la preuve de clôture, lisible, GAP par GAP** : `path:line` du comportement métier désormais écrit, nom du test qui exerce le cas métier manquant et ce qu'il assert, endroit où la règle du domaine ignorée est appliquée. « Je pense l'avoir corrigé » sans `path:line` ni test cité = GAP encore ouvert.
4. **Escalader à l'utilisateur** — onglet `[ASK]`, skill `asking-the-user` : les GAPS du juge, ce que j'ai corrigé avec les preuves ci-dessus, ce qui reste ouvert et pourquoi. **C'est lui qui tranche** : pousser tel quel, corriger autrement, ou autoriser explicitement un second juge.
5. **Un second juge ne se lance QUE sur cette autorisation explicite.**

**Conséquence sur le gate `pre-push`** (il exige un `VERDICT: OK` enregistré) : un `NEEDS_WORK` laisse le push refusé. Si l'utilisateur donne son GO sans nouveau juge, lever le gate en éditant `~/.claude/wf-gates.conf` → `pre-push = warn` (effet immédiat, relu à chaque appel), puis le remettre à `block` après le push. Ne jamais contourner le gate autrement.

---

## § RÔLE DU JUGE MÉTIER (sous-agent `judge`)

Le prompt système complet vit dans `~/.claude/agents/judge.md`. Invariants portés ici (source de vérité) :

- **Contexte frais.** Il n'a jamais vu le code produit autrement que par ce que la requête lui dit — et il vérifie ce qu'on lui dit.
- **VÉRIFICATION FRAÎCHE, JAMAIS LA MÉMOIRE.** Ni mémoire persistante, ni notes Obsidian comme vérité. Il **rétablit tout lui-même** : `git diff` réel dans le worktree indiqué, code réel `path:line`, **lecture** des tests (jamais leur exécution), logs Datadog/Sentry si le besoin l'exige, tickets JIRA réels. Tout verdict cite une **preuve réelle**.
- **EXHAUSTIVITÉ EN UN PASSAGE — vital ici.** Il n'y a pas de round suivant : le verdict unique doit lister TOUS les GAPS des quatre dimensions d'un coup.
- **RADICAL HONESTY · NEUTRE · FIABLE.** Il cherche à **réfuter** que le BESOIN est correctement résolu, sur quatre dimensions et quatre seulement : exigence de la consigne non satisfaite · meilleure solution métier ignorée (pattern jumeau, règle déjà portée ailleurs) · piège du domaine (invariant, idempotence/rejeu, parité legacy, données de prod, rétrocompat, ordre/concurrence) · cas de test métier faux ou manquant. Verdict `OK` seulement si aucun GAP métier ne subsiste ; sinon `NEEDS_WORK` + GAPS précis et actionnables (`path:line`, cas métier manquant). Ni complaisance, ni chicane.
- **NE CONTRÔLE PAS la forme du code.** Ktlint, style, nommage, **commentaires**, compilation, tests rouges, coverage chiffrée, imports, micro-perf : hors périmètre, jamais remontés — les hooks, les gates et la pipeline s'en chargent. La discipline de commentaire est portée par le skill `claude-prose`, plus par le juge. **Il ne lance ni build ni test** : le vert est exigé par le gate `pre-push`.
- **Ne code rien, ne touche aucun worktree, ne lance aucun build/test** (lecture seule). Sa **seule écriture** est son compte rendu dans le `REPORT_FILE`/`SURFACE_FILE` de la surface — trace auditable.
