---
name: daily
description: >
  Use to generate a Slack standup message from today's session log.
  Reads /Users/stephenbegot/tmp/YYYY-MM-DD.md (created by /end) and formats
  a Slack-ready standup with task-done, fire, and dart sections.
  If the user provides a Slack message/thread, reply in that thread with ONLY
  the "done" part.
  Use when: writing standup, daily update, /daily.
---

Generates a Slack standup message from today's `/end` log.

## Two modes

- **Copy-paste mode (default)** — no Slack message provided → produce the full standup (task-done + fire + focus) in a fenced code block for the user to paste. Follow the steps below.
- **Thread-reply mode** — the user provides a Slack message or thread (URL, permalink, or a reference like "reply in this thread") → **post a threaded reply containing ONLY the `:task-done:` part** (no `:fire:`, no `:dart:`). See **THREAD-REPLY MODE** below.

## Steps

1. **Get today's date** (YYYY-MM-DD) and read `/Users/stephenbegot/tmp/YYYY-MM-DD.md`.
2. If the file doesn't exist or has no entries → tell the user and stop.
3. **Parse all session blocks** (between `-------session------` and `-------end------`) that appear **before** any existing `-------daily-reported------` flag. If a flag is already present, only report sessions added after it.
4. **Group the sessions by umbrella ticket**, then produce **one business sentence per umbrella** (NOT per session/sub-ticket — otherwise the standup floods):
   - Read each block's `Umbrella:` bullet. All sessions sharing the same umbrella collapse into **a single standup line** summarizing the umbrella-level progress of the day (synthesize across those sessions' outcomes).
   - Sessions with **no umbrella** (standalone ticket, or none) each get their own line.
   - Each line is **one business sentence** readable by a product person (plain language, no jargon, no ticket codes). Reuse the blocks' `_..._` business titles when they fit.
   - **Append one link per line** to the umbrella ticket (see "Umbrella / epic link per line" below).
   - **Never include the sub-task Jira link nor the MR link** in the standup — only the umbrella (or epic) link.
5. **Output the Slack message** using the template below.
6. **Mark the log as reported:** append `-------daily-reported------` at the very end of the log file. This tells `/end` that today's standup was given, so later sessions roll over to the next day's file. If the flag is already present, append a fresh one after the last reported session.

## Umbrella / epic link per line

Each standup line ends with **one** Slack link, resolved as follows:

1. Read the umbrella from the block's `Umbrella:` bullet — it already carries the key, URL and name: `[BILL-2900](url) _(Canary parity registry)_`.
2. **Is the umbrella explicit enough?** The umbrella is explicit when its name clearly reflects the business value stated in the standup sentence (a product person would recognize what it is). Then link to it: `<https://malt-community.atlassian.net/browse/BILL-2900|BILL-2900>`.
3. **If the umbrella is NOT explicit enough** (vague/technical name, internal grouping, or generic like "misc", "chore", "tech"), resolve its **epic** and link to that instead:
   - `curl -s -u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" "$ATLASSIAN_SITE/rest/api/3/issue/<UMBRELLA-ID>?fields=parent"` → `fields.parent.key`.
   - Link: `<https://malt-community.atlassian.net/browse/<EPIC-ID>|<EPIC-ID>>`.
   - If no epic exists, fall back to the umbrella link.
4. Sessions with no umbrella get no link (or their own standalone ticket link if that is the only anchor).

Slack link format is `<url|label>` — never bare Markdown `[label](url)` (it does not render in Slack).

## Slack Message Template

```
:task-done: *What I worked on*
• [one business sentence per umbrella] <url|TICKET-ID>

:fire: *Blockers*
• Nothing

:dart: *Focus*
• [infer from last session entry or ask user if unclear]
```

## Rules

- **One bullet per umbrella ticket** — group all sessions sharing an umbrella into a single line; sessions without an umbrella get their own line. Never one bullet per sub-ticket (it floods the standup).
- Compress each umbrella (or standalone session) to a single business sentence readable by a product person: plain language, the value/outcome, no technical jargon.
- **One link per line — umbrella or epic.** Append `<url|TICKET-ID>` pointing to the umbrella ticket, or to its epic when the umbrella name is not explicit enough (see "Umbrella / epic link per line"). Never include the sub-task Jira link nor the MR link.
- `:fire:` section: default to `Nothing` unless a blocker is visible in the log or session context.
- `:dart:` section: infer from the most recent session's topic; if ambiguous, ask the user.
- **ALWAYS wrap the final output in a fenced code block** so the raw Markdown is shown verbatim and survives copy-paste.
- After producing the standup, append the `-------daily-reported------` flag to the log file (see step 6).
- Language: **ALWAYS in English** — regardless of the language used in the session log or the conversation.

## THREAD-REPLY MODE — post only the "done" part in a provided Slack thread

Triggered when the user provides a Slack message/thread (permalink, `https://<workspace>.slack.com/archives/<channel>/p<ts>`, or an explicit "reply in this thread").

1. Build the standup content exactly as in the steps above (parse the log, one business sentence per umbrella, English, one umbrella/epic link per line).
2. **Keep ONLY the `:task-done:` section** — drop `:fire:` and `:dart:` entirely. The reply body is:
   ```
   :task-done: *What I worked on*
   • [one business sentence per umbrella] <url|TICKET-ID>
   ```
3. **Post it as a threaded reply** to the provided message via the `/slack` skill (claude.ai Slack MCP): resolve the channel + `thread_ts` from the permalink/URL, then send the message with that `thread_ts` so it lands in the thread (not as a new top-level message).
4. **Do NOT wrap in a code block** here — this text is posted to Slack, so `:task-done:` renders as the emoji and `*...*` as bold.
5. After posting, append the `-------daily-reported------` flag to the log file (same as step 6 of the default mode).
6. Confirm to the user with the thread link. Language: **English**.

## Example Output

```
:task-done: *What I worked on*
• Prepared secure automated login between our accounting system and NetSuite <https://malt-community.atlassian.net/browse/BILL-2900|BILL-2900>
• Improved the daily standup and end-of-session tooling <https://malt-community.atlassian.net/browse/BILL-2938|BILL-2938>

:fire: *Blockers*
• Nothing

:dart: *Focus*
• Finalize the NetSuite connection so invoices can sync automatically
```
