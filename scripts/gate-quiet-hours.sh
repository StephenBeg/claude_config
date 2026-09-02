#!/usr/bin/env bash
# PreToolUse(tous outils) — CLAUDE.md § HEURES CALMES 20h00 -> 07h00.
#
# "Vérifier date +%H%M avant de programmer" est un ordre donné au LLM : il
# l'oublie. Ici l'heure est lue par le HARNESS, pas par le modèle.
#
# Gelés dans la plage : ScheduleWakeup, CronCreate, RemoteTrigger, /loop, les
# boucles `until` en background qui ré-invoquent Claude, les réveils de surface
# (cmux-tab.sh wake/spawn/send/--notify) et le spawn d'/orchestrator.
# AUTORISÉ : un round de juge (appel synchrone borné, cf. malt-judge-loop), et
# toute action lancée par l'utilisateur en temps réel — d'où le mode warn
# possible et le kill switch.
#
# Gate : quiet-hours
set -uo pipefail
. "$HOME/.claude/scripts/wf-gates-lib.sh"

INPUT="$(cat)"
gate_is_quiet_hours || exit 0
TOOL="$(gate_field tool_name)"
NOW="$(date '+%H:%M')"

why="il est $NOW — HEURES CALMES (20h00-07h00). CLAUDE.md : aucune ré-invocation de Claude dans cette plage. Consigner l'état (fichiers, MR + numéro, JIRA + statut, /goal, où reprendre), poser l'onglet [WAIT] « paused — quiet hours », relance MANUELLE le matin. Si l'utilisateur est présent et le demande maintenant : `quiet-hours = off` dans ~/.claude/wf-gates.conf."

case "$TOOL" in
  ScheduleWakeup|CronCreate|RemoteTrigger|PushNotification)
    gate_deny quiet-hours "$TOOL programme un réveil : $why" ;;
  Bash)
    gate_load_cmd
    if gate_invoked 'claude( |$)' \
       || printf '%s' "$CMD_RAW" | grep -Eq 'cmux-tab\.sh +(wake|spawn|send)|--notify' \
       || printf '%s' "$CMD_RAW" | grep -Eq 'until .*(sleep|glab|gradlew).*(done|do)' ; then
      # une boucle/réveil en tâche de fond survit à la nuit
      gate_deny quiet-hours "cette commande réveille Claude ou boucle en attente : $why" ;
    fi ;;
  Skill)
    sk="$(gate_field tool_input skill)"
    case "$sk" in
      *loop*|*orchestrator*) gate_deny quiet-hours "/$sk ré-invoque Claude en boucle : $why" ;;
    esac ;;
  Agent)
    at="$(gate_field tool_input subagent_type)"
    pr="$(gate_field tool_input prompt)"
    if printf '%s' "$pr" | grep -qi 'orchestrator' && [[ "$at" != "judge" ]]; then
      gate_deny quiet-hours "spawn d'un orchestrateur : $why"
    fi ;;
esac
exit 0
