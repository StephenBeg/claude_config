---
name: malt-accounting-domain
description: Frontière et patterns du sous-système accounting/NetSuite de Malt. Contexte migration — état actuel TRANSITOIRE, accounting-* VA PASSER LIVE et REMPLACER netsuite-connector (ne jamais raisonner comme si rollout OFF / discard / legacy-autorité étaient définitifs) ; netsuite-connector = legacy LIVE (autorité) aujourd'hui, accounting-* = nouveau code en shadow (canary compare sans écrire + rollout OFF discard) ; objectif SMOOTH/ISO-BUG (écrire exactement comme le legacy, bugs inclus, corriger APRÈS cutover) ; découplage connector↔accounting absolu (couplage = erreur, dupliquer proprement). Deux modèles de données — write-model event-sourcé = seule source des décisions dans les handlers SyncCommandBus (jamais lire le read-model), read-model ns_* lu uniquement par l'API accounting-backend et reconstruit depuis les aggregates (sauf tables config_*). Couvre aussi write path (command-queue + FF), canary de parité, pièges récurrents (SuiteQL, jOOQ, defers, wiring Spring E2E), carte des modules. À charger avant toute exploration/dev/diagnostic touchant erp/accounting-* ou erp/netsuite-*.
---

# Malt — domaine accounting / NetSuite

Orientation dense pour ne jamais re-expliquer la frontière connector vs accounting. Le détail vit dans les mémoires liées `[[slug]]` — ce skill sert à s'orienter, pas à tout re-détailler.

## Contexte migration — À LIRE EN PREMIER

- **RÈGLE ABSOLUE — L'ÉTAT ACTUEL EST TRANSITOIRE. NE JAMAIS LE PRENDRE POUR ACQUIS.** `accounting-*` **VA PASSER LIVE** et **REMPLACER** `netsuite-connector`. C'est la finalité du chantier, pas une hypothèse lointaine. Les rollout flags OFF, le 100 % DISCARDED, le canary read-only, le legacy qui garde l'autorité : **tout cela va basculer**. Erreur récurrente et coûteuse de Claude (des dizaines d'allers-retours et de MR inutiles) : raisonner comme si la configuration observée aujourd'hui était définitive, et en conclure qu'un correctif côté accounting « ne servirait à rien puisque c'est le legacy qui écrit », ou qu'un endpoint/mécanisme accounting est inutile « puisque tout est discardé ». **Ce raisonnement est INTERDIT.**
  - Un correctif accounting se juge sur ce qu'il produira **quand accounting sera autorité**, jamais sur l'effet observable aujourd'hui.
  - « Aujourd'hui tout est discardé / le legacy a l'autorité / le flag est OFF » est un **constat d'état**, jamais un **argument de conception** et jamais une raison de renoncer.
  - Écrire dans NetSuite les éléments de la plateforme Malt est le **rôle** de netsuite-connector aujourd'hui et d'accounting demain. Une lacune fonctionnelle d'accounting est un vrai manque, même si elle est masquée par un discard.
  - Corollaire : constater que le legacy échoue lui aussi sur un cas ne dispense PAS de corriger accounting — ça ajoute un problème, ça n'en retire pas un.
