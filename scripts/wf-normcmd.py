#!/usr/bin/env python3
"""Normalise la commande Bash d'un payload de hook, pour DÉTECTER UNE INVOCATION.

Lit le JSON du hook sur stdin, écrit sur stdout la commande aplatie sur une
ligne, débarrassée de ce qui n'est PAS du code shell exécuté :

1. corps des heredocs — c'est de la DONNÉE. Sans ça, un `cat > f <<EOF … glab mr
   merge … EOF` est lu comme un merge : un fichier qui PARLE des commandes
   gardées se fait bloquer (faux positif observé et reproduit).
2. contenu des chaînes citées — un `git commit -m "… git push …"` ne pousse rien.

Le résultat sert UNIQUEMENT au pattern-matching d'invocation. Les vérifications
de CONTENU (message de commit, titre de MR, skip_ci dans une URL) travaillent
sur la commande BRUTE, pas sur cette sortie.
"""
import json
import re
import sys

HEREDOC = re.compile(r"<<-?\s*[\x22\x27]?([A-Za-z_][A-Za-z0-9_]*)[\x22\x27]?")
QUOTED = re.compile(r"\x27[^\x27]*\x27|\x22[^\x22]*\x22")


def strip_heredocs(cmd: str) -> str:
    while True:
        m = HEREDOC.search(cmd)
        if not m:
            return cmd
        rest = cmd[m.end():]
        end = re.search(r"(?:^|\s)" + re.escape(m.group(1)) + r"(?:\s|$)", rest)
        cmd = cmd[:m.start()] + " HEREDOC " + (rest[end.end():] if end else "")
        if not end:
            return cmd


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    cmd = strip_heredocs(
        ((payload.get("tool_input") or {}).get("command") or "").replace("\n", " "))
    # --keep-quotes : heredocs retires mais chaines citees CONSERVEES. Necessaire
    # pour detecter un appel dont l argument vit entre quotes (une URL d API :
    # "projects/.../rebase?skip_ci=true").
    print(cmd if "--keep-quotes" in sys.argv else QUOTED.sub(" Q ", cmd))
    return 0


if __name__ == "__main__":
    sys.exit(main())
