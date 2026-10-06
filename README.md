# POS — Dart Frog + MongoDB backend

Two Dart Frog services replicating the architecture of `first/api-v4`
(NestJS POS API) and `first/file-v3` (Express file service):

| Service | Folder | Default port | Purpose |
| ------- | ------ | ------------ | ------- |
| POS API | `api/` | 3000 | REST endpoints: auth, products, types, sales/orders, users, dashboard |
| POS File | `file/` | 8080 | Upload (multipart + base64) and serve files from `public/uploads/` |
| MongoDB | — | 27017 | Single database `pos` shared by both services |

## Response envelope

Every endpoint answers with the same JSON shape:

```json
{ "success": true,  "status_code": 200, "data": { ... }, "pagination": { ... } }
{ "success": false, "status_code": 422, "error": "...", "errors": [ { "type": "field", "message": "..." } ], "timestamp": "19-09-2026 01:02:03 PM", "path": "/api/..." }
```

If MongoDB is unreachable the global error boundary returns
`{ "success": false, "error": "Database connection failed" }` (HTTP 503).

## Run with Docker (recommended)

```bash
cd POS
cp .env.example .env      # then set JWT_SECRET: openssl rand -base64 48
docker compose up --build -d
docker compose exec api /app/seed    # indexes + demo data
docker compose exec file /app/seed   # files collection index
```

* API: http://localhost:3000 · File service: http://localhost:8080 (playground page at `/`)
* Seeded accounts: `admin@pos.local / admin123` (Admin) and `cashier@pos.local / cashier123` (Cashier).
* `JWT_SECRET` has no default — compose refuses to start the API without it,
  so a placeholder secret can never sign real tokens.
* MongoDB is published on `127.0.0.1` only; the services reach it on the
  compose network. `api` and `file` wait on the mongo healthcheck before start.

## Toolchain and CI

Base images and CI share one pinned Dart toolchain (`dart:3.13.4`) so
formatting, analysis and compilation behave identically everywhere. Bump the
`dart:3.13.4` tag in `api/Dockerfile`, `file/Dockerfile` and both jobs of
`.github/workflows/ci.yml` together, then re-run `dart format` across both
packages — the CI gate is strict.

Run `dart pub get` in the package before formatting it. The formatter resolves
each file's language version through the package configuration; without it a
few long string literals wrap differently and the gate disagrees with your
commit, which is why CI formats after installing dependencies.

Both `pubspec.lock` files are committed, and CI, the E2E job and both
Dockerfiles install with `dart pub get --enforce-lockfile`. That command fails
instead of silently re-resolving, so no build can use dependency versions
nobody reviewed. To change them, run `dart pub upgrade` in the package and
commit the new lock in the same change.

* `ci.yml` — per service: `dart pub get --enforce-lockfile`,
  `dart format --set-exit-if-changed`, `dart analyze`, `dart test`
  (integration tests self-skip without a server).
* `e2e.yml` — builds the real images, boots compose, seeds, then runs
  `test/integration` and `scripts/smoke.dart` against the live stack.
* `api/Dockerfile` runs `dart test test/unit` before compiling, so a failing
  suite never produces an image.
* `.dockerignore` in each service keeps `.env` and local build output out of
  the image.

## Run locally (dev)

Requires the pinned Dart SDK (3.13.4) and `dart_frog_cli`
(`dart pub global activate dart_frog_cli 1.2.14`).

```bash
cd POS/file && cp .env.example .env && dart pub get && dart_frog dev --port 8080
cd POS/api  && cp .env.example .env && dart pub get && dart run scripts/seed.dart && dart_frog dev --port 3000
```

(`MONGODB_URI` defaults to `mongodb://localhost:27017/pos`; a `docker compose up mongo` is enough to start the database.)

## Auth

