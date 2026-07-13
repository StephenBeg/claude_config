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

1. **Get today's date** (YYYY-MM-DD format) — use it as the filename.
2. **Read the file** if it already exists (to append, never overwrite).
3. **Resolve the links** (do this before writing — see "Resolving links" below):
   - **MR link** — ALWAYS include one for the branch worked on this session.
   - **Jira link** — include it whenever a ticket ID is known.
4. **Synthesize a session summary** from the conversation context:
   - 1 to 3 short bullet points describing what was done.
   - Each bullet: one line, action-focused (verb first).
5. **Append** the following block at the end of the file (create the file if it doesn't exist):

```
-------session------
**HH:MM** — _short title of the session (e.g. ticket number + topic)_
- bullet 1
- bullet 2
- Jira: [TICKET-ID](https://malt-community.atlassian.net/browse/TICKET-ID) — MR: [!XXXX](url) (or [create MR](url) if not opened yet)
-------end------
```

6. **Capture de connaissance durable (Obsidian) — conditionnel.** Après avoir écrit le log, évaluer si l'implémentation a produit du savoir **réutilisable pour de futures implémentations** : specs ajoutées, décision d'architecture, convention, pattern, contrainte technique non évidente, piège rencontré.
   - Si oui → invoquer le skill `/obsidian` (mode capture) pour consigner ces éléments dans le vault (note durable dédiée ou append à la note existante la plus pertinente ; respecter frontmatter `summary`/`up`, backlink parent, MAJ `_INDEX.md`).
   - **Ne rien écrire** si rien n'est réutilisable, ou si c'était une petite tâche sans intérêt (fix trivial, config, renommage). En cas de doute que ce soit vraiment utile → ne pas polluer le vault.
   - Ne capturer que le savoir **généralisable**, pas le récit de la session (ça, c'est le rôle du log quotidien ci-dessus).

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
**14:32** — _BILL-2443 NetSuite auth spike_
- Explored TBA auth flow in NetSuite connector
- Drafted REST token generation prototype
- Jira: [BILL-2443](https://malt-community.atlassian.net/browse/BILL-2443) — MR: [!9871](https://gitlab.com/maltcommunity/malt/apps/malt/-/merge_requests/9871)
-------end------
```
