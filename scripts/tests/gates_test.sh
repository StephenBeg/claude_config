#!/usr/bin/env bash
# Test des gates déterministes : chaque cas vérifie le CODE DE SORTIE réel du
# hook (0 = laisse passer, 2 = bloque) sur un payload de hook fabriqué.
# Surface isolée (CMUX_SURFACE_ID) pour ne pas toucher l'état de travail réel.
set -uo pipefail
cd "$(dirname "$0")/.."
export CMUX_SURFACE_ID="gates-test"
unset WF_GATES_OFF
ST="python3 $PWD/wf-state.py"
MAIN_REPO="$HOME/Documents/projects/malt"
WT="$HOME/worktrees/malt"
pass=0; fail=0

pay() {  # pay <tool> <cwd> [k=v ...]
  python3 -c '
import json, sys
ti = {}
for kv in sys.argv[3:]:
    k, _, v = kv.partition("=")
    ti[k] = v
print(json.dumps({"tool_name": sys.argv[1], "cwd": sys.argv[2], "tool_input": ti}))' "$@"
}

t() {  # t <libellé> <exit attendu> <script> <payload>
  local label="$1" want="$2" script="$3" payload="$4" got out
  out=$(printf '%s' "$payload" | "./$script" 2>&1); got=$?
  if [[ "$got" == "$want" ]]; then
    pass=$((pass+1)); printf '  ok   %s\n' "$label"
  else
    fail=$((fail+1)); printf '  FAIL %s (attendu %s, obtenu %s)\n       %s\n' "$label" "$want" "$got" "${out:0:220}"
  fi
}

$ST reset
echo "== gate-bash-git : GIT WORKFLOW =="
t "sed -i dans le repo principal sur master"  2 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=sed -i '' s/a/b/ x.kt")"
t "git status dans le repo principal"         0 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=git status")"
t "redirection vers ~/tmp depuis le repo"     0 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=git diff > $HOME/tmp/scratch/d.txt")"
t "comparaison > 0.5 dans un python inline"   0 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=python3 -c print(1>0.5)")"
t "redirection vers un fichier du repo"       2 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=git diff > out.txt")"
t "push depuis master"                        2 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=git push origin master")"
t "worktree hors ~/worktrees/malt"            2 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=git worktree add /Users/x/wt -b t origin/master")"
t "worktree sans base origin/master"          2 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=git worktree add $WT/T-1 -b t-desc")"
t "worktree bien formé"                       0 gate-bash-git.sh "$(pay Bash "$MAIN_REPO" "command=git worktree add $WT/T-1 -b t-desc origin/master")"
t "push depuis un repo perso (hors portée Malt)" 0 gate-bash-git.sh "$(pay Bash "$HOME/Documents/perso/portfolio" "command=git push origin main")"
t "commit sans test hors portée Malt"          0 gate-bash-git.sh "$(pay Bash "$HOME/Documents/perso/portfolio" "command=git commit -m x")"
t "commit avec Co-Authored-By"                2 gate-bash-git.sh "$(pay Bash "$HOME" "command=git commit -F msg.txt Co-Authored-By: Claude")"
t "MR sans reviewer"                          2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab mr create --title X-1 Fix --label squad")"
t "MR titre hors format"                      2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab mr create --title \"Fix rounding\" --reviewer stephen.begot --label squad")"
t "MR sans label"                             2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab mr create --title \"[X-1] Fix rounding\" --reviewer stephen.begot")"
t "MR bien formée"                            0 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab mr create --title \"[X-1] Fix rounding\" --reviewer stephen.begot --label squad-acc")"
t "rebase sans skip_ci"                       2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab api --method PUT projects/x/merge_requests/12/rebase")"
t "rebase avec skip_ci"                       0 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab api --method PUT projects/x/merge_requests/12/rebase?skip_ci=true")"

