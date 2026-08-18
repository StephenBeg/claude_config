---
description: Interroge Datadog (logs, traces/APM, métriques, monitors) via la CLI `pup`. À utiliser dès qu'il faut lire des logs/traces/métriques prod Malt.
---

# /datadog — Interroger Datadog via `pup`

**RÈGLE ABSOLUE : pour toute interaction Datadog, utiliser la CLI `pup`.** Ne PAS taper l'API Datadog en `curl` à la main : `pup` porte l'auth (OAuth2) et la résolution de site. Un `curl` avec la seule `DD_API_KEY` de l'env **échoue en 401** (le Logs Search API exige aussi une Application Key que l'env n'expose pas).

`pup` = « Datadog API CLI ». Binaire : `/opt/homebrew/bin/pup`. Couvre logs, traces/APM, métriques, monitors, dashboards, incidents, events, RUM, SLOs… + `pup api` en passe-plat.

## 1. Vérifier l'auth AVANT toute requête

```
pup auth status
```

- Attendu : `authenticated: true`, `site: datadoghq.eu` (Malt = **EU**). Le token se rafraîchit tout seul (`has_refresh: true`).
- Si non authentifié / token expiré sans refresh → **demander à l'utilisateur** de lancer dans le prompt :
  ```
  ! pup auth login
  ```
  (login OAuth interactif — ne PEUT PAS être fait par Claude). Ne jamais essayer de contourner via curl/app-key.

## 2. Site

Malt est sur **datadoghq.eu**. `pup` le connaît via la session OAuth. Ne pas forcer `--site` sauf besoin explicite (`--trust-site` requis pour un host non-Datadog).

## 3. Global flags utiles

- `--output json|table|yaml|csv` (défaut `json`). Pour lecture humaine rapide → `--output table`.
- `--jq '<expr>'` : filtre la sortie via jq AVANT formatage (réduit le bruit / le contexte).
- `--read-only` : bloque toute écriture (create/update/delete). **Mettre `--read-only` par défaut** pour une simple investigation.
- `--org <name>` : multi-org.

## 4. Recettes

### Logs (le cas le plus fréquent)

Syntaxe de query = langage log Datadog : `service:`, `status:error`, `@attr.path:val`, `host:i-*`, `"phrase exacte"`, `AND/OR/NOT`.
Temps : `--from`/`--to` acceptent `1h`, `30m`, `7d`, `-2h`, `now`, RFC3339, ou timestamp ms.

```
# Erreurs d'un service sur 1h
pup logs search --query='service:accounting-backend status:error' --from='1h' --to='now' --limit=25 --output=table

# Cibler un endpoint précis par attribut HTTP path
pup logs search --query='service:accounting-backend @http.url_details.path:*/compare/*' --from='2h' --limit=25

# Query v2 (facets, storage tiers) + jq pour ne garder que message + timestamp
pup logs query --query='service:accounting-backend "IllegalStateException"' --from='4h' \
  --jq '.data[].attributes | {t:.timestamp, msg:.message}'

# Agréger (compter par status)
pup logs aggregate --query='service:accounting-backend' --compute='count' --group-by='status' --from='24h'
```

Storage tiers : `--storage indexes` (défaut, temps réel), `online-archives` (rehydraté, requêtes anciennes), `flex`.

### Traces / APM

```
# Spans d'une trace / d'un endpoint
pup traces search --query='service:accounting-backend resource_name:*compare*' --from='2h' --limit=20

# Stats agrégées sur les spans
pup traces aggregate --query='service:accounting-backend' --from='1h'

# Santé service APM
pup apm services list
```

### Métriques

```
pup metrics query --query='avg:accounting_sync.push.duration{*}' --from='2h'
```

### Monitors

```
pup monitors list
pup monitors search --query='accounting'
pup monitors get <monitor-id>
```

### Passe-plat API brut (si aucune sous-commande ne couvre le besoin)

```
pup api --method GET --path '/api/v2/logs/events/search' --raw-field '<json>'
```

## 5. Découvrir une sous-commande

Toutes les commandes sortent leur schéma JSON en `--help` (flags, sous-commandes, exemples) :

```
pup <cmd> --help
pup <cmd> <subcmd> --help
```

Domaines dispo (extrait) : `logs traces apm metrics monitors dashboards events incidents rum slos error-tracking synthetics security audit-logs api …`. Liste complète : `pup --help`.

## 6. Garde-fous

- **Investigation = lecture seule** : ajouter `--read-only`. Ne jamais créer/modifier/supprimer un monitor, dashboard, downtime, etc. sans demande explicite de l'utilisateur.
- Ne pas dumper des milliers de logs dans le contexte : borner avec `--limit` et filtrer via `--jq` / `--output table`. Pour un gros volume → écrire dans `~/tmp/scratch/` (cf. ÉTAT TEMPORAIRE ; jamais `/tmp`, purgé par macOS) et ne lire que la synthèse.
- Toujours préciser une fenêtre temporelle (`--from`/`--to`) — sinon défaut `1h`.

## Argument

`$ARGUMENTS` = ce que l'utilisateur veut chercher (service, endpoint, erreur, fenêtre de temps). Traduire en query `pup` appropriée, vérifier l'auth (§1), lancer, puis synthétiser le résultat (pas de dump brut).
