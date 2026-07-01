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

Output exactly this block in a code fence so it's easy to copy.

**IMPORTANT — line breaks**: each field MUST be on its own line, separated by a real newline (`\n`), so that copy-pasting into GitLab preserves the line breaks. Do NOT output all fields on a single line.

```
Jira: <TICKET-ID> — <ticket title or short description>
App to launch: <app name(s)>
Feature Flag: <flag name or None>
Comment: <one concise English sentence explaining what this MR does and why>
```

### 3. Rules

- Always write in **English**.
- Keep Comment to one sentence — what changed and the intent, no filler.
- Do not invent ticket IDs or flag names — ask if unsure.
- If multiple Jira tickets are involved, list them comma-separated.
- If multiple apps need to be launched, list them comma-separated.