echo "== gate-bash-git : pre-push =="
t "1er push sans juge"                        2 gate-bash-git.sh "$(pay Bash "$WT/T-1" "command=git push -u origin HEAD")"
$ST set judge_ok_pre_push=1
t "1er push sans tests verts"                 2 gate-bash-git.sh "$(pay Bash "$WT/T-1" "command=git push -u origin HEAD")"
$ST set tests_green=1
t "1er push avec juge + tests"                0 gate-bash-git.sh "$(pay Bash "$WT/T-1" "command=git push -u origin HEAD")"
$ST set mr=999
t "repush avec MR existante"                  0 gate-bash-git.sh "$(pay Bash "$WT/T-1" "command=git push --force-with-lease")"

echo "== gate-bash-git : merge (fail closed) =="
t "merge sans --squash"                       2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab mr merge 999 --remove-source-branch --yes")"
t "merge sans --remove-source-branch"         2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab mr merge 999 --squash --yes")"
t "merge sans rebase skip_ci préalable"       2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab mr merge 999 --squash --remove-source-branch --yes")"
$ST set rebased_skipci=1
t "merge API brute sans squash=true"          2 gate-bash-git.sh "$(pay Bash "$HOME" "command=glab api --method PUT projects/x/merge_requests/999/merge")"
$ST set mr= rebased_skipci= judge_ok_pre_push= tests_green=

echo "== gate-tmp =="
t "Write dans /tmp"                           2 gate-tmp.sh "$(pay Write "$HOME" "file_path=/tmp/x.md")"
t "Write dans le scratchpad du harness"       2 gate-tmp.sh "$(pay Write "$HOME" "file_path=/private/tmp/claude-502/s/n.md")"
t "Write dans ~/tmp/scratch"                  0 gate-tmp.sh "$(pay Write "$HOME" "file_path=$HOME/tmp/scratch/n.md")"
t "Bash qui lit /tmp"                         2 gate-tmp.sh "$(pay Bash "$HOME" "command=cat /tmp/foo.log")"
t "Bash mktemp (seule exception)"             0 gate-tmp.sh "$(pay Bash "$HOME" "command=f=\$(mktemp); cat \$f")"
t "Bash qui lit ~/tmp"                        0 gate-tmp.sh "$(pay Bash "$HOME" "command=cat $HOME/tmp/2026-09-02.md")"

echo "== gate-quiet-hours =="
WF_FAKE_HOUR=14 t "ScheduleWakeup en journée"  0 gate-quiet-hours.sh "$(pay ScheduleWakeup "$HOME" "delaySeconds=600")"
WF_FAKE_HOUR=22 t "ScheduleWakeup la nuit"     2 gate-quiet-hours.sh "$(pay ScheduleWakeup "$HOME" "delaySeconds=600")"
WF_FAKE_HOUR=22 t "boucle until la nuit"       2 gate-quiet-hours.sh "$(pay Bash "$HOME" "command=until glab ci status; do sleep 60; done")"
WF_FAKE_HOUR=22 t "juge synchrone la nuit"     0 gate-quiet-hours.sh "$(pay Agent "$HOME" "subagent_type=judge" "prompt=CHECKPOINT=pre-push ROUND=1")"
WF_FAKE_HOUR=3  t "gradlew test la nuit"       0 gate-quiet-hours.sh "$(pay Bash "$HOME" "command=./gradlew :accounting-backend:test")"

