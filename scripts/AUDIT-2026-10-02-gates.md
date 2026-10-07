# Audit des gates et des enregistreurs d'état — 2026-10-02

**Conclusion.** Sur 21 gates, 4 sont structurellement insatisfiables et 5 enregistreurs d'état sur 10 concluent sur la requête au lieu du résultat. La cause commune est mesurée : dans ce harnais l'outil `Agent` est toujours asynchrone, et la réponse immédiate que le hook `PostToolUse` lit **rejoue le prompt envoyé au sous-agent**.

## Le fait de base, mesuré

Sonde posée le 2026-10-02 (`claude -p --settings` avec un hook de dump sur `PostToolUse` et sur `SubagentStop`, deux sous-agents lancés en parallèle).

`PostToolUse(Agent)` tire **au lancement**. Son `tool_response` vaut :

```json
{"isAsync": true, "status": "async_launched", "agentId": "a5fe18a897e40b0d1",
 "prompt": "<le prompt envoyé au sous-agent, verbatim>",
 "outputFile": "...", "resolvedModel": "claude-haiku-4-5"}
```

`wf-record.sh:45` aplatit cet objet entier en JSON puis le grep. Le champ `prompt` est donc dans le texte grepé. C'est le mécanisme exact du faux positif `BOOTED_OK` : ce n'est pas le fallback de la ligne 46, qui est inopérant.

`SubagentStop` tire **à la fin**, et porte ce qu'il faut :

```json
{"agent_id": "a5fe18a897e40b0d1", "agent_type": "general-purpose",
 "last_assistant_message": "<sortie finale réelle, 3392 caractères non tronqués>",
 "agent_transcript_path": "..."}
```

`agent_id` est identique à `tool_response.agentId`, y compris avec deux sous-agents lancés en parallèle. `last_assistant_message` n'est pas tronqué à 3392 caractères.

## Gates

Levable veut dire : il existe une action que le workflow prescrit et que le harnais permet, qui le lève réellement. Dupable veut dire : le texte d'une requête suffit à le lever.

| Gate | Levable | Dupable | Verdict |
|---|---|---|---|
| master-write | oui | non | sain |
| master-push | oui | non | sain |
| worktree-form | oui | non | sain |
| coauthor | oui | non | sain |
| coverage | oui par un test indexé | non | message fautif, il prescrit d'éditer `wf-gates.conf`, action refusée par le classifier en auto mode |
| pre-push (tests verts) | fragile | non | `wf-bash-hook.sh:35` garde les 4000 **premiers** caractères de la sortie, `BUILD SUCCESSFUL` est en queue, donc une suite longue ne lève jamais le gate |
| pre-push (smoke-run) | oui | **oui** | fait 2 mesuré. En plus le relevé direct rate les apps Kotlin, le motif exige `Application in` et Spring écrit `ApplicationKt in` |
| pre-mr (juge) | **non** | oui | fait 1 mesuré, et le message de refus prescrit `run_in_background=false`, paramètre absent de l'outil `Agent` |
| mr-create | oui | non | sain |
| rebase-skipci | oui | non | sain, il contrôle la forme de la requête et c'est son rôle |
| mr-merge | **non** | via `rebased_skipci` | impasse vue trois fois (BILL-3534, BILL-3587, et la mémoire associée). Le rebase prescrit périme l'`Approved` et rend la pipeline de tête `skipped` |
| end-gate | oui | non | dépend de `merged`, posé sur un merge en échec |
| closing-block | oui | non | dépend de `pushed_turn`, posé sur un push en échec |
| jira-status | oui | non | sain |
| livrable | oui | non | sain |
| tmp-ban | **non** sur la forme prescrite | non | il refuse `~/tmp/scratch/`, le chemin que son propre message désigne |
| quiet-hours | oui | non | sain, mais CLAUDE.md décrit le juge comme un appel synchrone, ce qui est faux |
| external-lang | oui | non | faux positif connu, il scanne toute la commande. Sortie réelle : séparer les commandes. Laissé en l'état |
| skill-required | oui | non | sain dans la session principale, insatisfiable dans un sous-agent privé de l'outil `Skill`. Aucun sous-agent n'édite aujourd'hui |
| prose-required | oui | non | sain, mode warn |
| preanalysis | oui | non | sain, mode warn |

