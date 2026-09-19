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
docker compose up --build -d
docker compose exec api /app/seed    # indexes + demo data
docker compose exec file /app/seed   # files collection index
```

* API: http://localhost:3000 · File service: http://localhost:8080 (playground page at `/`)
* Seeded accounts: `admin@pos.local / admin123` (Admin) and `cashier@pos.local / cashier123` (Cashier).

## Run locally (dev)

Requires Dart SDK and `dart_frog_cli` (`dart pub global activate dart_frog_cli`).

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

GET    /api/testing/basic               public echo endpoint (no auth)
POST   /api/testing/upload/file         public base64 upload proxy to file service
```

File service endpoints (no auth, like v3):

```
POST /api/file/upload-single    multipart field "file" + "folder"
POST /api/file/upload-base64    {"folder": "...", "image": "data:image/png;base64,..."}
GET  /api/file/<filename>       stream file (?download=true → attachment)
```

## Design notes (vs. the NestJS/Sequelize reference)

* Users embed `roles: [{id, name, is_default}]` instead of a pivot table.
* Orders embed `items: [{product_id, name, unit_price, qty}]` — prices are
  snapshotted at sale time and checkout is a single-document write.
* `receipt_number` is a sequential 7-digit number from an atomic `counters`
  document (fixes the reference project's random generator race).
* Product `image` stores only the relative uri `api/file/<uuid>`; the bytes
  live on the file service disk, metadata in the `files` collection.
