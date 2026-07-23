---
name: end
description: >
  Use at the end of a work session to append a short summary of what was accomplished
  to a daily log file at /Users/stephenbegot/tmp/YYYY-MM-DD.md.
  ALWAYS includes the MR link, and the Jira link when a ticket is known.
  Use when: wrapping up a session, end of day recap, /end.
---

Appends a short summary of the current session to the daily log file.

## File Location

`/Users/stephenbegot/tmp/YYYY-MM-DD.md` — one file per calendar day.

## Steps

1. **Determine the target date/file** (see "Target file selection" below) — normally today, but the day rolls over once `/daily` has consumed today's log.
2. **Read the target file** if it already exists (to append, never overwrite).
3. **Resolve the links** (do this before writing — see "Resolving links" below):
   - **MR link** — ALWAYS include one for the branch worked on this session.
   - **Jira link** — include it whenever a ticket ID is known.
   - **Umbrella ticket** — resolve the parent umbrella of the sub-task (its JIRA `parent`: the User Story or EPIC the sub-task lives under) and include it in the block, so the log says which umbrella this sub-task belongs to. See "Resolving links".
4. **Synthesize a session summary** from the conversation context:
   - **One business sentence (mandatory)** — a single sentence, written in plain business language readable by a product person (not caveman, no jargon, no ticket codes). It states the value/outcome of the session, not the technical steps. This is the `_..._` title line of the block.
   - Then 1 to 3 short bullet points describing what was done (technical, action-focused, verb first).
