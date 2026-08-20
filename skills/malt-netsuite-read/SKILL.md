---
name: malt-netsuite-read
description: Interroger NetSuite (prod ou sandbox) en LECTURE SEULE depuis le CLI, via SuiteQL, avec `~/.claude/scripts/malt-netsuite.py`. À charger dès qu'il faut vérifier l'état réel d'une donnée dans NetSuite — une facture a-t-elle été intégrée, avec quel statut/montant, un customer existe-t-il, un paiement est-il appliqué — au lieu de supposer ou de demander à l'utilisateur d'aller regarder dans l'UI.
---

# malt-netsuite-read — lecture NetSuite en CLI

## RÈGLE ABSOLUE — LECTURE SEULE, SANS EXCEPTION

**INTERDICTION FORMELLE D'ÉCRIRE DANS NETSUITE. AUCUN CAS DE FIGURE NE L'AUTORISE — Y COMPRIS UNE DEMANDE EXPLICITE DE L'UTILISATEUR.**

Le token TBA configuré est porté par le **rôle prod read-write** : NetSuite ne refusera pas une écriture pour toi. Ce droit n'est PAS pour Claude. Ce qui rend l'écriture impossible, c'est le chemin imposé, pas le rôle.

Si l'utilisateur demande une écriture : refuser en une phrase, puis **lui fournir la requête ou la manip** pour qu'il l'exécute lui-même dans l'UI NetSuite.

## Comment la lecture seule est garantie — 3 couches

1. **Transport** — `malt-netsuite.py` ne construit qu'une seule requête : `POST /services/rest/query/v1/suiteql`. La **Record API** (`POST|PATCH|DELETE /record/v1/…`), seul chemin d'écriture de l'API REST NetSuite, n'est pas implémentée du tout.
2. **Serveur** — le parseur SuiteQL de NetSuite est read-only *by design* : il refuse tout DML/DDL. **C'est la couche non contournable** : elle ne dépend d'aucune logique locale.
3. **Statement** — allowlist locale (`SELECT` / `WITH`) + denylist de mots-clés, comme filet qui échoue vite avec un message clair.

Le hook `PreToolUse(Bash)` `~/.claude/scripts/netsuite-write-guard.sh` bloque en plus tout appel réseau direct vers un host `*.netsuite.com` (curl, wget, python inline, y compris masqué derrière `sudo`/`env`) et toute lecture du token dans le keychain. **Ne jamais chercher à le désarmer, ne jamais écrire un script maison qui parle à NetSuite.**

## Prérequis (une fois)

Les credentials TBA vivent dans le **keychain macOS**, jamais en clair sur disque. Elles sont amorcées depuis les secrets SOPS d'app-config :

```
malt-netsuite.py --setup prod --from-config
malt-netsuite.py --setup sandbox --from-config
```

Le script déchiffre `app-config/helm/spring-apps-template/configurations/netsuite-connector/spring-secrets.production.enc.yaml` en mémoire (prod sous `netsuite.<clé>`, sandbox sous le jumeau `.sandbox`) et écrit le keychain lui-même : **aucun secret n'atteint stdout ni le log de session**. Il n'imprime qu'un accusé (accountId + serviceUri + nombre de champs).

Prérequis : `sops` installé et accès KMS `malt-platform-production`. Checkout app-config ailleurs que `~/Documents/projects/app-config` → `MALT_APP_CONFIG=<chemin>`.

**Ne jamais faire `sops -d` à la main sur ce fichier** : le token prod read-write atterrirait dans le transcript. Le hook le bloque.

Sans `--from-config`, `--setup <env>` imprime seulement le gabarit de commande, à remplir et exécuter par l'utilisateur.

## Usage

```
~/.claude/scripts/malt-netsuite.py "SELECT id, tranid, status FROM transaction WHERE tranid = 'FRIN-123'"
~/.claude/scripts/malt-netsuite.py --env sandbox --json "SELECT ..."
~/.claude/scripts/malt-netsuite.py --limit 20 --csv "SELECT ..."
echo "SELECT 1 FROM dual" | ~/.claude/scripts/malt-netsuite.py
```

