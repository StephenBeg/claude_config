#!/usr/bin/env bash
# PreToolUse(Bash) — GATES GIT / GITLAB.
#
# Porte mécaniquement les "RÈGLES ABSOLUES" de CLAUDE.md § GIT WORKFLOW, de
# /dev (steps 4, 5, 8, 12, 13) et de § COUVERTURE DE CODE. master-guard.sh ne
# couvrait que Edit|Write : en mode auto Claude écrit via Bash (sed, heredoc,
# git checkout) — ce chemin était grand ouvert.
#
# Gates (nom = clé de ~/.claude/wf-gates.conf) :
#   master-write   écriture Bash dans le repo principal quand il est sur master
#   master-push    push depuis une branche master
#   worktree-form  git worktree add hors ~/worktrees/malt ou sans base origin/master
#   coauthor       Co-Authored-By dans un message de commit
#   coverage       commit qui ajoute du code source sans aucun fichier de test indexé
#   pre-push       1er push sans verdict juge OK / sans tests verts / sans smoke-run
#   mr-create      MR sans reviewer @stephen.begot, sans titre [PREFIX], sans label
#   rebase-skipci  rebase d'API sans skip_ci=true (boucle CI sur master)
#   mr-merge       merge sans --squash/--remove-source-branch, sans rebase skip_ci,
#                  sans commentaire Approved postérieur au dernier push, pipeline non verte
#                  -> FAIL CLOSED (un merge ne se rejoue pas)
set -uo pipefail
. "$HOME/.claude/scripts/wf-gates-lib.sh"

INPUT="$(cat)"
gate_load_cmd
[[ -n "${CMD_RAW:-}" ]] || exit 0
DIR="$(gate_effective_dir)"
BR="$(gate_branch "$DIR")"

