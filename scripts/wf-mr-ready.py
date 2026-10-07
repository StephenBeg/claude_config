#!/usr/bin/env python3
"""wf-mr-ready.py — conditions réelles d'un merge : Approved frais + vert citable.

Le gate mr-merge est fail closed, donc sa prémisse doit être SATISFIABLE après la
procédure que CLAUDE.md prescrit (rebase skip_ci=true puis merge --squash). Elle
ne l'était pas, trois fois de suite (BILL-3534, BILL-3587, et la mémoire associée) :

- le rebase crée un nouveau `committed_date`, donc l'`Approved` qui l'a autorisé
  devenait « antérieur au dernier push ». La fraîcheur se mesure donc contre
  `authored_date`, que le rebase préserve, et contre le dernier push réellement
  OBSERVÉ par les hooks ;
- `skip_ci=true` crée une pipeline de tête `skipped`, jamais `success`. Un vert
  obtenu avant le rebase reste valable si le rebase n'a rien changé DANS LES
  FICHIERS DE LA MR : c'est vérifié par `repository/compare`, pas supposé.

Un `failed`, un `running` ou une absence de vert restent refusés.

Usage : wf-mr-ready.py <iid> <project> [dernier push ISO observé]
Sortie : OK|<note>  ·  KO|<problèmes>  ·  UNVERIFIABLE|<cause>
Tests  : WF_MR_FIXTURE=<json> remplace les appels glab par une table chemin -> objet.
"""
import json
import os
import subprocess
import sys
import urllib.parse

APPROVER = "stephen.begot"


class ApiError(RuntimeError):
    pass


def api(path: str):
    fixture = os.environ.get("WF_MR_FIXTURE")
    if fixture:
        with open(fixture) as f:
            table = json.load(f)
        if path not in table:
            raise ApiError("fixture sans entrée pour %s" % path)
        return table[path]
    r = subprocess.run(["glab", "api", path], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise ApiError((r.stderr or "glab a échoué").strip().splitlines()[0])
    return json.loads(r.stdout)


def paths_of(diffs) -> set:
    out = set()
    for d in diffs or []:
        for k in ("new_path", "old_path"):
            if d.get(k):
                out.add(d[k])
    return out


def green_is_transferable(base, iid, green_sha, head_sha):
    """Le vert pré-rebase vaut pour la tête si le rebase n'a touché aucun fichier
    de la MR. Il reste un risque de conflit sémantique (master peut casser mon
    code sans toucher mes fichiers) : il est assumé et nommé dans la note."""
    mine = paths_of((api(base + "/changes").get("changes")))
    moved = paths_of(api("%s/repository/compare?from=%s&to=%s"
                         % (base.split("/merge_requests/")[0],
                            urllib.parse.quote(green_sha, safe=""),
                            urllib.parse.quote(head_sha, safe=""))).get("diffs"))
    return not (mine & moved), sorted(mine & moved)[:5]


def main() -> int:
    iid, project = sys.argv[1], sys.argv[2]
    observed_push = sys.argv[3] if len(sys.argv) > 3 else ""
    pid = urllib.parse.quote(project, safe="")
    base = "projects/%s/merge_requests/%s" % (pid, iid)

    try:
        mr = api(base)
        notes = api(base + "/notes?per_page=100&sort=desc")
    except Exception as e:
        print("UNVERIFIABLE|%s" % e)
        return 0

    head_sha = mr.get("sha") or ""
    authored = ""
    if head_sha:
        try:
            authored = api("projects/%s/repository/commits/%s" % (pid, head_sha)).get("authored_date", "")
        except Exception:
            authored = ""
    reference = max([d for d in (authored, observed_push) if d] or [""])

    approved = [n for n in notes
                if not n.get("system")
                and (n.get("author") or {}).get("username") == APPROVER
                and (n.get("body") or "").strip().lower() == "approved"]
    fresh = [n for n in approved if not reference or n.get("created_at", "") > reference]

    problems, notes_out = [], []

    status = (mr.get("head_pipeline") or {}).get("status") or "aucune"
    if status == "success":
        notes_out.append("pipeline de tête verte")
    elif status == "skipped":
        try:
            allowed = bool(api("projects/%s" % pid).get("allow_merge_on_skipped_pipeline"))
            pipes = api(base + "/pipelines")
            greens = [p for p in pipes if p.get("status") == "success" and p.get("sha") != head_sha]
            if not allowed:
                problems.append("pipeline de tête = skipped et le projet interdit le merge sur pipeline skipped")
            elif not greens:
                problems.append("pipeline de tête = skipped et aucune pipeline verte sur cette MR")
            else:
                green = greens[0]
                ok, clash = green_is_transferable(base, iid, green["sha"], head_sha)
                if ok:
                    notes_out.append("pipeline de tête skipped (rebase skip_ci) mais vert transférable : "
                                     "pipeline %s verte sur %s, et le rebase n'a touché aucun fichier de la MR. "
                                     "Risque résiduel assumé : un conflit sémantique ne se voit pas dans les chemins."
                                     % (green.get("id"), (green.get("sha") or "")[:11]))
                else:
                    problems.append("pipeline de tête = skipped et le vert de référence n'est plus transférable, "
                                    "master a modifié des fichiers de la MR depuis : %s" % ", ".join(clash))
        except Exception as e:
            print("UNVERIFIABLE|%s" % e)
            return 0
    else:
        problems.append("pipeline de tête = %s (attendu success, ou skipped avec un vert transférable)" % status)

    if not approved:
        problems.append("aucun commentaire 'Approved' de @%s dans les 100 dernières notes" % APPROVER)
    elif not fresh:
        problems.append("le dernier 'Approved' (%s) est antérieur au dernier travail poussé (%s) : "
                        "il est périmé, redemander un Approved"
                        % (approved[0].get("created_at"), reference))

    print(("KO|" + " ; ".join(problems)) if problems else ("OK|" + " ; ".join(notes_out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
