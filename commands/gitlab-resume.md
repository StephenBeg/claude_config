---
description: Génère un résumé de MR GitLab structuré (Jira, App, Feature Flag, Comment) à partir du contexte courant.
---

Generate a GitLab MR description in English from the current context.

## Input

$ARGUMENTS

## Workflow

### 1. Gather information

Extract from context (git branch, recent commits, open files, conversation history):

- **Jira ticket** — ticket ID (e.g. BILL-2519). Infer from branch name (`feature/bill-XXXX-...`) or commit messages.
- **App to launch** — which app/service needs to be started to test the changes (e.g. `netsuite-connector`, `billing-backend`, `payment-frontend`). Infer from modified files and module paths.
- **Feature flag** — any feature flag gating the changes. Look for `@FeatureToggle`, `featureFlags`, environment variables, or flag names in the diff/code. If none, use `None`.
- **Comment** — a short English sentence summarizing what the MR does and why.

If any information cannot be inferred from context, **ask the user explicitly before generating output**. Ask all missing fields in a single message, not one by one.

### 2. Generate the summary

Output the result as **Markdown inside a ` ```markdown ` fenced code block** so it can be copy-pasted into the GitLab MR description with the metadata and formatting preserved.

**IMPORTANT — line breaks**: the metadata fields MUST each be their own `###` header (real newlines), so pasting into GitLab renders each on its own line. Do NOT use bold labels or collapse them onto a single line.

Use exactly this structure:

````markdown
```markdown
### Jira
<[TICKET-ID](https://malt-community.atlassian.net/browse/TICKET-ID) — ticket title, or None>

### App to launch
<app name(s)>

### Feature Flag
<flag name or None>

## Description

<2–4 sentences (or a short bullet list) covering: the context/problem being addressed, what the change actually does, and why — enough for a reviewer to understand the MR without reading the diff.>

<If relevant, add a `### Key changes` bullet list of the notable modifications (files/layers touched, new endpoints, migrations, etc.).>
```
````

### 3. Rules

- Always write in **English**.
- **Description must be substantive**, not a single terse sentence: give the reviewer the context (why this change exists), the what (what it does), and the impact. Still no filler — every sentence carries information.
- Use a `### Key changes` bullet list whenever the MR touches several files/layers or is non-trivial.
- Jira links MUST use the base `https://malt-community.atlassian.net/browse/<TICKET-ID>` (NOT `malt.atlassian.net`, which is broken). Same base for the umbrella/parent link.
- Do not invent ticket IDs or flag names — ask if unsure.
- If multiple Jira tickets are involved, list them comma-separated.
- If multiple apps need to be launched, list them comma-separated.
- Output ONLY the fenced markdown block (plus a one-line intro if needed) — no extra commentary around it.
