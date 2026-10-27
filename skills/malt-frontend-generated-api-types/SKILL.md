---
name: malt-frontend-generated-api-types
description: Never hand-write a frontend API model or HTTP call when the backend has an OpenAPI contract. Use before writing or changing any type, composable, store or test that touches a backend payload in a Nuxt app or module (interfaces named *Response/*Request, status enums, useUniversalFetch to an internal API), and whenever a contract changes.
---

# Generated API types only

A frontend type that mirrors a backend payload must come from the OpenAPI generator, never from your reading of the backend code. A hand-written copy drifts silently: in `erp/accounting-front` the same entry shapes were copied four times, one copy dropped `parentCorrelationId` from the Payments tab and another narrowed `status` from 11 values to 5. TypeScript cannot catch this, because the hand-written type is what it checks against.

## Rules

1. **Contract first.** A field, endpoint or enum value the front needs and the contract lacks is a contract change: edit `<domain>-api-contract/contract/api-definition.yaml` (skill `malt-api-contracts`), then regenerate. Never add it on the front side "for now".
2. **Regenerate, don't type.** `pnpm --filter=<app> run generate:client-api`. Output (`app/openapi/` for most apps, see `package.json` `malt.openApiContract` and the `clean` script) is gitignored and never edited. Turbo regenerates it before `dev`, `build`, `typecheck` and `test:ci`.
3. **Calls go through the generated `*Api` classes**, instantiated once in `app/configuration/apiConfiguration.ts`. No `useUniversalFetch`/`useUniversalPost`/`$fetch` and no URL string to an internal API: the generated runtime already goes through `createUniversalFetchRaw` (CSRF, base URL).
4. **Types are imported**: `import type {InvoiceEntryResponse} from '@api'`. Use the generated name; do not re-alias it to keep an old local name.
5. **What stays hand-written**: view-models only (tab keys, props, search criteria, table rows, chart data) and front business helpers. Build them from generated types (`Pick`, `Omit`, `&`, `InvoiceEntryResponse['status']`) instead of re-listing fields.
6. **Enums**: use the generated union or `XxxEnum` const. Never narrow it (a `switch` then silently misses values) and never widen it with another enum's values.
7. **A field you cannot find in the generated model does not exist.** Do not invent it from a backend class, a fixture or a guess; if the backend sends it, the contract is wrong (rule 1).

## Traps of the generated client

- **Dates are `Date` objects.** Responses go through `XxxFromJSON`, so `format: date` and `format: date-time` fields arrive as `Date`, not ISO strings. A `format: date` value is UTC midnight: format it in UTC (or with the shared utilities, skill `malt-frontend-shared-utilities`) or the displayed day shifts. Date query parameters expect `Date`.
- **Errors** are the `FetchError`/`OFetchError` exported by `@api`; keep using `useErrorHandler` (skill `malt-frontend-api`).
- **Nuxt auto-imports composable exports**: a local exported type with the same name as an `@api` model shadows it without warning.

## Tests

Mock the instance, not the network (twin: `erp/accounting-front/app/composables/useNsReconciliation.spec.ts`):

```ts
const {listInvoices} = vi.hoisted(() => ({listInvoices: vi.fn()}));
vi.mock('../configuration/apiConfiguration', () => ({invoicesApi: {listInvoices}}));
```

Type fixtures with the generated model so a contract change breaks the test at compile time.

## Enforcement

`erp/accounting-front/eslint.config.mjs` (copied to `erp/accounting-mf-lot-entries/eslint.config.mjs`) fails lint on any hand-written HTTP call (`useUniversal*`, `fetch`, `useFetch`, `useLazyFetch`, `$fetch`/`ofetch`/`createUniversalFetchRaw`, `$fetch.raw`, `nuxtApp.$fetch`), any `/api/` string anywhere in a literal or template, a local `*Response`/`*Request`/`*Payload`/`*Dto` type, or an import from `~/openapi`/any `openapi/` path instead of `@api`. Copy that block when you bring another app under this rule. A lint error from it is never fixed with `eslint-disable`: fix the contract or use the generated client.

## Checklist

- [ ] Every payload type comes from `@api`
- [ ] No internal-API call outside the generated `*Api` instances
- [ ] Missing field or endpoint added to the contract, not to the front
- [ ] Date fields handled as `Date`, display unchanged
- [ ] Fixtures typed with generated models