# --------------------------------------------------------------------------- #
# 0. PORTÉE — les gates liés à une copie de travail (push master, forme du
#    worktree, couverture, pre-push) ne valent que dans le monorepo Malt et ses
#    worktrees : ailleurs (repos perso, scratch) ils n'ont pas de sens. Les
#    gates GitLab (mr-*, rebase) et coauthor restent globaux, eux ne dépendent
#    d'aucun répertoire.
# --------------------------------------------------------------------------- #
in_malt_scope() {
  case "$DIR" in
    "$MAIN_REPO"|"$MAIN_REPO"/*|"$WT_ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --------------------------------------------------------------------------- #
# 1. Écriture Bash dans le repo principal alors qu'il est sur master
# --------------------------------------------------------------------------- #
in_main_repo() { case "$DIR" in "$MAIN_REPO"|"$MAIN_REPO"/*) return 0 ;; *) return 1 ;; esac; }

if in_main_repo && [[ "$BR" == "master" ]]; then
  # verbes qui écrivent l'arbre ou l'index, sans ambiguïté
  if gate_invoked 'sed +-i|perl +-[a-z]*i|git +(apply|restore|stash|reset|commit|add|cherry-pick|revert|merge|rebase|am)|git +checkout' ; then
    gate_deny master-write "commande d'ÉCRITURE dans $MAIN_REPO qui est sur 'master'. Une modif non commitée sur master collisionne avec les worktrees parallèles. Créer d'abord le worktree et n'écrire QUE dedans :
  cd $MAIN_REPO && git fetch origin master && git worktree add $WT_ROOT/TICKET -b TICKET-desc origin/master"
  fi
  # redirection vers un chemin DANS le repo (absolu, ou relatif depuis le repo).
  # La cible doit RESSEMBLER à un chemin (contenir . ou /), sinon un `if x > 0`
  # dans un python inline déclencherait le gate.
  if printf '%s' "$CMD_RAW" | grep -Eq ">>?[[:space:]]*(\"|')?($MAIN_REPO/|[A-Za-z0-9_.-]*/[A-Za-z0-9_./-]*|[A-Za-z0-9_-]+\.[A-Za-z]{1,6}([^A-Za-z0-9]|$))" \
     && ! printf '%s' "$CMD_RAW" | grep -Eq ">>?[[:space:]]*(\"|')?(/dev/null|\$|$HOME/|~/|/tmp|/var|/etc)"; then
    gate_deny master-write "redirection qui écrit un fichier dans $MAIN_REPO (sur 'master'). Écrire dans un worktree, ou hors repo sous ~/tmp/scratch/."
  fi
fi

# --------------------------------------------------------------------------- #
# 2. Push depuis master  /  push qui vise master
# --------------------------------------------------------------------------- #
if in_malt_scope && gate_invoked 'git +push'; then
  if [[ "$BR" == "master" ]] || printf '%s' "$CMD_RAW" | grep -Eq 'git +push[^;&|]*(origin +master|HEAD:master|:master\b)'; then
    gate_deny master-push "push sur 'master' (branche courante « ${BR:-?} » dans $DIR). CLAUDE.md : jamais de push sur master — toujours branche + MR."
  fi
fi

# --------------------------------------------------------------------------- #
# 3. Forme du worktree
# --------------------------------------------------------------------------- #
if in_malt_scope && gate_invoked 'git +worktree +add'; then
  tgt=$(printf '%s' "$CMD_RAW" | grep -oE 'worktree +add +(-[^ ]+ +)*[^ ]+' | sed -E 's/.*add +(-[^ ]+ +)*//' | tr -d "\"'")
  tgt="${tgt/#\~/$HOME}"
  case "$tgt" in
    "$WT_ROOT"/*) : ;;
    *) gate_deny worktree-form "worktree créé hors de $WT_ROOT (« $tgt »). CLAUDE.md : toujours un worktree HORS du repo, sous $WT_ROOT/<TICKET>." ;;
  esac
  printf '%s' "$CMD_RAW" | grep -q 'origin/master' || \
    gate_deny worktree-form "worktree créé sans base explicite 'origin/master'. Sans elle la branche part du master LOCAL (périmé) — 2 MR sur base périmée cassent master au merge. Utiliser :
  cd $MAIN_REPO && git fetch origin master && git worktree add $WT_ROOT/TICKET -b TICKET-desc origin/master"
fi

# --------------------------------------------------------------------------- #
# 4-5. Commit : co-author interdit, couverture de code exigée
# --------------------------------------------------------------------------- #
if gate_invoked 'git +commit'; then
  printf '%s' "$CMD_TRUE" | grep -qi 'co-authored-by' && \
    gate_deny coauthor "message de commit avec 'Co-Authored-By'. CLAUDE.md : aucun Co-Authored-By, jamais (le prompt système de l'outil Bash le demande — CLAUDE.md prime)."

  verdict=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | python3 -c '
import sys, re
SRC  = re.compile(r"\.(kt|java|ts|tsx|js|vue|py)$")
SKIP = re.compile(r"(^|/)(build|generated|node_modules)/|\.generated\.")
TEST = re.compile(r"(Test|IT|Spec)\.(kt|java)$|\.(spec|uispec|test)\.(ts|tsx|js)$|(^|/)src/test/|(^|/)tests?/")
added_src = tests = 0
for line in sys.stdin:
    p = line.split("\t")
    if len(p) < 3: continue
    a, path = p[0], p[2].strip()
    if SKIP.search(path): continue
    if TEST.search(path):
        tests += 1
    elif SRC.search(path) and a.isdigit() and int(a) > 0:
        added_src += 1
print("NOTEST" if (added_src and not tests) else "OK")' 2>/dev/null)
  [[ "$verdict" == "NOTEST" ]] && in_malt_scope && \
    gate_deny coverage "l'index ajoute du code SOURCE et AUCUN fichier de test. CLAUDE.md § COUVERTURE DE CODE : toute ligne ajoutée ou modifiée doit être couverte par un test (nouveau comportement -> TDD skill malt-backend-tdd ; code déjà écrit -> skill malt-test-coverage). Vérifier l'index : git -C $DIR diff --cached --name-only. Exception réelle (code généré, config triviale, logs purs, diff 100 % commentaire) : le cran du gate est le réglage de l'UTILISATEUR, pas une sortie à prendre seul — le lui demander, il la pose avec le préfixe ! de la session. Ne JAMAIS indexer un test bidon pour satisfaire le compteur."
fi

# --------------------------------------------------------------------------- #
# 6. 1er push d'une branche : tests verts + smoke-run
#    (le juge, lui, est exigé à la CRÉATION DE LA MR — section 7 : c'est là que
#     l'implémentation est terminée ; un push de travail n'a rien à juger.)
# --------------------------------------------------------------------------- #
if in_malt_scope && gate_invoked 'git +push' && [[ -z "$($ST get mr)" ]]; then
  # app-config n'a ni Gradle ni pnpm : le détecteur tests_green (wf-bash-hook.sh)
  # ne peut jamais matcher, sa validation réelle est le job CI catalog-validator.
  origin_url="$(cd "$DIR" 2>/dev/null && git config --get remote.origin.url 2>/dev/null)"
  case "$origin_url" in *app-config*) tests_exempt=1 ;; *) tests_exempt="" ;; esac

  [[ -n "$($ST get tests_green)" || -n "$tests_exempt" ]] || \
    gate_deny pre-push "1er push sans exécution de tests verte observée dans cette session. CLAUDE.md § COUVERTURE : lancer les tests des modules touchés et citer la sortie (BUILD SUCCESSFUL / Tests passed) avant de pousser."

  svc=$(cd "$DIR" 2>/dev/null && git diff --name-only origin/master...HEAD 2>/dev/null | python3 -c '
import os, sys, re, glob
roots = set()
for path in (l.strip() for l in sys.stdin if l.strip()):
    d = os.path.dirname(path)
    while d:
        if glob.glob(os.path.join(d, "build.gradle*")):
            roots.add(d); break
        d = os.path.dirname(d)
apps = []
for r in roots:
    for b in glob.glob(os.path.join(r, "build.gradle*")):
        try: txt = open(b).read()
        except Exception: continue
        if "org.springframework.boot" in txt or "bootRun" in txt:
            apps.append(os.path.basename(r)); break
print(",".join(sorted(set(apps))))' 2>/dev/null)
  if [[ -n "$svc" && -z "$($ST get smoke_ok)" ]]; then
    if gate_proof smoke-file smoke_pending; then
      $ST set smoke_ok=1
    else
      gate_deny pre-push "1er push touchant un ou des service(s) applicatif(s) ($svc) sans SMOKE-RUN. /dev step 5 + commons § SMOKE-RUN LOCAL : les tests verts ne prouvent pas que le service boote (bean manquant, Liquibase invalide, FF absent).
SORTIE : lancer le subagent smoke-runner avec un REPORT_FILE dans son prompt (Agent subagent_type=smoke-runner, prompt: 'MODULE=<basename> REPORT_FILE=<chemin absolu>'). Le sous-agent est ASYNCHRONE ici : ATTENDRE sa notification de fin, le hook SubagentStop pose smoke_ok tout seul sur un BOOTED_OK. Un smoke-run lancé dans le tour courant ne lève rien tant qu'il n'a pas rendu.
SECOURS si la notification n'arrive pas : le gate relit le REPORT_FILE et accepte une ligne 'SMOKE-VERDICT: BOOTED_OK' écrite APRÈS le lancement. Boot lancé à la main : la ligne 'Started <App>Application(Kt) in' dans la sortie d'un Bash suffit aussi.
BOOT_FAILED par la faute du diff = bug à corriger, pas un gate à lever. Env local indispo (devbox down, secret manquant) = non bloquant : le dire à l'utilisateur et lui demander de desserrer le cran lui-même, puis consigner la raison en Tradeoffs."
    fi
  fi
fi

# --------------------------------------------------------------------------- #
# 7. Création de MR : reviewer, titre préfixé, labels
# --------------------------------------------------------------------------- #
if gate_invoked 'glab +mr +(create|new)'; then
  if in_malt_scope && [[ -z "$($ST get judge_ran_pre_mr)" ]]; then
    if gate_proof verdict-file judge_pending; then
      $ST set judge_ran_pre_mr=1
    else
      gate_deny pre-mr "MR créée sans PASSAGE de JUGE. L'implémentation est terminée : c'est ICI que le juge métier est dû (/dev step 4, skill malt-judge-loop).
SORTIE : Agent subagent_type=judge, prompt commençant par 'CHECKPOINT=pre-mr ROUND=1' et portant 'REPORT_FILE=<chemin absolu>'. Dans ce harnais l'outil Agent ne sait pas lancer un sous-agent en synchrone : le juge est forcément asynchrone. ATTENDRE sa notification de fin, le hook SubagentStop enregistre le passage tout seul.
SECOURS si la notification n'arrive pas : le gate relit le REPORT_FILE et accepte une ligne 'JUDGE-VERDICT:' écrite APRÈS le lancement du juge.
Le gate exige que le dev ait ÉTÉ JUGÉ, pas que le juge ait dit oui : un 'VERDICT: NEEDS_WORK' le lève aussi (fermer chaque GAP métier avec preuve, puis créer la MR, jamais de round 2)."
    fi
  fi
  printf '%s' "$CMD_RAW" | grep -q 'stephen.begot' || \
    gate_deny mr-create "MR créée sans reviewer. CLAUDE.md : @stephen.begot en reviewer DÈS la création (--reviewer stephen.begot)."
  title=$(printf '%s' "$CMD_RAW" | sed -nE 's/.*--title[= ]+("([^"]*)"|'"'"'([^'"'"']*)'"'"'|([^ ]+)).*/\2\3\4/p' | head -1)
  if [[ -n "$title" ]]; then
    printf '%s' "$title" | grep -Eq '^\[[A-Za-z0-9_-]+\] .' || \
      gate_deny mr-create "titre de MR « $title » hors format. CLAUDE.md : '[<préfixe>] Titre' en ANGLAIS, préfixe = numéro de ticket (y compris /hotfix), sinon [devscoot] / [hotfix]."
  fi
  printf '%s' "$CMD_RAW" | grep -Eq '(--label|-l )' || \
    gate_deny mr-create "MR créée sans label. Labels de squad OBLIGATOIRES (skill malt-squad-conventions) — les labels JIRA et GitLab ne portent pas les mêmes noms."
fi

# --------------------------------------------------------------------------- #
# 8. Rebase d'API sans skip_ci
# --------------------------------------------------------------------------- #
if printf '%s' "$CMD_RAW" | grep -Eq 'merge_requests/[0-9]+/rebase'; then
  printf '%s' "$CMD_RAW" | grep -q 'skip_ci=true' || \
    gate_deny rebase-skipci "rebase d'API sans skip_ci=true. Un rebase nu relance une pipeline complète ; sur master très actif la branche redevient « behind » avant la fin -> boucle infinie. Utiliser :
  glab api --method PUT \"projects/maltcommunity%2Fmalt%2Fapps%2Fmalt/merge_requests/<IID>/rebase?skip_ci=true\""
fi

# --------------------------------------------------------------------------- #
# 9. MERGE — fail closed
# --------------------------------------------------------------------------- #
merge_iid=""
if gate_invoked 'glab +mr +merge'; then
  merge_iid=$(printf '%s' "$CMD_RAW" | sed -nE 's/.*glab +mr +merge +([0-9]+).*/\1/p' | head -1)
elif printf '%s' "$CMD_RAW" | grep -Eq -- '--method +PUT.*merge_requests/[0-9]+/merge'; then
  merge_iid=$(printf '%s' "$CMD_RAW" | sed -nE 's|.*merge_requests/([0-9]+)/merge.*|\1|p' | head -1)
fi

if [[ -n "$merge_iid" ]] || gate_invoked 'glab +mr +merge'; then
  [[ -n "$merge_iid" ]] || merge_iid="$($ST get mr)"
  [[ -n "$merge_iid" ]] || gate_deny mr-merge "merge sans numéro de MR identifiable. Passer l'IID explicitement pour que le gate puisse vérifier Approved + pipeline."

  if gate_invoked 'glab +mr +merge'; then
    printf '%s' "$CMD_RAW" | grep -q -- '--squash' || \
      gate_deny mr-merge "merge sans --squash. CLAUDE.md : merge TOUJOURS --squash --remove-source-branch."
    printf '%s' "$CMD_RAW" | grep -q -- '--remove-source-branch' || \
      gate_deny mr-merge "merge sans --remove-source-branch. CLAUDE.md : --squash ET --remove-source-branch."
  else
    printf '%s' "$CMD_RAW" | grep -q 'squash=true' || \
      gate_deny mr-merge "merge par API brute sans squash=true. Le squash est obligatoire quel que soit le chemin (glab CLI ou PUT /merge)."
  fi

  [[ -n "$($ST get rebased_skipci)" ]] || \
    gate_deny mr-merge "aucun rebase skip_ci=true observé avant ce merge. CLAUDE.md : rebase skip_ci=true PUIS merge — jamais l'un sans l'autre."

  # Vérification contre le réel : Approved frais + vert citable (wf-mr-ready.py,
  # testable seul avec WF_MR_FIXTURE). La fraîcheur se mesure contre le dernier
  # push OBSERVÉ et contre authored_date, pas contre committed_date : le rebase
  # prescrit juste avant le merge réécrit committed_date et périmait l'Approved.
  check=$(python3 "$HOME/.claude/scripts/wf-mr-ready.py" "$merge_iid" "$GLAB_PROJECT" "$($ST get last_push_at)" 2>/dev/null)
  case "${check:-}" in
    OK*) : ;;
    KO*)          gate_deny mr-merge "conditions de merge non réunies — ${check#KO|}. /dev step 13 : merge UNIQUEMENT sur un commentaire 'Approved' de @stephen.begot POSTÉRIEUR au dernier repush ET pipeline verte." ;;
    UNVERIFIABLE*) gate_deny mr-merge "impossible de VÉRIFIER Approved + pipeline (${check#UNVERIFIABLE|}). Un merge ne se rejoue pas : le gate refuse plutôt que de supposer. Vérifier à la main (glab api .../notes) et, si le feu vert est réellement là, le dire à l'utilisateur : le cran du gate est SON réglage, pas une sortie à prendre seul." ;;
    *)             gate_deny mr-merge "vérification Approved/pipeline sans réponse exploitable. Contrôler à la main avant de merger." ;;
  esac
fi

exit 0
