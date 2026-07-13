---
name: daily
description: >
  Use to generate a Slack standup message from today's session log.
  Reads /Users/stephenbegot/tmp/YYYY-MM-DD.md (created by /end) and formats
  a Slack-ready standup with task-done, fire, and dart sections.
  Use when: writing standup, daily update, /daily.
---

Generates a Slack standup message from today's `/end` log.

## Steps

1. **Get today's date** (YYYY-MM-DD) and read `/Users/stephenbegot/tmp/YYYY-MM-DD.md`.
2. If the file doesn't exist or has no entries → tell the user and stop.
3. **Parse all session blocks** (between `-------session------` and `-------end------`).
4. For each session block, extract one bullet summarizing the work done. If the block has a MR link, include it as a Markdown hyperlink: `[MR XXXX](url)`.
5. **Output the Slack message** using the template below.

## Slack Message Template

```
:task-done: *What I worked on*
• [one line per session, MR link inline if any]

:fire: *Blockers*
• Nothing

:dart: *Focus*
• [infer from last session entry or ask user if unclear]
```

## Rules

- One bullet per session block from the log — not per bullet inside the block.
- Compress each session to a single short sentence (max ~10 words).
- MR links: Markdown format `[MR 1234](https://gitlab.../merge_requests/1234)` — never Slack format `<url|text>`.
- `:fire:` section: default to `Rien` unless a blocker is visible in the log or session context.
- `:dart:` section: infer from the most recent session's topic; if ambiguous, ask the user.
- **ALWAYS wrap the final output in a fenced code block** so the raw Markdown (`[MR XXXX](url)`) is shown verbatim and survives copy-paste. Without the code fence the terminal renders the links and the copied text loses the URLs.
- MR link format is `[MR XXXX](url)` because Slack's **default WYSIWYG composer auto-converts** that on paste. It does NOT convert if the user enabled "Format messages with markup" (Preferences > Advanced) — in that mode links must be added via Cmd+Shift+U or by pasting a URL onto selected text. The Slack API/webhook format `<url|text>` NEVER works in the human composer, so never use it here.
- Language: **ALWAYS in English** — regardless of the language used in the session log or the conversation.

## Example Output

```
:task-done: *What I worked on*
• NetSuite TBA auth spike — REST token prototype [MR 9871](https://gitlab.malt.tech/malt/malt/-/merge_requests/9871)
• Created /end and /daily Claude Code skills

:fire: *Blockers*
• Nothing

:dart: *Focus*
• Finalize NetSuite TBA backend integration
```