echo "== gate-external-lang =="
t "MR description en anglais"                 0 gate-external-lang.sh "$(pay Bash "$HOME" "command=glab mr create --title \"[X-1] Fix\" --description=This fixes the rounding of invoice amounts when the currency differs")"
t "MR description en francais"                2 gate-external-lang.sh "$(pay Bash "$HOME" "command=glab mr create --title \"[X-1] Arrondi\" --description=Corrige l arrondi des factures pour les clients dans une devise etrangere ainsi que les avoirs qui sont concernes")"
t "commentaire JIRA en francais"              2 gate-external-lang.sh "$(pay Bash "$HOME" "command=curl -X POST -u a:b https://x.atlassian.net/rest/api/3/issue/X-1/comment -d Les tests sont verts sur les modules touches ainsi que la pipeline")"
t "champ Prompt JIRA en francais (exception)"  0 gate-external-lang.sh "$(pay Bash "$HOME" "command=curl -X PUT -u a:b https://x.atlassian.net/rest/api/3/issue/X-1 -d customfield_11956 Corrige l arrondi des factures dans une devise etrangere ainsi que les avoirs")"
t "lecture JIRA (GET) non concernée"          0 gate-external-lang.sh "$(pay Bash "$HOME" "command=curl -s -u a:b https://x.atlassian.net/rest/api/3/issue/X-1?fields=summary")"

echo "== gate-skills =="
$ST set skills=
t "édition .vue sans skill"                   2 gate-skills.sh "$(pay Edit "$HOME" "file_path=$WT/T/app/components/VFoo.vue")"
$ST set skills=vue-best-practices,malt-frontend-conventions
t "édition .vue avec skills"                  0 gate-skills.sh "$(pay Edit "$HOME" "file_path=$WT/T/app/components/VFoo.vue")"
t "édition test backend sans skill"           2 gate-skills.sh "$(pay Edit "$HOME" "file_path=$WT/T/erp/x/src/test/kotlin/FooTest.kt")"
t "édition hors repo"                         0 gate-skills.sh "$(pay Edit "$HOME" "file_path=$HOME/notes.md")"
t "Grep monorepo sans pré-analyse (warn)"     0 gate-skills.sh "$(pay Grep "$HOME" "path=$MAIN_REPO/erp")"
$ST set skills=

echo "== wf-record : enregistrement =="
printf '%s' "$(pay Skill "$HOME" "skill=malt-accounting-domain")" | ./wf-record.sh >/dev/null
[[ "$($ST get skills)" == "malt-accounting-domain" && -n "$($ST get preanalysis)" ]] \
  && { pass=$((pass+1)); echo "  ok   Skill enregistré + pré-analyse levée"; } \
  || { fail=$((fail+1)); echo "  FAIL Skill non enregistré (skills=$($ST get skills))"; }
printf '{"tool_name":"Agent","tool_input":{"subagent_type":"judge","prompt":"CHECKPOINT=pre-push ROUND=1"},"tool_response":"VERDICT: OK"}' | ./wf-record.sh >/dev/null
[[ -n "$($ST get judge_ok_pre_push)" ]] \
  && { pass=$((pass+1)); echo "  ok   verdict juge OK enregistré"; } \
  || { fail=$((fail+1)); echo "  FAIL verdict juge non enregistré"; }
printf '{"tool_name":"Agent","tool_input":{"subagent_type":"smoke-runner","prompt":"x"},"tool_response":"BOOTED_OK en 92s"}' | ./wf-record.sh >/dev/null
[[ -n "$($ST get smoke_ok)" ]] \
  && { pass=$((pass+1)); echo "  ok   smoke-run enregistré"; } \
  || { fail=$((fail+1)); echo "  FAIL smoke-run non enregistré"; }

echo "== normalisation : un heredoc qui PARLE des commandes gardées =="
hd=$(python3 -c '
import json
print(json.dumps({"tool_name":"Bash","cwd":"/x","tool_input":{"command":"cat > f <<Z\nglab mr merge 999 --squash\ngit push origin master\nZ\necho done"}}))')
t "heredoc mentionnant merge/push"            0 gate-bash-git.sh "$hd"

echo "== crans (env) =="
WF_GATES_OFF=1       t "kill switch global"    0 gate-tmp.sh "$(pay Write "$HOME" "file_path=/tmp/x.md")"
WF_GATE_TMP_BAN=warn t "cran warn"             0 gate-tmp.sh "$(pay Write "$HOME" "file_path=/tmp/x.md")"

$ST reset
printf '\n%d ok, %d FAIL\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
