#!/usr/bin/env python3
"""wf-state.py — état de workflow PAR SURFACE, partagé entre cmux-tab.sh et les hooks.

Le header CMUX, la MR et le /end ne peuvent pas dépendre du zèle du LLM : ils
dépendent de CE fichier, écrit par `cmux-tab.sh` et par les hooks déterministes
(PostToolUse / UserPromptSubmit / Stop / SessionStart).

Fichier : ~/claude-exchange-llm/_phase/<SURFACE>.json   (JAMAIS /tmp — CLAUDE.md)

Champs :
  phase      préfixe courant (ORCH|PLAN|IMPL|PIPE|MR|ASK|BLOCK|WAIT|CLEAN|END|JUGE)
  prev_phase phase d'avant un [ASK]/[BLOCK]/[WAIT] — sert à en RESSORTIR tout seul
  topic      résumé 3-4 mots, stable entre les phases (ce qu'on FAIT)
  ticket     numéro JIRA si connu
  branch     branche de travail
  mr         IID de la MR (dès que le hook la voit passer)
  merged     1 quand la MR a été mergée
  end_done   1 quand /end a écrit le log du jour (vérifié, pas déclaré)
"""
import json
import os
import sys
import time

PHASES = ["ORCH", "PLAN", "IMPL", "PIPE", "MR", "ASK", "BLOCK", "WAIT", "CLEAN", "END", "JUGE"]
# Phases "d'attente" : on mémorise ce qu'on faisait avant pour y revenir seul.
TRANSIENT = {"ASK", "BLOCK", "WAIT"}
DIR = os.path.expanduser("~/claude-exchange-llm/_phase")


def surface() -> str:
    s = os.environ.get("CMUX_SURFACE_ID") or os.environ.get("WF_SURFACE_ID") or "default"
    return "".join(c for c in s if c.isalnum() or c in "-_") or "default"


def path() -> str:
    return os.path.join(DIR, surface() + ".json")


def load() -> dict:
    try:
        with open(path()) as f:
            return json.load(f)
    except Exception:
        return {}


def save(st: dict) -> None:
    os.makedirs(DIR, exist_ok=True)
    st["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    tmp = path() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, indent=1, sort_keys=True)
    os.replace(tmp, path())  # atomique


def title(st: dict) -> str:
    ph = st.get("phase")
    if not ph:
        return ""
    mr = st.get("mr")
    head = "[%s (%s)]" % (ph, mr) if (mr and ph in ("MR", "PIPE")) else "[%s]" % ph
    topic = (st.get("topic") or "").strip()
    return (head + " " + topic).strip()


def set_phase(st: dict, ph: str, topic: str | None = None) -> dict:
    ph = ph.upper()
    if ph not in PHASES:
        raise SystemExit("phase invalide: %s (attendu %s)" % (ph, "|".join(PHASES)))
    cur = st.get("phase")
    # Entrer dans une phase d'attente : mémoriser d'où on vient pour en ressortir.
    if ph in TRANSIENT and cur and cur not in TRANSIENT:
        st["prev_phase"] = cur
    if ph not in TRANSIENT:
        st.pop("prev_phase", None)
    st["phase"] = ph
    if topic:
        st["topic"] = topic.strip()
    return st


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    cmd, rest = args[0], args[1:]
    st = load()

    if cmd == "path":
        print(path())
    elif cmd == "get":
        if rest:
            print(st.get(rest[0], "") or "")
        else:
            print(json.dumps(st, sort_keys=True))
    elif cmd == "set":
        for kv in rest:
            k, _, v = kv.partition("=")
            if v == "":
                st.pop(k, None)
            else:
                st[k] = v
        save(st)
    elif cmd == "phase":
        if not rest:
            raise SystemExit("phase <PREFIX> [topic]")
        set_phase(st, rest[0], rest[1] if len(rest) > 1 else None)
        save(st)
        print(title(st))
    elif cmd == "title":
        print(title(st))
    elif cmd == "show":
        if not st.get("phase"):
            return 0
        bits = [title(st) or "(pas de phase)"]
        for k in ("ticket", "branch", "mr"):
            if st.get(k):
                bits.append("%s=%s" % (k, st[k]))
        if st.get("merged"):
            bits.append("MR mergée")
        bits.append("/end " + ("fait" if st.get("end_done") else "PAS fait"))
        print(" · ".join(bits))
    elif cmd == "reset":
        if os.path.exists(path()):
            os.remove(path())
    else:
        raise SystemExit("commande inconnue: %s" % cmd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