`--env prod` par défaut. Pagination automatique par pages de 1000. Un `401 INVALID_LOGIN_ATTEMPT` transitoire est retenté une fois avec un nonce frais (BILL-2830).

## Pièges SuiteQL (vérifiés dans le code du monorepo)

- **Les clés de colonnes reviennent en minuscules**, quelle que soit la casse écrite dans le `SELECT`. La sortie les garde telles quelles — ne jamais réinventer une casse.
- **Les colonnes sortent par ordre alphabétique**, pas dans l'ordre du `SELECT` (NetSuite renvoie un objet JSON par ligne). La colonne de métadonnées `links` est filtrée par le script.
- **`trandate` sort au format `JJ/MM/AAAA`** (locale du compte), pas en ISO. Pour comparer une date, passer par `TO_DATE('2026-08-01','YYYY-MM-DD')`.
- `type = 'CustInvc'` pour les factures client, `'CustCred'` pour les avoirs, `'CustPymt'` / `'VendPymt'` pour les paiements, `'VendBill'` pour les factures fournisseur.
- `totalResults` plafonne à 5000 : « (5 rows of 5000) » ne veut pas dire qu'il y a exactement 5000 lignes.
- `FROM dual` existe (pratique pour un test de connexion).
- Les jointures se font sur les tables analytics : `transaction`, `transactionline`, `customer`, `vendor`, `subsidiary`, `accountingperiod`, `currency`.
- L'`externalId` Malt est dans `transaction.externalid` ; le numéro métier dans `transaction.tranid`.
- Pas de `LIMIT` en SQL — utiliser `--limit`, qui pilote la pagination REST.

## Requêtes utiles

Une facture est-elle intégrée, et dans quel état ?
```sql
SELECT id, tranid, externalid, type, status, trandate, foreigntotal, currency
FROM transaction WHERE externalid = 'FRIN-123'
```

Tous les documents rattachés à un externalId (facture + avoir + paiements) :
```sql
SELECT type, tranid, externalid, status, trandate FROM transaction
WHERE externalid LIKE 'FRIN-123%' ORDER BY trandate
```

Un customer existe-t-il ?
```sql
SELECT id, entityid, externalid, companyname, isinactive FROM customer WHERE externalid = '<maltId>'
```

Lignes d'une transaction (montants, comptes, taxes) :
```sql
SELECT tl.linesequencenumber, tl.memo, tl.foreignamount, a.acctnumber, a.acctname
FROM transactionline tl JOIN account a ON a.id = tl.expenseaccount
WHERE tl.transaction = <internalId> ORDER BY tl.linesequencenumber
```

## Frontière avec les autres sources

- **NetSuite dit ce qui EST dans l'ERP.** Il ne dit pas ce que le write-path accounting *pensait* écrire.
- Pour l'état côté Malt (write-model event-sourcé, read-model `ns_*`, `write_simulation`, `write_order_queue`) → skill `malt-prod-sql` + `malt-accounting-domain`.
- Un diagnostic de parité sérieux croise **les deux** : présence/valeur dans NetSuite (ici) et décision côté accounting (SQL prod). « Absent de NetSuite » ne dit pas *pourquoi* ; « APPLIED côté accounting » ne prouve pas la présence.
- Rappel : **présence dans NetSuite ≠ version courante** (BILL-3293).

## Maintenance

La signature OAuth 1.0a TBA est un **portage** de `erp/netsuite-suiteql-lib/.../NetsuiteSuiteQlAuth.kt`. Si le Kotlin change (encodage, repliement des query params — BILL-2747, header `Prefer: transient` — BILL-2827), répercuter dans le script. Tests : `~/.claude/scripts/tests/malt-netsuite-test.sh` (aucun réseau, aucune credential requise).
