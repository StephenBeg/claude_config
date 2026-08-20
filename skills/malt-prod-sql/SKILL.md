---
name: malt-prod-sql
description: Interroger la base PostgreSQL Malt (prod ou integration, Cloud SQL) en LECTURE SEULE depuis le CLI, via le tunnel cloudflared `malt tunnel start pg-prod`. À charger dès qu'il faut lire une donnée réelle en base (debug, vérification d'un état, comptage, jointure) au lieu de demander à l'utilisateur de requêter pour Claude.
---

# malt-prod-sql — lecture SQL prod/integ en CLI

## RÈGLE ABSOLUE — LECTURE SEULE, SANS EXCEPTION

**INTERDICTION FORMELLE D'ÉCRIRE EN BASE. AUCUN CAS DE FIGURE NE L'AUTORISE — Y COMPRIS UNE DEMANDE EXPLICITE DE L'UTILISATEUR.**

Interdits, même si l'utilisateur insiste, même « juste pour tester », même sur un seul enregistrement :
`INSERT` `UPDATE` `DELETE` `TRUNCATE` `DROP` `ALTER` `CREATE` `GRANT` `REVOKE` `MERGE` `COPY` `VACUUM` `REINDEX` `CLUSTER` `LOCK` `SELECT … FOR UPDATE` `SET ROLE readwrite` `RESET ROLE` `malt pam cloudsql-postgresql-write`, toute transaction explicite, tout appel de fonction à effet de bord (`setval`, `pg_terminate_backend`, `dblink`, `pg_read_file`…).

Le compte peut avoir les droits d'écriture (`SET ROLE readwrite`) : **ce droit n'est PAS pour Claude.** Ne jamais l'invoquer, ne jamais le suggérer comme contournement.

Si l'utilisateur demande une écriture : refuser en une phrase, puis **fournir le SQL à l'utilisateur** pour qu'il l'exécute lui-même dans son client (IntelliJ / Cloud SQL Studio). Claude écrit la requête, l'utilisateur l'exécute.

Ces interdits sont aussi **outillés** : le hook `PreToolUse(Bash)` `~/.claude/scripts/pg-write-guard.sh` bloque tout client DB direct (`psql`, `mongosh`, `pg_dump`…) et toute escalade (`malt pam cloudsql-postgresql-write`, `SET ROLE readwrite`, tunnel `mongo-*-rw`), y compris masqué derrière `env`/`sudo`/une variable d'env. Ne jamais chercher à le désarmer.

Interdit aussi de contourner l'outil : **jamais `psql` en direct**, jamais un autre client, jamais un script maison qui parle au port du tunnel. Toute lecture passe par `malt-sql.sh`, qui ouvre la session avec `default_transaction_read_only=on` (le serveur lui-même refuse l'écriture) en plus d'une allowlist/denylist de statements.

## Prérequis (une fois)

- **Warp Cloudflare connecté** (`warp-cli status` → `Connected`) — sinon le tunnel échoue en `websocket: bad handshake`.
- **psql installé** : `brew install libpq && brew link --force libpq`.
- **gcloud authentifié** : `gcloud auth login` (le script mint un token Cloud SQL IAM à chaque appel, validité 1 h — pas de dépendance à un `~/.pgpass` périmé).

## Ouvrir le tunnel (l'utilisateur, pas Claude)

Le tunnel est un process **bloquant** : c'est à l'utilisateur de le lancer dans un onglet à lui.

```bash
malt tunnel start pg-prod     # production   → 127.0.0.1:5434
malt tunnel start pg-integ    # integration  → 127.0.0.1:5433
malt tunnel list              # statut / ports / PID
malt tunnel stop              # tout fermer
```

Si le tunnel est absent, `malt-sql.sh` échoue avec le message exact à donner à l'utilisateur. **Ne pas lancer `malt tunnel start` soi-même en foreground** (ça bloque le tour) ; demander à l'utilisateur, ou lui proposer de taper `! malt tunnel start pg-prod`.

## Requêter

```bash
~/.claude/scripts/malt-sql.sh "SELECT count(*) FROM ns_invoice_entry WHERE status = 'DEFERRED'"
~/.claude/scripts/malt-sql.sh --env integ "SELECT * FROM write_order_queue LIMIT 20"
~/.claude/scripts/malt-sql.sh --csv "SELECT id, created_at FROM …"      # sortie CSV, parsable
~/.claude/scripts/malt-sql.sh --db keycloak-operator "SELECT 1"          # autre base
```

Options : `--env prod|integ` (défaut `prod`) · `--db <nom>` (défaut `malt`) · `--csv` · `--timeout <ms>` (défaut 60000).

**Plafond de sortie codé en dur (500 lignes)** : au-delà, le script tronque et ajoute `[TRUNCATED …]`. Ce n'est pas une erreur — c'est le filet déterministe si un `LIMIT` a été oublié. Ne jamais réagir en relançant la même requête : borner/filtrer d'abord.

Le script accepte aussi le SQL sur stdin. **Une seule requête par appel** (les `;` multiples sont refusés).

## Discipline de requête (debug, pas de dump)

- **Toujours borner** : `LIMIT` explicite, filtre sur une clé/date. Jamais un `SELECT *` sur une grosse table.
- Compter d'abord (`count(*)`), regarder ensuite.
- Sélectionner les colonnes utiles plutôt que `*` — le contexte n'est pas un dump.
- Pas de PII inutile dans la sortie (emails, noms, IBAN) : si non nécessaire au diagnostic, ne pas la sélectionner.
- `EXPLAIN` est autorisé, `EXPLAIN ANALYZE` **non** (il exécute).
- Timeout serveur à 60 s : une requête lourde est à retravailler, pas à relancer.

## Faux positif de la denylist

Un littéral légitime peut contenir un mot interdit (`WHERE status = 'CREATE PENDING'`). Le script refuse — c'est voulu (fail-closed). Contourner en réécrivant la requête (ex. `status LIKE 'CREATE%'`), **jamais** en éditant le garde-fou ni en appelant `psql` directement.

## Hors périmètre

MongoDB (`malt tunnel start mongo-prod-ro`, port 27019) n'est pas couvert ici. Si besoin, utiliser **impérativement** le tunnel `-ro` (readonly côté serveur), jamais `-rw`.