- **`netsuite-connector` = legacy, LIVE.** Il détient aujourd'hui **l'autorité** sur les writes NetSuite : c'est lui qui écrit réellement en prod.
- **`accounting-*` = nouveau code, PAS ENCORE autorité — en « shadow ».** Opérationnellement, « shadow » = deux choses : (1) **canary simulation** — accounting recalcule son payload et le **compare** à celui du legacy (poussé en HTTP par le connector), **sans rien écrire dans NetSuite** ; (2) **rollout flags OFF** (`accounting-rollout-<type>`) → le write est **discardé** localement, le legacy garde l'autorité. Il n'y a **pas** de « shadow write » — soit compare, soit discard. (« shadow mode » n'est pas un terme de code actif ; en pratique = canary + rollout OFF.)
- **Objectif migration = SMOOTH / ISO-BUG.** À l'activation d'un rollout, accounting doit écrire **EXACTEMENT la même chose que le connector legacy** — mêmes valeurs, **bugs du legacy inclus**. Le connector est la **source de vérité** ([[feedback_connector_source_of_truth_no_invented_rounding]]). **Ne RIEN corriger pendant la migration** : inventer un arrondi/transform/« amélioration » absent du legacy = divergence = rejeté. **Les corrections viennent APRÈS le cutover**, jamais pendant. Toute divergence canary est un signal que accounting s'écarte du legacy, à réduire à zéro — pas une occasion de « faire mieux ».
- **Découplage connector ↔ accounting = ABSOLU (RÈGLE ABSOLUE).** accounting ne dépend JAMAIS de netsuite-connector (ni l'inverse au-delà du canari HTTP unidirectionnel connector→accounting). **Tout couplage in-process est une ERREUR** : ré-utiliser le SOAP/le code du connector dans accounting a été tenté et rejeté (BILL-2635). Le code nécessaire est **dupliqué et remis au propre en respectant l'archi d'accounting** — la duplication assumée passe **devant** la mutualisation ([[reference_sonar_dup_intentional_decoupling]] : « duplication over unwanted coupling », extraire un helper partagé serait un recouplage interdit).

## Frontière : `netsuite-connector` vs `accounting-*`

Malt parle à NetSuite via **deux sous-systèmes indépendants**. C'est LA distinction qui revient sans cesse.

### `netsuite-connector` (legacy, SOAP)
- Intégration **legacy**. Transport **SOAP**, types JAXB générés via **xjc** depuis les WSDL NetSuite (`com.netsuite.webservices.*`). Voué à disparaître.
- **Source de vérité de la VALEUR de chaque champ écrit dans NetSuite.** accounting doit reproduire EXACTEMENT ce que le connector produit — pas « mieux », pas « plus correct ». Jamais inventer un arrondi/trim/reformat que le connector ne fait pas ; un résidu signalé par un spike est laissé tel quel tant que non vérifié, pas deviné. Voir [[feedback_connector_source_of_truth_no_invented_rounding]].
- Le client SOAP complet a été extrait dans une **lib neutre** `erp/netsuite-soap-lib` (`:netsuite-soap-lib`, `com.malt.erp.netsuite.soap.client`) : `NetSuiteClient` (~48 méthodes), impl, result types. Neutre = seulement JAXB + `String` pour les value types, zéro dep `erp-model`/connector. Voir [[reference_netsuite_soap_lib_full_client]], [[reference_netsuite_soap_lib_build_coverage]].

### `accounting-*` (nouveau domaine, event-sourcé)
- Modules : `erp/accounting-domain`, `erp/accounting-infra`, `erp/accounting-backend` (app read), + `erp/netsuite-rest-lib`.
- **À l'origine REST-only** (BILL-2559) : le nouveau domaine NE dépend PAS de `netsuite-connector` ni de SOAP. Port métier dans `accounting-domain`, adapter dans `accounting-infra`, client bas niveau dans `netsuite-rest-lib` (REST pur, types neutres). On lit le SOAP legacy seulement pour *comprendre* le métier, jamais pour le réutiliser. Voir [[project_accounting_rest_only]].
- **Transport = SOAP-only aujourd'hui** (DRIFT corrigé BILL-3233, état vérifié sur master). Il y a EU un transport switch REST/SOAP via le FF `accounting-netsuite-rest-write` (BILL-2923/2928/2937), mais **ce FF n'existe plus** : le transport REST-write a été retiré, **SOAP est l'unique transport d'écriture** (`build.gradle.kts:50-55` « SOAP is the sole NetSuite write transport »). Le port neutre `NetsuiteRecordWritePort` subsiste mais son switch est devenu **SOAP-prod vs SOAP-sandbox** (qualifiers `SOAP_RECORD_WRITE_PORT` / `SANDBOX_RECORD_WRITE_PORT`, BILL-3096), plus REST↔SOAP. **Piège :** des noms résiduels `restPayload`/`restSide`/« REST side » désignent en réalité le payload/côté accounting, PAS un transport REST (renommage tracké BILL-3237). Ne PAS réintroduire de transport/fallback REST. Voir [[reference_accounting_neutral_write_port_transport_flag]] (contexte historique), [[reference_accounting_ff_transport_switch_e2e]].
- **Couplage unidirectionnel et HTTP-only.** Pour le canary, `netsuite-connector` calcule le `CanonicalNetsuiteRecord` legacy (n'écrit rien dans NetSuite) et le **pousse en HTTP vers accounting-backend** (connector = client, accounting = serveur). accounting n'importe JAMAIS le connector. Voir [[project_accounting_rest_only]], [[reference_accounting_canary_connector_producer]].
- Briques de parité neutres partagées dans `erp/netsuite-parity` (`:netsuite-parity`) : `CanonicalNetsuiteRecord`, `NetsuiteRecordComparator`, `DivergenceAllowList`, canonicalizers. Dep = seulement `:netsuite-rest-lib`. Le canonicalizer SOAP + capturing client restent dans le connector. Voir [[reference_netsuite_parity_module]].

## Deux modèles de données — RÈGLE ABSOLUE

accounting sépare strictement **write-model** et **read-model** :

- **Write-model = l'aggregate event-sourcé.** C'est **LA source de vérité** et la **SEULE source de données locale autorisée dans les handlers du `SyncCommandBus`**. Toute décision (gating, existence du parent, `ParentAppliedRule`, discard/defer) se prend en rechargeant l'aggregate depuis l'**event store**. **INTERDIT de lire le read-model** (`ns_*_entry`, `write_simulation`, `*ProjectionRepository`) dans un `SyncCommandHandler`. Un check qui manque → **faire évoluer le write-model** pour porter l'état via un event, jamais lire une projection. Voir [[feedback_no_readmodel_read_in_sync_handlers]].
- **Read-model = les tables `ns_*`** (`ns_*_entry`, `ns_write_try`, `processed_event`, `inbound_event_try`, `write_simulation`). **Lu UNIQUEMENT par les endpoints API de `accounting-backend`** (l'UI). **Construit exclusivement à partir des aggregates** : chaque projection est écrite dans la **même transaction SYNC** depuis les events appliqués (`OutboundWritePersister`), 100% reconstructible par replay ; aucune écriture de projection hors d'un `SyncCommandHandler`. L'aggregate est lu/créé même quand la commande finit `Rejected`/`Skip`. **Seule exception : les tables `config_*`** (matrice d'acceptation, statiques, non projetées) — lisibles ailleurs. Voir [[project_accounting_event_sourcing_purity]].
- Le read-model **reflète la réalité externe** (ce qui est réellement écrit dans NetSuite, valeur tronquée incluse), pas un idéal. Voir [[feedback_readmodel_mirrors_external_reality]].
- **TOUTE écriture passe par un command handler event-sourcé — RÈGLE ABSOLUE (sauf `config_*`).** Aucune mutation directe d'une table read-model (pas d'`UPDATE`/`upsert` déclenché hors flux d'events), même pour une annotation purement UI (ex : marquer une divergence `cleaned`). Le pattern par défaut de **toute** écriture : une **commande** sur le `SyncCommandBus` → un **handler** qui charge l'aggregat, applique un **event** (l'état vit dans l'aggregat), et le **projecteur** met à jour la projection read-model **dans la même transaction SYNC**. Ainsi tout champ read-model reste 100% reconstructible par replay. Seule exception : les tables `config_*` (statiques, non projetées). Un besoin de « juste flag une ligne » n'est PAS une dérogation → passer par event + projection.

## Autres invariants (ne jamais casser)

- **Jamais toucher `tech-starters/*` ni le moteur monorepo partagé** depuis un ticket de domaine (MR revertée). Garder démotions de log / comportement Rabbit app-local (logback accounting-backend ou le listener). Prudence sur les libs cross-domain (`netsuite-rest-lib`, consommée par connector ET accounting) → préférer le fix côté accounting. Voir [[feedback_never_touch_shared_tech_starters]], [[reference_expected_retry_signal_log_demotion]].
- **Un micro-frontend cross-domain n'appelle jamais le backend d'un autre domaine.** Propager par events, pas par couplage. Voir [[feedback_no_cross_domain_mf_backend_call]].
- **Aucun doc spec/plan committé dans le repo.** Voir [[feedback_no_spec_docs_in_repo]].
- (Connector = source de vérité des valeurs + découplage absolu : voir **Contexte migration** en tête.)

## Write path (push sortant vers NetSuite)

Queue via `tech-starters/command-queue` (JDBC persistant, polling). `AbstractOutboundWriteHandler` fire TOUJOURS `WriteNetsuiteRecord` → `QueueingAsyncCommandBus` (@Primary) enqueue TOUJOURS sur **`accounting-write-queue`** (pas de FF à l'enqueue). Consumer = `WriteNetsuiteRecordCommand` → `NetsuiteRecordPusher`. La décision push/discard est au **seam de consommation** :
- FF `accounting-auto-discard-netsuite-writes` ON && !forcePush → DISCARDED, pas d'appel REST.
- `type == null` OU FF de rollout du type OFF → DISCARDED.
- sinon → écriture via `NetsuiteRecordWritePort` (409 = idempotent SUCCEEDED).

Kill-switch = FF `accounting-netsuite-rest-push` : `PauseProbe` met en pause la **consommation** quand OFF (messages restent en queue, pas de DLQ) ; n'affecte pas l'enqueue. Les anciens `RoutingAsyncCommandBus` / `accounting-outbound-push-enabled` ont été **supprimés** (le routing-par-FF n'existe plus). Voir [[reference_accounting_write_queue]].

**Rollout gaté sur trois axes orthogonaux :** FF transport global (`accounting-netsuite-rest-write`), FFs de rollout par type (`accounting-rollout-<type>`, legacy vs accounting), et la **matrice d'acceptation** (`config_subsidiary_record_type` : subsidiary × recordType → enabled, défaut MALT_SA). Voir [[reference_accounting_rollout_flags]], [[reference_accounting_config_accept_matrix_tables]], [[reference_accounting_per_client_rollout_gate]].

## Canary de parité

`CanarySimulationComputer` async rebâtit le côté accounting et compare au canonical poussé par le connector. Sous SOAP → `SoapNetsuiteRecordCanonicalizer` (SOAP-vs-SOAP). Règles d'or : **jamais crash, jamais fallback REST** — types non supportés / throws inattendus → **SKIPPED** (runCatching). Divergences event-sourcées, exposées via l'API read (`write_simulation`, page front Divergence Scan). Voir [[reference_accounting_canary_soap_source]], [[reference_accounting_write_simulation_table]], [[reference_accounting_divergence_scan_front]].

**Pièges faux-positifs récurrents :** un seul `throw` de mapper vide tout le record REST → flood de faux `MISSING_ON_REST` ; le classifier `lenient()` absorbe un miss isolé, PAS un référentiel entier vide. Un faux SKIPPED = throw canonicalize avalé. blank↔null doivent être équivalents (`"" == null`). Voir [[reference_accounting_canary_lenient_referential]], [[reference_accounting_canary_skipped_swallowed_throw]], [[reference_parity_blank_null_equivalence]], [[reference_accounting_canary_registry_refactor]].

## Pièges récurrents (groupés)

**NetSuite REST / SuiteQL**
- SuiteQL **lowercase toutes les clés de colonnes** quelle que soit la casse du SELECT → `row["acctnumber"]`. Voir [[reference_suiteql_lowercases_column_keys]].
- Tout appel SuiteQL DOIT envoyer le header `Prefer: transient` (valeur exacte, pas `return=transient`) sinon 400. Voir [[reference_netsuite_suiteql_prefer_transient]].
- Reads REST retentent le `401 INVALID_LOGIN_ATTEMPT` transitoire (3 essais, OAuth1 header frais). Voir [[reference_netsuite_rest_read_401_retry]].
- REST est **SuiteTax-only** (sublist taxDetails), pas de `taxCode` par ligne ; currency read-only (SET via `currency{id}`). Voir [[reference_netsuite_rest_suitetax_only_iso_soap]], [[reference_netsuite_rest_currency_readonly]], [[reference_netsuite_rest_record_vs_suiteql]].

**jOOQ / DB**
- `.onDuplicateKeyUpdate()` sans conflict target sur une table à 2 clés uniques → MERGE `ON ((pk) OR (write_id))` → **deadlock**. Utiliser `.onConflict(<pk>).doUpdate()`. Voir [[reference_jooq_onduplicate_merge_deadlock]].
- Deadlocks DB transitoires (`TransientDataAccessException`) → Deferred retriable. Voir [[reference_accounting_transient_db_retriable]].
- Codegen jOOQ ne génère que les tables du regex `database.includes` dans `accounting-infra/build.gradle.kts` — nouvelle table silencieusement skippée ; ajouter `|<table>` puis `jooqCodegenMain --rerun-tasks`. Codegen lit la devbox DB live. Voir [[reference_accounting_jooq_includes_whitelist]], [[reference_jooq_codegen_devbox]].
- `TruncatingVarcharBinding` tronque les VARCHAR générés ; le read-model reflète la valeur écrite (possiblement tronquée). Voir [[reference_accounting_truncating_varchar_binding]], [[feedback_readmodel_mirrors_external_reality]].

**Deferral / retry**
- Defers coincés bornés → `DEFERRAL_EXHAUSTED` (MAX=10). Source native manquante (`findById` null) → defer, boucle infinie possible sans guard. Voir [[reference_accounting_deferral_exhausted_bound]], [[reference_accounting_business_referral_no_confirmed_transaction]], [[project_accounting_missing_writes_native_source]].

**Wiring Spring (E2E)**
- Contextes `@ContextConfiguration`/`@Import` curatés à la main (`AccountingE2ETestContext`, `AccountingWriteContextTest`) NE scannent PAS → chaque nouveau `@Component` du path write/read doit être ajouté à la main sinon `UnsatisfiedDependency` → E2E rouges. La prod boote (tous `@Component`). `MockFeatureFlipping` = singleton partagé → reset des flags en `@BeforeEach`. Voir [[reference_accounting_e2e_soap_writer_bean_manual]], [[reference_constructor_widening_all_sites_and_contexts]].
- Nouveau endpoint → 404 `NoResourceFoundException` alors que `/hello` marche = backend crashé au boot (pas Traefik) ; check `accounting-backend-deploy-*`. Un `@WebMvcTest` mockant le repo ne l'attrape pas. Voir [[reference_accounting_backend_wiring]].

## Carte des modules

| Concern | Localisation |
|---|---|
| Intégration SOAP legacy | `erp/netsuite-connector` (`com.malt.erp.netsuite.connector`) |
| Lib client SOAP neutre | `erp/netsuite-soap-lib` (`:netsuite-soap-lib`) |
| Lib transport REST | `erp/netsuite-rest-lib` (`NetsuiteRestRecordLister/Reader/Writer`) |
| Briques de parité neutres | `erp/netsuite-parity` (`:netsuite-parity`) |
| Domaine accounting (write-model, ports) | `erp/accounting-domain` |
| Infra accounting (adapters, repos jOOQ, canonicalizers, resolvers) | `erp/accounting-infra` |
| App REST read accounting | `erp/accounting-backend` (scan complet, `@JooqRepository` injectés dans `AccountingApi`) |
| jOOQ généré | `erp/accounting-infra/src/generated/jooq/` (committé) |
| Migrations Liquibase | `hoptools/upgrader/.../changes/*.sql` (pièges `;`/COMMENT — [[reference_liquibase_hoptools_rules]]) |
| Feature flags backend (FF4j) | `hoptools/upgrader/.../ff4j/current-flags/ff4j-squad-billing.xml` |

**FF4j = GLOBAL** (collection Mongo `ff4j` partagée) — le fichier `ff4j-squad-*.xml` sert à l'ownership/organisation, PAS à scoper par service. Un flag ON en prod est lu ON par tout service qui l'évalue ; le `enable="false"` du XML n'est qu'une graine de création, la valeur prod live peut être ON. Flag absent du XML → `isEnabled` renvoie false silencieusement. Un flag front nécessite quand même la registration FF4j (nuxt.config seul insuffisant). Voir [[reference_ff4j_backend_flags]], [[feedback_frontend_flag_needs_ff4j_registration]].
