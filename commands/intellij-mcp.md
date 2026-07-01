---
description: Use IntelliJ MCP to write code and confirm it builds/passes inspections. Use when editing Kotlin/Java/frontend files and need real IDE feedback (build errors, lint, type errors) instead of guessing.
---

# IntelliJ MCP — Code + Confirm Workflow

Use the `mcp__idea__*` tools to get real IDE feedback after every code change.
Project path: always pass `projectPath` from context (e.g. `/Users/stephenbegot/Documents/projects/malt`).

## Arguments

$ARGUMENTS

If no arguments: infer from context (current file, recent edits, user description).

---

## Workflow

### 1. Locate before editing

Prefer IDE tools over Bash for search — faster, index-backed.

```
mcp__idea__search_symbol(q, projectPath)           # find class/method/field
mcp__idea__search_in_files_by_text(searchText)     # find literal text
mcp__idea__search_in_files_by_regex(regexPattern)  # pattern search
mcp__idea__get_file_text_by_path(pathInProject)    # read file
mcp__idea__get_symbol_info(filePath, line, column) # type/doc at position
```

### 2. Edit

Use the standard `Edit` / `Write` tools (or `mcp__idea__replace_text_in_file` for simple replacements).

After editing, reformat if needed:
```
mcp__idea__reformat_file(path, projectPath)
```

### 3. Build — always run after edits

```
mcp__idea__build_project(projectPath)
# or for targeted rebuild:
mcp__idea__build_project(projectPath, filesToRebuild: ["relative/path/to/File.kt"])
```

**Interpret results:**
- No errors → proceed
- Errors → fix, loop back to step 2

### 4. Inspections / lint

```
mcp__idea__get_file_problems(filePath, projectPath, errorsOnly: false)
```

Fix every `ERROR` severity item before declaring done.
`WARNING` items: fix if related to your change; skip unrelated pre-existing ones.

### 5. Run tests (if applicable)

```
mcp__idea__get_run_configurations(projectPath)          # list existing configs
mcp__idea__get_run_configurations(filePath, projectPath) # find runnable points in file
mcp__idea__execute_run_configuration(configurationName, projectPath, timeout: 120000)
# or from file+line:
mcp__idea__execute_run_configuration(filePath, line, projectPath, waitForExit: true, timeout: 120000)
```

Check `exitCode` in result. Non-zero = failure, read output for details.

### 6. Validate done

Only mark task complete when ALL of:
- [ ] `build_project` returns no errors
- [ ] `get_file_problems` returns no ERROR items on edited files
- [ ] Relevant test config exits 0 (if tests exist for the change)

---

## Quick reference — tool map

| Need | Tool |
|---|---|
| Find class/method | `search_symbol` |
| Find text | `search_in_files_by_text` |
| Read file | `get_file_text_by_path` |
| What is this symbol? | `get_symbol_info` |
| Build | `build_project` |
| Lint/inspections | `get_file_problems` |
| Run test/config | `execute_run_configuration` |
| Format file | `reformat_file` |
| List run configs | `get_run_configurations` |
| Create file | `create_new_file` |
| Rename symbol (refactor) | `rename_refactoring` |

---

## Rules

- **Always build after edits** — never assume compilation succeeded.
- **Never declare success with build errors** — fix them first.
- `filePath` in MCP tools is **relative to project root**, not absolute.
- For large monorepos, target `filesToRebuild` to avoid full rebuild when possible.
- If build times out (>5 min), switch to `get_file_problems` for fast feedback.
