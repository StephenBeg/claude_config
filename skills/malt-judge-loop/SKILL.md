---
name: malt-judge-loop
description: Protocole du JUGE METIER en sous-agent : loop de controle radical-honesty avant livraison, un juge frais par round, perimetre strictement metier (besoin couvert, meilleure solution, pieges du domaine, cas de test metier), borne (2 rounds sur les gates /dev et /hotfix, 4 sur le gate /plan), fichier de compte rendu SURFACE_FILE. Source de verite unique — invoque par /dev, /hotfix, /plan.
---

# Judge loop — sous-agent MÉTIER frais, borné jusqu'au verdict OK

Rend le **LLM-as-judge** **itératif et traçable** (loop jusqu'à verdict OK, plafonné) au lieu d'un contrôle one-shot noyé dans le contexte qui a produit le travail.

**PÉRIMÈTRE — MÉTIER UNIQUEMENT (RÈGLE ABSOLUE).** Le juge ne contrôle QUE : (1) le besoin est-il réellement couvert, (2) y avait-il mieux à faire, (3) quels pièges du domaine sont ignorés, (4) les cas de test métier sont-ils les bons et en manque-t-il. **Tout le reste est hors de son périmètre** — ktlint, style, nommage, commentaires, compilation, tests rouges, coverage chiffrée, imports, micro-perf : ces défauts sont attrapés par les hooks, les gates et la pipeline sans lui. **Il ne lance ni build ni test** : le vert est exigé par le gate `pre-push`, pas par le juge. Un GAP non métier remonté par un juge est une faute — le traiter comme du bruit, pas comme un blocage.

**Le juge n'est PAS une surface CMUX.** C'est un **sous-agent `judge`** lancé par la surface elle-même (dev/hotfix/plan), en contexte frais, **un juge NEUF à chaque round**. Le compte rendu de chaque juge est écrit dans le **fichier de compte rendu de la surface** — `SURFACE_FILE` (§ FICHIER DE COMPTE RENDU) ; le rôle exact de ce fichier (inbox orchestrée ou fichier solo) est défini par le skill `malt-surface-exchange`, invoqué séparément quand le contexte est orchestré/multi-surface.

Toutes les sections sont des **RÈGLES ABSOLUES**.

---

## § LOOP JUGE — sous-agent frais par round, borné jusqu'au verdict OK ou 2 rounds (plan-gate `/plan` : 4)

**S'applique EN SOLO COMME EN ORCHESTRÉ.** Le juge est un **sous-agent `judge`** (`Agent` tool, `subagent_type: "judge"`), lancé **par la surface elle-même**, en contexte frais, **synchrone** (`run_in_background: false` — on a besoin du verdict pour continuer). Il **remplace** le subagent `reviewer` à ces checkpoints.

**RÈGLE ABSOLUE — UN JUGE NEUF PAR ROUND.** Chaque round lance un **nouvel** appel `Agent` : jamais de `SendMessage` vers un juge déjà utilisé, jamais de réutilisation de contexte. Un juge qui a vu le round N-1 n'est plus neutre. On reboucle jusqu'à ce qu'**un juge dise `OK`**.

**Checkpoints** : `/dev` a DEUX passages — step 1b `dev-plan-gate` (avant impl, juste après lecture du ticket/consigne) et step 4 `pre-push` (avant push) ; `/hotfix` a DEUX passages — step 5b `hotfix-plan-gate` (avant impl, juste après la cause racine confirmée) et step 7b `hotfix-verify` (avant push) ; `/plan` garde un seul passage, `plan-gate` (GATE avant SPIKE DONE).

**Pourquoi deux passages sur `/dev`/`/hotfix`.** Un juge unique en fin d'impl découvre souvent un problème d'archi/scope né dès le plan — corriger ça après coup déclenche plusieurs rounds de reprise. Faire relire le plan **avant** d'écrire le code intercepte ces GAPS pour le prix d'UN round, avant que le code ne soit à défaire.

**Fichier de compte rendu (`SURFACE_FILE`).** Avant le round 1, poser :
- **orchestré** (skill `malt-surface-exchange`) → `SURFACE_FILE="$WF/<T>.md"` (l'inbox propre de la surface) ;
- **solo** → `SURFACE_FILE=/Users/stephenbegot/claude-exchange-llm/_solo/<TICKET>.md`, créé si absent (`mkdir -p` + `pair-init`, header = ticket + « mode solo »).

C'est **le juge** qui y append son compte rendu (`JUDGE-VERDICT: … round N` + preuves). La surface ne recopie rien ; elle **relit le fichier** si elle a besoin de l'historique des rounds.

**Protocole du round** (`round N`, N à partir de 1) :
1. **Lancer un juge frais** avec un prompt **auto-suffisant** (il vérifie tout lui-même, il n'a AUCUN contexte) :
   ```
   Agent(subagent_type: "judge", run_in_background: false, description: "judge round N <T>", prompt:
     "CHECKPOINT=<dev-plan-gate | hotfix-plan-gate | pre-push | hotfix-verify | plan-gate>  ROUND=N  TICKET=<T>
      WORKTREE=<chemin absolu>  BRANCH=<branche>   (ou, *-plan-gate : consigne/cause racine + plan d'impl envisagé, pas encore de diff ; plan-gate/plan : UMBRELLA + clés des tickets créés + DAG)
      REPORT_FILE=<SURFACE_FILE>
      CONSIGNE=<le champ Prompt / la consigne exacte, verbatim>
      CE QUE JE PRÉTENDS AVOIR FAIT=<…, avec les CAS MÉTIER censés être couverts par les tests>
      GAPS DES ROUNDS PRÉCÉDENTS ET CE QUE J'AI CORRIGÉ=<… ou 'aucun, round 1'>")
   ```
2. **Lire le verdict retourné** (et le compte rendu dans `SURFACE_FILE`) :
   - `VERDICT: OK` → checkpoint franchi, continuer.
   - `VERDICT: NEEDS_WORK` → traiter **chaque GAP métier**, repush si besoin (`[IMPL]`/`[PIPE]`), puis **round N+1 avec un juge NEUF**. Les corrections ne valent jamais approbation : re-soumettre. **Un GAP hors périmètre métier remonté par erreur (lint, style, commentaire, test rouge) ne se traite pas dans ce loop** : il est déjà pris en charge par les hooks/CI — le noter et passer.

**RÈGLE ABSOLUE — PAS DE ROUND N+1 SANS PREUVE DE CLÔTURE PAR GAP.** Le juge est déjà exhaustif en un seul passage (round 1 liste TOUS les GAPS d'un coup — voir `judge.md` § EXHAUSTIVITÉ). Si un round N+1 retrouve encore quelque chose, ce n'est quasiment jamais que le juge a mal cherché : c'est que la correction du round N était **incomplète, bâclée, ou a introduit un effet de bord**, resoumise sans vérification. Métaphore : le juge dit « il manque 80 % du mur à peindre » — repeindre 20 % puis resoumettre en espérant que ça passe est **interdit**. Pour CHAQUE GAP du round N, avant de relancer un juge :
1. **Traiter toute l'étendue du GAP**, pas seulement l'exemple cité (le juge dit "cas limite X non testé sur la méthode Y" → vérifier s'il y a d'autres cas analogues non couverts sur la même méthode, pas seulement X).
2. Appliquer le fix.
3. **Produire la preuve de clôture spécifique à ce GAP — une preuve LISIBLE, pas une exécution** : le comportement métier manquant est désormais écrit dans le diff (`path:line` cité), le cas métier manquant est exercé par un test nommé (fichier + nom du test + ce qu'il assert), la règle du domaine ignorée est appliquée à l'endroit cité. Le juge ne lance rien : la preuve qu'il sait relire est du code et des cas de test, pas une sortie verte (le vert est exigé séparément par le gate `pre-push`).
4. **Un GAP n'est coché fermé QUE si cette preuve lisible existe.** "Je pense l'avoir corrigé" sans `path:line` ni cas de test cité = GAP encore ouvert — ne pas resoumettre tant que ce n'est pas fait.
5. Seulement quand TOUS les GAPS du round N sont fermés avec preuve → lancer le `judge` round N+1, en indiquant pour chaque GAP la preuve lisible dans `CE QUE J'AI CORRIGÉ` (pas une simple déclaration) — le juge round N+1 vérifie vite au lieu de tout redécouvrir.

3. **Borne dure — dépend du checkpoint :**
   - `dev-plan-gate` / `hotfix-plan-gate` (avant impl) et `pre-push` / `hotfix-verify` (avant push) : **2 rounds max** — round 1, puis si `NEEDS_WORK`, correction + **round 2 avec un juge NEUF** pour vérifier la correction (pas de round 3+). Le coût est tenu bas par les DEUX checkpoints qui interceptent tôt (plan) et tard (impl), pas par l'acharnement sur un seul.
   - `plan-gate` (`/plan`, GATE avant SPIKE DONE) : **4 rounds max** — inchangé, ce checkpoint reste seul sur son périmètre (pas de second passage en amont).
   - Toujours `NEEDS_WORK` à la dernière borne, ou désaccord technique argumenté → **STOPPER, escalader à l'utilisateur** (`[ASK]`) en citant les GAPS résiduels. Jamais d'acharnement, jamais franchir en ignorant un verdict.
4. **Notifier** (mode orchestré, skill `malt-surface-exchange` § NOTIFICATION) : `note "$WF/_inbox/orchestrator.md" "<T>[dev]" "STEP:judge" "round N → OK|NEEDS_WORK (<résumé>)"`.

Le loop est **entièrement contenu dans la surface** : aucune attente inter-surfaces, aucun `await-note`, aucune action de l'utilisateur. Un round ne « se perd » plus.

**HEURES CALMES 20h–7h** (CLAUDE.md) : un round de juge est un appel synchrone borné, pas un poll — il est autorisé. Ce qui reste interdit dans la plage : programmer un réveil/poll après le verdict.

---

## § RÔLE DU JUGE MÉTIER (sous-agent `judge`)

Le prompt système complet vit dans `~/.claude/agents/judge.md`. Invariants portés ici (source de vérité) :

- **Contexte frais, un juge par round.** Il n'a jamais vu le code produit ni les rounds précédents autrement que par ce que la requête lui dit — et il vérifie ce qu'on lui dit.
- **VÉRIFICATION FRAÎCHE, JAMAIS LA MÉMOIRE.** Ni mémoire persistante, ni notes Obsidian comme vérité. Il **rétablit tout lui-même** : `git diff` réel dans le worktree indiqué, code réel `path:line`, **lecture** des tests (jamais leur exécution), logs Datadog/Sentry si le besoin l'exige, tickets JIRA réels. Tout verdict cite une **preuve réelle**.
- **RADICAL HONESTY · NEUTRE · FIABLE.** Il cherche à **réfuter** que le BESOIN est correctement résolu, sur quatre dimensions et quatre seulement : exigence de la consigne non satisfaite · meilleure solution métier ignorée (pattern jumeau, règle déjà portée ailleurs) · piège du domaine (invariant, idempotence/rejeu, parité legacy, données de prod, rétrocompat, ordre/concurrence) · cas de test métier faux ou manquant. Verdict `OK` seulement si aucun GAP métier ne subsiste ; sinon `NEEDS_WORK` + GAPS précis et actionnables (`path:line`, cas métier manquant). Ni complaisance, ni chicane.
- **NE CONTRÔLE PAS la forme du code.** Ktlint, style, nommage, **commentaires**, compilation, tests rouges, coverage chiffrée, imports, micro-perf : hors périmètre, jamais remontés — les hooks, les gates et la pipeline s'en chargent. La discipline de commentaire est portée par le skill `claude-prose`, plus par le juge. **Il ne lance ni build ni test** : le vert est exigé par le gate `pre-push`.
- **Ne code rien, ne touche aucun worktree, ne lance aucun build/test** (lecture seule). Sa **seule écriture** est son compte rendu dans le `REPORT_FILE`/`SURFACE_FILE` de la surface — trace auditable de chaque round.
