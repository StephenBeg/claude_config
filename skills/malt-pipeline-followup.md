---
name: malt-pipeline-followup
description: Suivi de pipeline GitLab CI jusqu'au vert — lookup statut, pipelines parent-child (monorepo), diagnostic + fix + repush, intégration Sonar, conflits de rebase, boucle d'attente auto-cadencée, heures calmes. Source de vérité unique invoquée par /dev, /hotfix et malt-workflow-commons § /end AVEC MR — ne jamais recopier son contenu ailleurs, y renvoyer par le nom de section.
---

# Suivi de pipeline — /dev · /hotfix

Bloc unique qui régit **tout suivi de pipeline GitLab CI** une fois une MR ouverte : vérifier qu'elle est verte, diagnostiquer et fixer si elle est rouge (y compris Sonar), résoudre les conflits de rebase, et attendre proprement sans bloquer l'utilisateur. Invoqué par `/dev` (step 10, `[PIPE (numMR)]`), `/hotfix` (step 7c) et `malt-workflow-commons § /end AVEC MR`.

**Ne pas confondre avec le merge (step 13 de `/dev`/`/hotfix`)** : ce skill couvre la pipeline **verte**, pas la condition d'approbation (`Approved` de `@stephen.begot`) ni la procédure de merge elle-même — ces étapes restent dans les commandes.

---

## 1 — Lookup du statut

```
glab ci status                       # ou
glab api "projects/:id/pipelines/<PID>"
```
But : obtenir `success | failed | running | canceled`. Ne jamais déclarer une pipeline verte sans avoir lu ce statut (superpowers:verification-before-completion — preuve, jamais affirmation).

## 2 — Pipeline rouge → diagnostiquer et fixer

1. Lire les logs du job en échec : `glab ci trace <job>` / `glab api ".../jobs/<job_id>/trace"`.
2. **Pipeline parent-child (monorepo Malt)** — `glab ci status`/`glab ci get` ne montrent QUE les jobs du parent. Le job réellement en échec est souvent dans la **child pipeline** (job-factory) :
   ```
   glab api "projects/:id/pipelines/<PARENT_ID>/bridges"        # → downstream_pipeline.id
   glab api "projects/:id/pipelines/<CHILD_ID>/jobs?per_page=100"   # → job status=failed
   ```
3. **Job Sonar en échec (`erp-sonar`, `*-sonar`)** — le log CI ne donne que `QUALITY GATE STATUS: FAILED` + un lien dashboard, jamais les conditions précises. **Ne jamais deviner** : invoquer la commande `/sonar`, qui interroge l'API SonarQube pour les conditions du gate en échec + les issues exactes (règle, fichier:ligne, message). **Exception « Sonar illisible »** : API injoignable / token invalide et log illisible → demander les erreurs Sonar à l'utilisateur, puis fixer.
4. **Rebase impossible signalé par GitLab (conflits)** — résoudre les conflits sur la branche de la MR (jamais sur master, cf. GIT WORKFLOW), puis repush.
5. Fixer la cause exacte identifiée (jamais un correctif au hasard), **commit + repush sur la branche de la MR** (jamais master), la pipeline se relance automatiquement.
6. Reboucler sur § 1 jusqu'au statut `success`.

## 3 — Attente — jamais bloquer l'utilisateur

**`Monitor` INTERDIT** pour surveiller une pipeline : chaque événement déclenche une demande d'accord qui bloque l'utilisateur. Utiliser un `Bash` en **`run_in_background: true`** avec une boucle `until` qui sort au statut terminal (une seule notification à la fin) :

```bash
until s=$(glab api "projects/:id/pipelines/<PID>" | python3 -c "import sys,json;print(json.load(sys.stdin)['status'])") \
  && [ "$s" = success -o "$s" = failed -o "$s" = canceled ]; do sleep 30; done; echo "DONE=$s"
```

Intervalle calé sur la vitesse réelle de la pipeline surveillée (~8 min → check ~480s, pas 8 checks de 60s). Alternative auto-cadencée : `/loop` (skill commons § VÉRIFICATION & BOUCLES levier 4) — mécanisme équivalent, pas un remplacement de fond.

**PIÈGE VÉCU — `nohup ... & disown` = boucle invisible, INTERDIT.** La boucle `until` DOIT être passée directement dans le paramètre `run_in_background: true` de l'outil `Bash` — jamais lancée en arrière-plan « à la main » via `nohup ... & disown` (ou équivalent) à l'intérieur d'un appel `Bash` classique. Un process détaché de cette façon tourne bien, mais **sort du tracking du harness** : aucune notification `<task-notification>` n'arrivera jamais à la fin, et la session reste sourde jusqu'à ce que l'utilisateur relance manuellement. Seul `run_in_background: true` sur l'appel `Bash` lui-même déclenche la notification automatique de fin — c'est le seul mécanisme qui dispense de repasser par l'utilisateur. Repérer l'erreur a posteriori : si on a dû relire un fichier de statut à la main plutôt que recevoir une notification, la boucle était mal lancée.

**Même mécanisme pour attendre le commentaire `Approved`** (pas seulement la pipeline) : une fois la pipeline verte, si `Approved` n'est pas encore là, relancer une boucle `until` (même paramètre `run_in_background: true`) qui poll `glab api "projects/:id/merge_requests/<IID>/notes"` jusqu'à trouver un commentaire de `stephen.begot` dont le corps vaut exactement `Approved` et dont `created_at` est postérieur au dernier repush — puis sortir. Ne jamais se contenter d'annoncer « j'attends ton retour » et rester passif sans boucle trackée : c'est la même faute que ne pas boucler sur la pipeline.

**HEURES CALMES 20h–7h (CLAUDE.md) — RÈGLE ABSOLUE.** Avant de lancer/relancer une boucle `until` ou un `/loop`/`ScheduleWakeup` de suivi pipeline : `date +%H%M`. Si ∈ [2000,2359]∪[0000,0659] → **STOPPER NET**, ne rien programmer, consigner l'état (branche, MR+numéro, statut pipeline, où reprendre) en onglet `[WAIT]` (« paused — quiet hours »), relance **manuelle** le matin. Raison : boucles nocturnes ayant brûlé ~2M tokens à attendre une pipeline/`Approved` qui n'arrivent pas la nuit.

**ANTI-VEILLE** : avant de lancer la boucle background, vérifier qu'un `caffeinate` ne tourne pas déjà (`pgrep -fl caffeinate`), sinon `nohup caffeinate -di >/dev/null 2>&1 &`.

## 4 — Clôture

Ne considérer le suivi pipeline comme terminé qu'au statut `success` **cité** (pas supposé), ou après avoir explicitement demandé les erreurs Sonar à l'utilisateur (exception § 2.3). Revenir à l'onglet `[MR (<numMR>)]` (en attente d'approval) une fois la pipeline verte — cf. `malt-workflow-commons § PRÉFIXES DE HEADER CMUX`.
