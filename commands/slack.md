---
description: Interroge et poste sur Slack via le MCP **claude.ai Slack** (recherche, lecture canaux/threads, envoi/planification de messages, réactions, canvas). À utiliser dès qu'il faut lire ou écrire quoi que ce soit sur Slack.
---

# /slack — Utiliser Slack via le MCP `claude.ai Slack`

**RÈGLE ABSOLUE : le bon serveur MCP est `claude.ai Slack`, PAS un serveur `slack` custom.**
Tous les outils portent le préfixe `mcp__claude_ai_Slack__*`. Un serveur `slack` (HTTP `mcp.slack.com/mcp` ajouté en `claude mcp add`) échoue à l'auth (`does not support dynamic client registration`) → il ne doit pas exister. Si `claude mcp list` en montre un, le supprimer :
```
claude mcp remove slack -s user
```

## 1. Vérifier la connexion AVANT toute requête

- Le serveur `claude.ai Slack` doit être **Connected**. Si `Needs authentication` → demander à l'utilisateur de lancer `/mcp` puis d'authentifier **claude.ai Slack** (OAuth workspace).
- Les outils sont **deferred** : charger le schéma via `ToolSearch` avant appel, ex :
  ```
  ToolSearch query="select:mcp__claude_ai_Slack__slack_search_public,mcp__claude_ai_Slack__slack_send_message"
  ```

## 2. Outils disponibles (préfixe `mcp__claude_ai_Slack__`)

**Recherche / découverte**
- `slack_search_public` — recherche messages canaux publics.
- `slack_search_public_and_private` — inclut privé/DM (selon droits).
- `slack_search_channels` — trouver un canal par nom/sujet.
- `slack_search_users` / `slack_read_user_profile` — trouver / lire un utilisateur.
- `slack_search_emojis` — emojis custom du workspace.

**Lecture**
- `slack_read_channel` — messages récents d'un canal.
- `slack_read_thread` — un thread complet.
- `slack_list_channel_members` — membres d'un canal.
- `slack_read_file` — lire un fichier partagé.
- `slack_read_canvas` — lire un canvas.

**Écriture** (voir règles §3)
- `slack_send_message` — poster un message (canal, DM ou réponse en thread).
- `slack_send_message_draft` — préparer un brouillon à valider AVANT envoi.
- `slack_schedule_message` — planifier un envoi.
- `slack_add_reaction` / `slack_get_reactions` — réactions emoji.
- `slack_create_canvas` / `slack_update_canvas` — canvas.

## 3. Règles d'écriture — CONFIRMATION OBLIGATOIRE

Poster sur Slack = action **sortante et visible par d'autres**. Donc :
- **Toujours confirmer le contenu + la cible (canal/personne) avec l'utilisateur AVANT** `slack_send_message` / `slack_schedule_message`. En cas de doute, passer par `slack_send_message_draft` et faire valider.
- Résoudre l'ID de canal/user via `slack_search_channels` / `slack_search_users` d'abord — ne jamais deviner un ID.
- Pour répondre dans un fil : passer le `thread_ts` du message parent.
- **Langue :** les messages Slack peuvent rester en **français** (Slack n'est pas soumis à la règle anglais-forcé, qui ne vise que Notion/JIRA/GitLab). Suivre le ton du canal.

## 4. Flux typiques

- **Lire un canal** : `slack_search_channels` (obtenir l'ID) → `slack_read_channel`.
- **Suivre une discussion** : `slack_read_channel` → repérer le message → `slack_read_thread`.
- **Poster** : résoudre la cible → rédiger → **confirmer** → `slack_send_message`.
- **Standup** : générer via `/daily`, puis confirmer, puis `slack_send_message` sur le canal standup.