## Enregistreurs d'état

| Clé | Ce qui est lu | Dupable | Verdict |
|---|---|---|---|
| `skills`, `preanalysis` | `tool_input.skill` du tool `Skill` | non | sain, l'invocation est l'acte |
| `tests_green` | commande **et** sortie | non | principe sain, troncature en tête à corriger |
| `smoke_ok` (sous-agent) | `tool_response` qui rejoue le prompt | **oui** | à refaire sur `SubagentStop` |
| `smoke_ok` (bash direct) | sortie de la commande | non | motif aveugle à `ApplicationKt` |
| `judge_ran_*`, `judge_ok_*` | `tool_response` qui rejoue le prompt | **oui**, et faux négatif | à refaire sur `SubagentStop` |
| `rebased_skipci` | la commande seule | **oui** | posé même si le rebase échoue |
| `mr` | commande + sortie | partiellement | l'IID doit venir de la sortie seule, sinon un mauvais IID oriente le gate `mr-merge` vers la mauvaise MR |
| `merged` | la commande seule | **oui** | un merge en échec bloque la fin de tour sur un `/end` impossible |
| `pushed_turn` | la commande seule | **oui** | un push rejeté exige un bloc de clôture |
| `end_done`, `livrable_done` | log du jour, transcript | non | sain |

## Ce que je corrige

Les lignes marquées en gras ci-dessus, plus les trois messages de refus qui décrivent une sortie impraticable (`pre-mr`, `coverage`, et le skill `malt-judge-loop`).

Deux directions étaient ouvertes pour le signal des sous-agents. Je prends **`SubagentStop`**, parce que la sonde montre qu'il reçoit la sortie finale réelle et l'`agent_id` du lancement. La preuve par artefact reste implémentée en **second chemin indépendant** dans le gate `pre-mr` et dans le gate `pre-push`, pour le cas où `SubagentStop` ne tire pas (sous-agent tué, session dont le snapshot de hooks ne porte pas l'événement).

## Ce que je ne corrige pas

`external-lang` reste en l'état. Il est levable, sa sortie est d'écrire en anglais ou de séparer la commande, et le resserrer demanderait un analyseur de commande que rien d'autre ne justifie.

`skill-required` reste en `block`. Le cas insatisfiable n'existe que pour un sous-agent qui éditerait du code, ce qu'aucun agent défini ne fait.

## Trouvé en route, corrigé aussi

`ticket` était lu par le gate `jira-status` et écrit par personne. Ce gate ne s'est donc jamais
déclenché. `wf-prompt-hook.sh` pose maintenant la clé quand il détecte le ticket en entrée.

Les drapeaux de preuve survivaient d'un ticket au suivant sur la même surface. Un `judge_ran_pre_mr`
acquis sur le ticket précédent ouvrait la MR du suivant sans aucun juge. Ils sont remis à zéro sur
`git worktree add`, qui marque le début d'un nouveau ticket.

## Vérification

`tests/gates_test.sh` : 92 ok, 0 FAIL. `tests/hooks_test.sh` : 18 ok, 0 FAIL.

Les quatre cas exigés ont été rejoués contre le code d'avant, dans un `HOME` isolé portant les scripts
d'origine. Deux échouaient : le verdict produit après le lancement ne débloquait pas la MR, et le
`BOOTED_OK` cité dans un prompt posait `smoke_ok`. Les deux autres passaient déjà, mais pour une
mauvaise raison : le gate `pre-mr` refusait tout.

Vérifié aussi en session réelle, hooks installés : un sous-agent `smoke-runner` dont le prompt nomme
`BOOTED_OK` et dont la conclusion est `BOOT_FAILED` laisse `smoke_ok` absent de l'état de surface.
