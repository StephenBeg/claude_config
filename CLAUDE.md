# Instructions globales

## CAVEMAN — mode réponse (TOUJOURS ACTIF)

**Niveau défaut : full.** Changer : `/caveman lite|full|ultra`.
Désactiver : "stop caveman" / "mode normal".

**Supprime :** articles, mots de remplissage, politesses, hésitations.
**Garde :** substance technique, termes exacts, blocs de code intacts.
**Pattern :** `[chose] [action] [raison]. [étape suivante].`

```
❌ "Bien sûr ! Je serais ravi d'aider. Le problème est probablement..."
✅ "Bug middleware auth. Expiry utilise `<` pas `<=`. Correction :"
```

**Exceptions — passe en prose normale :**
- Avertissement sécurité
- Confirmation action irréversible
- Séquence multi-étapes où compression risque mauvaise lecture
- Ambiguïté technique causée par compression

Reprend caveman après exception.

---

## PRINCIPES — OBLIGATOIRES

- Direct. Zéro jargon. Zéro blabla.
- Montre raisonnement. Jamais hypothèse silencieuse.
- Vérifie avant d'affirmer. Lis code source, lis docs fournies.
- Pas de cleanup non demandé. Reste sur tâche.

---

## ORCHESTRATION PAR SOUS-AGENTS — RÈGLE ABSOLUE

**Thread principal = orchestrateur uniquement.** Toute tâche longue ou gourmande en contexte → déléguer à un sous-agent. But : éviter l'auto-compact (le contexte principal sature trop vite).

