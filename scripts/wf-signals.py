#!/usr/bin/env python3
"""wf-signals.py — lecture des SIGNAUX de workflow (verdict de juge, smoke-run).

Un signal se lit dans un RÉSULTAT, jamais dans la requête qui l'a demandé. Deux
pièges mesurés imposent la forme de ce fichier :

1. `PostToolUse(Agent)` tire au LANCEMENT et son `tool_response` rejoue le prompt
   (clé `prompt`). Grep ce blob revient à grep la consigne : `resp-text` retire
   les champs d'écho avant tout examen.
2. Un compte rendu contient normalement les deux chaînes (« il aurait fallu X
   pour un OK »). La détection est donc ANCRÉE en début de ligne, et un
   NEEDS_WORK l'emporte toujours sur un OK.

Sous-commandes :
  resp-text                  stdin = payload de hook -> texte de réponse réel
  verdict-text               stdin = texte           -> OK | NEEDS_WORK | NONE
  smoke-text                 stdin = texte           -> BOOTED_OK | BOOT_FAILED | NONE
  verdict-file <f> <since>   compte rendu du juge    -> idem, postérieur à <since>
  smoke-file   <f> <since>   compte rendu du smoke   -> idem
"""
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

# Champs que le harnais renvoie au LANCEMENT d'un sous-agent : ils rejouent la
# requête ou décrivent la plomberie, aucun ne porte de résultat.
ECHO_FIELDS = {
    "prompt", "description", "outputFile", "canReadOutputFile",
    "agentId", "resolvedModel", "isAsync", "status", "subagent_type", "model",
}

VERDICT_LINE = re.compile(r"^[\s>*_`#\-]*(?:JUDGE-)?VERDICT\s*:?\s*(OK|NEEDS_WORK)\b", re.I)
SMOKE_LINE = re.compile(r"^[\s>*_`#\-]*(?:SMOKE-VERDICT\s*:?\s*)?(BOOTED_OK|BOOT_FAILED)\b", re.I)
REPORT_VERDICT = re.compile(r"(?:JUDGE-)?VERDICT\s*:?\s*(OK|NEEDS_WORK)\b", re.I)
REPORT_SMOKE = re.compile(r"SMOKE-VERDICT\s*:?\s*(BOOTED_OK|BOOT_FAILED)\b", re.I)
ISO = re.compile(r"(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})")


def resp_text(payload: str) -> str:
    try:
        d = json.loads(payload)
    except Exception:
        return ""
    r = d.get("tool_response")
    if isinstance(r, str):
        return r
    if isinstance(r, dict):
        kept = {k: v for k, v in r.items() if k not in ECHO_FIELDS}
        return "" if not kept else json.dumps(kept)
    if isinstance(r, list):
        return json.dumps(r)
    return ""


def scan(text: str, pattern, win: str) -> str:
    """Première valeur ancrée en début de ligne, <win> l'emportant sur l'autre."""
    found = ""
    for line in (text or "").splitlines():
        m = pattern.match(line)
        if not m:
            continue
        v = m.group(1).upper()
        if v == win:
            return v
        found = v
    return found or "NONE"


def epoch_of(line: str, fallback: float) -> float:
    m = ISO.search(line)
    if not m:
        return fallback
    try:
        dt = datetime.strptime(m.group(1) + " " + m.group(2), "%Y-%m-%d %H:%M:%S")
        return dt.replace(tzinfo=timezone.utc).timestamp()
    except Exception:
        return fallback


def scan_file(path: str, since: float, pattern, win: str) -> str:
    """Un verdict ne compte que s'il a été écrit APRÈS le lancement : sans ça un
    compte rendu d'un round précédent, présent dans la même inbox, lèverait le
    gate. L'horodatage de la ligne prime sur le mtime, que n'importe quelle autre
    surface écrivant dans la même inbox peut déplacer."""
    try:
        mtime = os.path.getmtime(path)
        with open(path, errors="ignore") as f:
            lines = f.readlines()
    except Exception:
        return "NONE"
    found = ""
    for line in lines:
        m = pattern.search(line)
        if not m:
            continue
        if epoch_of(line, mtime) < since:
            continue
        v = m.group(1).upper()
        if v == win:
            return v
        found = v
    return found or "NONE"


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    cmd, rest = args[0], args[1:]
    if cmd == "resp-text":
        print(resp_text(sys.stdin.read()))
    elif cmd == "verdict-text":
        print(scan(sys.stdin.read(), VERDICT_LINE, "NEEDS_WORK"))
    elif cmd == "smoke-text":
        print(scan(sys.stdin.read(), SMOKE_LINE, "BOOT_FAILED"))
    elif cmd in ("verdict-file", "smoke-file"):
        if len(rest) < 2:
            raise SystemExit("%s <fichier> <epoch de lancement>" % cmd)
        since = float(rest[1] or 0)
        if cmd == "verdict-file":
            print(scan_file(rest[0], since, REPORT_VERDICT, "NEEDS_WORK"))
        else:
            print(scan_file(rest[0], since, REPORT_SMOKE, "BOOT_FAILED"))
    elif cmd == "now":
        print(int(time.time()))
    else:
        raise SystemExit("commande inconnue: %s" % cmd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
