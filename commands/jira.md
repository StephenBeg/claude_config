Interact with Jira via the **Atlassian REST API v3** (curl + Basic auth). Fallback used while the Atlassian MCP is broken (Confluence-scope issue).

`$ARGUMENTS` = free-form request (e.g. `read SM-1507`, `comment SM-1507 "..."`, `transition SM-1507 to In Progress`, `create bug in SM project ...`). Interpret the intent, run the matching recipe below, report the result. Reply in French (caveman) unless asked otherwise. All text WRITTEN to Jira (summaries, descriptions, comments) MUST be in **English**.

## Auth (already in ~/.zshrc)

```sh
# ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN, ATLASSIAN_SITE (https://malt-community.atlassian.net)
AUTH=(-u "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" -H "Accept: application/json")
JSON=(-H "Content-Type: application/json")
API="$ATLASSIAN_SITE/rest/api/3"
```

Always `source ~/.zshrc` (or rely on the shell env) first. Sanity check: `curl -s "${AUTH[@]}" "$API/myself"` → 200.

## Key facts (verified live 2026-07-20)

- Old `GET/POST /rest/api/3/search` → **410 Gone**. Use **`/rest/api/3/search/jql`**.
- `/search/jql` **requires a bounded JQL** ("Unbounded JQL queries are not allowed"). Add a restriction (project, assignee, created >= -30d, etc.).
- `/search/jql` returns `{issues, isLast, nextPageToken}` — **no `total`**. Paginate with `nextPageToken`.
- Rich text fields (`description`, comment `body`) use **ADF** (Atlassian Document Format), not plain string. Minimal ADF for a paragraph is below.

## ADF helper (for description / comments)

```sh
adf() {  # $1 = plain text -> ADF JSON doc
  python3 -c 'import json,sys;print(json.dumps({"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"text","text":sys.argv[1]}]}]}))' "$1"
}
```

## Recipes

### Read an issue
```sh
curl -s "${AUTH[@]}" "$API/issue/SM-1507?fields=*all" \
| python3 -c 'import sys,json;d=json.load(sys.stdin);f=d["fields"];print(d["key"],"|",f["summary"]);print("status:",f["status"]["name"]);print("assignee:",(f.get("assignee") or {}).get("displayName"))'
```
Comments: `curl -s "${AUTH[@]}" "$API/issue/SM-1507/comment?maxResults=100"`

### Search (JQL)
```sh
curl -s "${AUTH[@]}" --get "$API/search/jql" \
  --data-urlencode 'jql=project = SM AND statusCategory != Done ORDER BY updated DESC' \
  --data-urlencode 'maxResults=50' \
  --data-urlencode 'fields=key,summary,status,assignee'
```
Next page: add `--data-urlencode "nextPageToken=<token>"` while `isLast=false`.

### Create an issue
```sh
DESC=$(adf "Created via REST API.")
curl -s "${AUTH[@]}" "${JSON[@]}" -X POST "$API/issue" -d "{
  \"fields\": {
    \"project\": { \"key\": \"SM\" },
    \"issuetype\": { \"name\": \"Task\" },
    \"summary\": \"My summary in English\",
    \"description\": $DESC
  }
}"
```
Discover valid project keys / issue types / required fields first:
`curl -s "${AUTH[@]}" "$API/issue/createmeta?projectKeys=SM&expand=projects.issuetypes.fields"`

### Edit fields
```sh
curl -s "${AUTH[@]}" "${JSON[@]}" -X PUT "$API/issue/SM-1507" -d "{
  \"fields\": { \"summary\": \"Updated summary\", \"description\": $(adf \"New description.\") }
}"   # 204 No Content on success
```

### Change status (transition)
Transitions are per-workflow; look up the id first, then apply.
```sh
curl -s "${AUTH[@]}" "$API/issue/SM-1507/transitions"   # -> list of {id, name}
curl -s "${AUTH[@]}" "${JSON[@]}" -X POST "$API/issue/SM-1507/transitions" \
  -d '{ "transition": { "id": "31" } }'   # 204 on success
```
To resolve a name → id automatically:
```sh
TID=$(curl -s "${AUTH[@]}" "$API/issue/SM-1507/transitions" \
  | python3 -c 'import sys,json;n=sys.argv[1].lower();[print(t["id"]) for t in json.load(sys.stdin)["transitions"] if t["name"].lower()==n]' "In Progress")
```

### Add a comment
```sh
curl -s "${AUTH[@]}" "${JSON[@]}" -X POST "$API/issue/SM-1507/comment" \
  -d "{ \"body\": $(adf \"Comment text in English.\") }"
```

### Assign
```sh
# accountId via /rest/api/3/user/search?query=<email>
curl -s "${AUTH[@]}" "${JSON[@]}" -X PUT "$API/issue/SM-1507/assignee" \
  -d '{ "accountId": "712020:...." }'
```

## Notes
- Success codes: create → 201 (returns key), edit/transition/assign → 204 (empty body).
- On 4xx read the `errorMessages` / `errors` in the JSON body before retrying.
- Reference: https://developer.atlassian.com/cloud/jira/platform/rest/v3/