**DOIT déléguer à un sous-agent :**
- Exploration / recherche code (lire plusieurs fichiers, localiser un domaine, comprendre une archi). Sur repo Malt : note Obsidian d'abord (voir CONTEXTE MONOREPO MALT), sous-agent si la note ne suffit pas.
- Recherche multi-fichiers, sweep de conventions, grep large.
- Analyse de gros outputs (logs, dumps, résultats de build volumineux).
- Toute tâche multi-étapes qui lirait > 2-3 fichiers entiers.
- Tests → déjà couvert par COUVERTURE DE CODE (`malt-test-coverage` délègue l'exploration).

**Le sous-agent retourne une CONCLUSION, pas les dumps de fichiers.** C'est ce qui économise le contexte principal. Si un sous-agent doit transiter beaucoup de données → fichier `/tmp` (voir section ÉTAT TEMPORAIRE), le sous-agent écrit, le thread principal lit le résumé.

**Thread principal garde seulement :**
- Décisions, synthèses, arbitrages.
- Édition ciblée d'un fichier déjà localisé.
- Interaction avec l'utilisateur.
- Dispatch + agrégation des sous-agents.

**Parallélisation :** sous-tâches indépendantes → lancer plusieurs sous-agents dans le même message (exécution concurrente).

**Exceptions — pas de sous-agent :** action triviale (1 fichier déjà connu, 1 commande), question conversationnelle directe. En cas de doute sur la longueur → déléguer.

---

## COUVERTURE DE CODE — RÈGLE ABSOLUE

**Toute ligne ajoutée ou modifiée DOIT être couverte par un test.** Aucun code de production livré sans test exerçant les lignes touchées.

- Nouveau comportement → TDD (skill `malt-backend-tdd`).
- Couverture sur code déjà écrit (le code existe, pas de cycle rouge-vert) → skill `malt-test-coverage` (délègue l'exploration à un subagent, copie le test jumeau le plus proche).
- **Avant de déclarer une tâche terminée** : vérifier que chaque ligne ajoutée/modifiée est exercée par au moins un test, puis lancer les tests concernés — vert obligatoire.
- Exceptions tolérées : code généré, config triviale, logs purs. En cas de doute → couvrir.

---

## SKILLS — déclenchement automatique

| Contexte | Skill |
|---|---|
| Écrire/lire Obsidian (second cerveau local) | `obsidian` |
| Écrire/lire Notion | `notion` |
| Lire code, linters, build errors sur repo Malt | `intellij-mcp` |
| Ajouter/compléter couverture de tests sur code backend Malt déjà écrit | `malt-test-coverage` |
| Comprendre archi / localiser code / naviguer monorepo Malt | `notes-research` → note `[[Monorepo Malt - Carte technique]]` |

---

## CONTEXTE MONOREPO MALT — pré-analyse (économie de contexte)

**Avant d'explorer le repo Malt** (structure, build, où vit un domaine, conventions de test), lis la note Obsidian via `notes-research` :
- Point d'entrée : `[[Monorepo Malt - Carte technique]]` (carte navigation back/front + lookup tables).
- Patterns : `[[Architecture Backend]]`, `[[Architecture Frontend Nuxt]]`.
- Sous-système le plus documenté : hub `[[NetSuite Connector]]`.

Réutilise cette pré-analyse au lieu de re-scanner → économise tokens + contexte.

**DRIFT — règle absolue :** le repo évolue. Si le code réel contredit la note (localisation, version, convention déplacée), **mets à jour la note Obsidian** (skill `notes`) dans la foulée — corrige la ligne fautive, garde la note dense. Ne laisse jamais une carte périmée.

---

## TITRE DE SESSION — RÈGLE ABSOLUE

Quand le sujet d'une session concerne un ticket (Jira, Linear, etc.), le **titre de la conversation DOIT commencer par le numéro de ticket**.

Format : `TICKET-123 description courte`

Exemples :
- ✅ `BILL-2443 spike REST TBA auth`
- ✅ `PAY-4078 send command to ERP`
- ❌ `Spike sur l'authentification NetSuite`
- ❌ `Fix bug paiement`

---

## GIT WORKFLOW — RÈGLE ABSOLUE

**Ne jamais push directement sur `master`.** Toujours passer par branche + MR.

**TOUJOURS utiliser un worktree** (permet la parallélisation). Worktree **hors du repo** pour éviter les artefacts dans `git status`.

Workflow obligatoire :
1. **Depuis le repo principal uniquement** (`cd ~/Documents/projects/malt`), jamais depuis un worktree existant :
   ```
   cd ~/Documents/projects/malt
   git fetch origin master
   git worktree add ~/worktrees/malt/TICKET -b TICKET-description origin/master
   ```
   — **toujours spécifier `origin/master` comme base** : sans ça, git prend le HEAD courant (qui peut être une feature branch → worktree vide ou mauvaise base).

2. **Vérifier le worktree avant tout travail** :
   ```
   cd ~/worktrees/malt/TICKET
   git status        # doit afficher "On branch TICKET-description, nothing to commit"
   git log --oneline -3  # doit montrer les commits de master
   ```
   Si la branche est vide ou pointe ailleurs → stopper et recréer le worktree.

3. **Tous les git add/commit/push** depuis `~/worktrees/malt/TICKET`, jamais depuis le repo principal ni un autre worktree.

4. `git push origin TICKET-description`

5. Après merge : `git worktree remove ~/worktrees/malt/TICKET`

Ne pas utiliser l'outil `EnterWorktree` (crée le worktree dans `.claude/worktrees/` à l'intérieur du repo → pollue `git status`).

**Avant tout `git push` : vérifier que la branche courante n'est PAS `master`.**

**Interdictions absolues :**
- **Jamais créer la MR** (`glab mr create` ou équivalent) — uniquement push la branche, l'humain crée la MR.
- **Jamais se mettre en co-author** dans les commits (pas de `Co-Authored-By: Claude` ni aucune variante).

---

## ÉTAT TEMPORAIRE — fichiers /tmp

**DOIT utiliser `/tmp` pour transiter des données volumineuses entre étapes.**

Quand utiliser : résultats intermédiaires trop grands pour contexte, état à passer entre appels d'outils, données à réutiliser dans la session.

**Format obligatoire — header d'index en début de fichier :**

```
# TMP_INDEX
# created: <date>
# purpose: <une ligne — ce que contient ce fichier>
# sections: [liste des sections si fichier multi-parties]
# cleanup: supprimer après <session|tâche X>
---
```

**Règles :**
- Nommer clairement : `/tmp/claude_<tâche>_<type>.md` (ex: `/tmp/claude_research_sources.md`)
- Un fichier par type de données (ne pas mélanger sources + résultats dans le même fichier)
- Supprimer à la fin de la tâche sauf si l'utilisateur demande de garder
- Si plusieurs fichiers liés : créer `/tmp/claude_session_index.md` pointant vers chacun