`POST /api/account/auth/login` with `{"username": "admin@pos.local", "password": "admin123"}`
(`username` may also be the phone) returns a 24 h JWT. Send it as
`Authorization: Bearer <token>`. Roles baked into the token: `Admin = 1`,
`Cashier = 2`; `POST /api/account/auth/switch {"role_id": 2}` re-issues the
token with a different default role. Route groups `/api/admin/*` and
`/api/cashier/*` are guarded by role in the global middleware.

## API surface

Interactive docs: **http://localhost:3000/swagger** (Swagger UI), raw OpenAPI 3.0.3 JSON at **http://localhost:3000/openapi**. Both are public (no token). In the UI click *Authorize* and paste the `token` returned by `/api/account/auth/login`.

```
GET    /                                health
POST   /api/account/auth/login          login (public)
POST   /api/account/auth/switch         switch default role
GET    /api/account/profile             own profile
PUT    /api/account/profile/update      update own profile
PUT    /api/account/profile/update-password
GET    /api/account/profile/logs        own login history

GET    /api/admin/dashboard             today/week stats + top products
GET    /api/admin/types                 list (pagination)      POST create
GET/PUT/DELETE /api/admin/types/:id
GET    /api/admin/products              list: page, limit, key, type, creator, startDate, endDate, sort_by, order
POST   /api/admin/products              create (image = base64 data URL → file service)
GET    /api/admin/products/setup-data   type/user dropdown refs
GET/PUT/DELETE /api/admin/products/:id
GET    /api/admin/sales                 all orders (same filters + user, platform)
GET    /api/admin/sales/setup-data      cashier dropdown refs
GET/DELETE /api/admin/sales/:id
GET    /api/admin/users                 list                    POST create
GET/PUT/DELETE /api/admin/users/:id
PUT    /api/admin/users/:id/status      activate/deactivate
PUT    /api/admin/users/:id/password    reset password

GET    /api/cashier/ordering/products   types with nested active products
POST   /api/cashier/ordering/order      checkout {"cart": "{\"<productId>\": qty}", "platform": "Web"}
GET    /api/cashier/sales               own sales only
GET/DELETE /api/cashier/sales/:id

GET    /api/reports/invoice/:id        invoice PDF (admin: any order, cashier: own only)

GET    /api/testing/basic               public echo endpoint (no auth)
POST   /api/testing/upload/file         public base64 upload proxy to file service
```

File service endpoints (no auth, like v3):

```
POST /api/file/upload-single    multipart field "file" + "folder"
POST /api/file/upload-base64    {"folder": "...", "image": "data:image/png;base64,..."}
GET  /api/file/<filename>       stream file (?download=true → attachment)
```

## Testing

Three layers, all runnable from `api/` with the stack up (`docker compose up -d`):

```bash
dart test                 # 59 tests: unit + authz integration vs live server
dart run scripts/smoke.dart   # 12-step E2E smoke, exits 1 on failure
```

* `test/unit/` — pure logic: JWT round-trip and tampering, bcrypt, validators,
  pagination, order/price snapshot models, invoice PDF rendering.
* `test/integration/authz_test.dart` — HTTP against a running instance
  (`API_BASE_URL` overrides, default `http://localhost:3000`); auto-skips when
  the server is unreachable. Covers 401/403 rules, checkout validation, the
  order lifecycle and sequential receipt numbers. Test data is prefixed
  `zz-test-` and deleted again in teardown.
* `scripts/smoke.dart` — one-shot demo flow with a PASS/FAIL line per step.

Postman: import `postman/OmniPOS.postman_collection.json`, run folders top to
bottom. Tokens are captured automatically into collection variables; the
Cleanup folder (30–33) removes everything the flow created.

## Design notes (vs. the NestJS/Sequelize reference)

* Users embed `roles: [{id, name, is_default}]` instead of a pivot table.
* Orders embed `items: [{product_id, name, unit_price, qty}]` — prices are
  snapshotted at sale time and checkout is a single-document write.
* `receipt_number` is a sequential 7-digit number from an atomic `counters`
  document (fixes the reference project's random generator race).
* Product `image` stores only the relative uri `api/file/<uuid>`; the bytes
  live on the file service disk, metadata in the `files` collection.