5. **Append** the following block at the end of the file (create the file if it doesn't exist):

```
-------session------
**HH:MM** — _one business sentence readable by a product person_
- bullet 1
- bullet 2
- Umbrella: [PARENT-ID](https://malt-community.atlassian.net/browse/PARENT-ID) _(parent umbrella name)_
- Jira: [TICKET-ID](https://malt-community.atlassian.net/browse/TICKET-ID) — MR: [!XXXX](url) (or [create MR](url) if not opened yet)
-------end------
```

The `Umbrella:` bullet is what lets `/daily` group sessions by umbrella (one standup line per umbrella). Omit it only when the ticket has no parent (standalone ticket) or genuinely no ticket applies.

6. **Tradeoffs → commentaire Jira (OBLIGATOIRE quand un ticket est connu).** Poster les arbitrages pris **sans validation explicite de l'utilisateur** (choix de design/scope/implémentation décidés seul, contournements, éléments laissés à un ticket de suivi) en **commentaire sur le ticket Jira concerné**, pour que le relecteur puisse les contester.
   - Utiliser `mcp__atlassian__addCommentToJiraIssue` (cloudId `aca47d88-0bd1-419a-bb78-2e7aeb2ce594` pour malt-community ; sinon résoudre via `getAccessibleAtlassianResources`).
   - **RÉDIGÉ EN ANGLAIS** (règle absolue d'écriture Jira/GitLab/Notion), même si la conversation est en français.
   - Format : titre `Tradeoffs (BILL-XXXX)` puis une puce par arbitrage, avec la raison. Si **aucun** arbitrage non validé → poster `Tradeoffs: none — all decisions validated upfront.` (ou omettre uniquement s'il n'y a genuinement aucun ticket).
   - Ne PAS dupliquer dans le log quotidien ; le log reste le récit court, le commentaire Jira porte les tradeoffs.

7. **Capture de connaissance durable (Obsidian) — conditionnel.** Après avoir écrit le log, évaluer si l'implémentation a produit du savoir **réutilisable pour de futures implémentations** : specs ajoutées, décision d'architecture, convention, pattern, contrainte technique non évidente, piège rencontré.
   - Si oui → invoquer le skill `/obsidian` (mode capture) pour consigner ces éléments dans le vault (note durable dédiée ou append à la note existante la plus pertinente ; respecter frontmatter `summary`/`up`, backlink parent, MAJ `_INDEX.md`).
   - **Ne rien écrire** si rien n'est réutilisable, ou si c'était une petite tâche sans intérêt (fix trivial, config, renommage). En cas de doute que ce soit vraiment utile → ne pas polluer le vault.
   - Ne capturer que le savoir **généralisable**, pas le récit de la session (ça, c'est le rôle du log quotidien ci-dessus).

## Target file selection (day rollover)

`/daily` marks a log as "consumed" by appending a `-------daily-reported------` flag at the end of the file (after the last session it reported). This means the day's standup has already been given, so any session finished afterwards belongs to the **next** day's standup.

Rule for `/end`:
1. Compute today's date `T` and its file `/Users/stephenbegot/tmp/T.md`.
2. If that file exists **and** contains the `-------daily-reported------` flag → the target becomes **tomorrow's** file `/Users/stephenbegot/tmp/T+1.md` (next calendar day). Append there instead.
3. Otherwise → target is today's file.
4. Never remove or move the `-------daily-reported------` flag; it stays where `/daily` left it.

## Resolving links

**MR link (mandatory):**
- Determine the current branch and repo (e.g. `git -C <worktree> rev-parse --abbrev-ref HEAD`; repo is `maltcommunity/malt/apps/malt` unless obviously another).
- If an MR already exists for the branch, use its real web URL:
  `glab mr view <branch> -R maltcommunity/malt/apps/malt` → use the `web_url` (rendered as `[!<iid>](web_url)`).
- If no MR exists yet (Malt workflow: the human opens the MR), use the "create MR" URL — it's printed by `git push` output, or build it:
  `https://gitlab.com/maltcommunity/malt/apps/malt/-/merge_requests/new?merge_request%5Bsource_branch%5D=<branch>` (rendered as `[create MR](url)`).
- The branch/MR URL is almost always already in the session context (from a recent push or MR command) — reuse it instead of re-querying when it's there.

**Jira link (when known):**
- Infer the ticket ID from the branch name (`TICKET-123-...`), commit messages, or the conversation.
- Build: `https://malt-community.atlassian.net/browse/<TICKET-ID>`.
- If genuinely no ticket applies to the session, omit the Jira part (but still include the MR link).

**Umbrella ticket (parent):**
- Resolve the sub-task's parent umbrella (the User Story or EPIC it lives under):
  `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/issue/<TICKET-ID>?fields=parent"` → `fields.parent.key` and `fields.parent.fields.summary`.
- Build the link `https://malt-community.atlassian.net/browse/<PARENT-ID>` and include the parent summary as the italic name.
- If the ticket has no parent (standalone) → omit the `Umbrella:` bullet.

## Rules

- **NEVER** modify anything above the last `-------end------` separator.
- Only append. The file is a running log — past entries are read-only.
- The separator `-------session------` / `-------end------` is hardcoded — do not vary it.
- **ALWAYS** include the MR link (real MR if open, otherwise the create-MR URL). Never omit it.
- Include the Jira link whenever a ticket ID can be determined; omit only when there is genuinely no ticket.
- Put the `Jira: … — MR: …` links on their own final bullet of the block.
- Time (HH:MM) is the current local time at the moment of invocation.
- Keep bullets short — max 10 words each. This is a log, not a report.
- Create the `/Users/stephenbegot/tmp/` directory if it doesn't exist.

## Example Output (appended block)

```
-------session------
**14:32** — _Prepared secure automated login between our accounting system and NetSuite_
- Explored TBA auth flow in NetSuite connector
- Drafted REST token generation prototype
- Umbrella: [BILL-2400](https://malt-community.atlassian.net/browse/BILL-2400) _(NetSuite REST migration)_
- Jira: [BILL-2443](https://malt-community.atlassian.net/browse/BILL-2443) — MR: [!9871](https://gitlab.com/maltcommunity/malt/apps/malt/-/merge_requests/9871)
-------end------
```
