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
                          # and replace the two MongoDB passwords (see .env.example)
docker compose up --build -d
docker compose exec api /app/seed    # indexes + demo data
docker compose exec file /app/seed   # files collection index
```

* API: http://localhost:3000 · File service: http://localhost:8080 (playground page at `/`)
* Seeded accounts: `admin@pos.local / admin123` (Admin) and `cashier@pos.local / cashier123` (Cashier).
* `JWT_SECRET` has no default — compose refuses to start the API without it,
  so a placeholder secret can never sign real tokens. The four MongoDB
  credentials are required for the same reason: a stack that interpolates
  without them cannot be running credential-free.
* MongoDB runs with `--auth`. On a brand-new `mongo-data` volume the root
  user comes from the `MONGO_ROOT_*` variables and `docker/mongo-init.sh`
  creates the least-privilege `MONGO_APP_*` user; `api`, `file` and the
  backup service all connect as that app user, never root. An
  already-populated volume never runs the init: see the runbook under
  [Deployments](#deployments).
* A `backup` service dumps the database and archives the uploads volume
  into `BACKUP_DIR` (default `./backups`) every `BACKUP_INTERVAL_SECONDS`
  and prunes beyond `BACKUP_KEEP` copies. See
  [Backups and restore](#backups-and-restore).
* Both services run as uid 65534 (`nobody`), so a checkout upgrading from
  the old root-owned images must hand the existing uploads volume over
  once, and only once (`docker compose down` first):

  ```bash
  docker run --rm -v pos_file-uploads:/d alpine chown -R 65534:65534 /d
  ```

* MongoDB is published on `127.0.0.1` only; the services reach it on the
  compose network. `api` and `file` wait on the mongo healthcheck before start,
  and `api` additionally waits for the file service to report healthy.
* `docker compose ps` shows `(healthy)` once `GET /readyz` answers in both
  services; `GET /healthz` stays 200 while a dependency is down, so an outage
  never looks like a crash. See [Deployments](#deployments).

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
* `e2e.yml` — builds the real images, boots compose, seeds, waits on `/readyz`
  of both services, then runs `test/integration` and `scripts/smoke.dart`
  against the live stack.
* `release.yml` — publishes both images to GHCR on a merge to `main`, and adds
  version tags plus a GitHub Release when you push a `vX.Y.Z` tag. See
  [Releases](#releases).
* `deploy.yml` — restarts the production stack on one pinned image tag, with
  automatic rollback. Called by `release.yml` and runnable by hand. The bundle
  it copies to the host is everything the compose files bind-mount: the two
  compose files, `scripts/deploy.sh`, `scripts/backup.sh`,
  `scripts/restore.sh` and `docker/mongo-init.sh`. See
  [Deployments](#deployments).
* `dependabot.yml` — weekly grouped minor and patch bumps for both packages,
  the base images and the actions. Major bumps always arrive as single PRs to
  be read on their own.
* `api/Dockerfile` runs `dart test test/unit` before compiling, so a failing
  suite never produces an image.
* `.dockerignore` in each service keeps `.env` and local build output out of
  the image.

Turn on the local hooks once per clone; they run the same formatter check CI
runs, in the pinned image when Docker is available, and reject subjects that
are not Conventional Commits:

```bash
git config core.hooksPath .githooks
```

`main` is protected. A change reaches it through a pull request with the four
job checks green — `API`, `File service`, `Check workflow syntax`, `Live
stack` — and cannot be force-pushed over or merged while they are failing.
Approvals are not required, because this is a one-person repository, and the
owner can still override the checks in an emergency; treat an override as an
incident worth following up, not a shortcut.

## Releases

One version covers the whole repository: `api/` and `file/` are tagged and
published together. Before a `vX.Y.Z` tag is allowed to publish, `release.yml`
checks that the tag matches `version:` in **both** `pubspec.yaml` files and
that `CHANGELOG.md` has a section for it, so a release cannot ship with stale
metadata. Pre-release suffixes such as `v1.1.0-rc1` are rejected on purpose;
the flow only knows final versions.

To cut a release:

1. Set `version:` in `api/pubspec.yaml` and `file/pubspec.yaml`.
2. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new
   `## [x.y.z] - YYYY-MM-DD` heading, and open a fresh `## [Unreleased]`.
3. Commit, tag, then push both:

   ```bash
   git tag -a v1.0.1 -m "OmniPOS 1.0.1"
   git push origin main --follow-tags
   ```

| Trigger | Image tags published | GitHub Release |
| ------- | -------------------- | -------------- |
| merge to `main` | `pos-api:main`, `pos-api:latest`, `pos-api:sha-<short>` (same four for `pos-file`) | no |
| tag `v1.2.3` | `pos-api:1.2.3` and `pos-api:1.2` on top of the branch tags | yes, notes taken from this changelog |

Deploy a published image without building it:

```bash
docker pull ghcr.io/casiendetra/pos-api:1.2.3
docker pull ghcr.io/casiendetra/pos-file:1.2.3
```

The workflow creates both packages the first time it runs, and a package
created from a private repository starts out private, so anonymous pulls fail
until you flip each one once: GitHub → your profile → Packages → *pos-api* →
Package settings → Change visibility → Public. Later pushes keep that setting.
Until then, pull with an authenticated `docker login ghcr.io`.

## Deployments

Production runs the same compose stack, from published images rather than a
local build. `docker-compose.yml` remains the development definition and
`docker-compose.deploy.yml` layers on top of it: it pins both services to
`ghcr.io/casiendetra/pos-*:${IMAGE_TAG}`, caps and rotates container logs,
gives each service 30 seconds to finish the request it is serving, hardens
every container (dropped capabilities, no privilege escalation, read-only
root filesystems — the base file stays comfortable for development) and
puts a memory, CPU and process-id ceiling on each service so one runaway
query cannot take the host down; the header comment in that file records
how the numbers were sized and what to revisit on a different machine.
Nothing is rebuilt on the host, so what runs is byte for byte what CI
published.

### One-time host setup

1. Docker Engine with the compose plugin, and a directory the deploy user owns:
   `sudo mkdir -p /srv/pos && sudo chown <deploy-user> /srv/pos`.
2. A way for that user to pull the images. If both GHCR packages are public
   (see Releases above) an anonymous pull works and there is nothing to do.
   While they are private, sign the user in once with a fine-grained token that
   has `read:packages` on this repository:
   `docker login ghcr.io -U <github-handle> --password-stdin`.
3. Secrets on the host, out of git: `/srv/pos/.env` with a real `JWT_SECRET`
   (`openssl rand -base64 48`), the four MongoDB credentials from
   `.env.example` (keep the passwords to letters and digits — see the
   comment in that file), plus the bind address that host actually needs —
   `API_BIND_ADDRESS=127.0.0.1` and `FILE_BIND_ADDRESS=127.0.0.1` when a TLS
   proxy terminates on the same machine, or that machine's LAN address when the
   terminals connect directly. The services need no other configuration.
4. The repository settings `deploy.yml` reads:

   ```bash
   gh variable set DEPLOY_ENABLED --body true
   gh variable set DEPLOY_DIR --body /srv/pos
   gh secret set DEPLOY_HOST < host.txt
   gh secret set DEPLOY_USER < user.txt
   gh secret set DEPLOY_SSH_KEY < ./deploy_key        # private half
   gh secret set DEPLOY_KNOWN_HOSTS < known_hosts.txt # public half's host key
   ```

   Generate the key pair on your machine with `ssh-keygen -t ed25519 -f
   deploy_key -C pos-deploy`, put the public half in the deploy user's
   `authorized_keys`, and never use a key with a passphrase — the workflow has
   no terminal to type it into. `DEPLOY_KNOWN_HOSTS` is trusted verbatim and
   the workflow never accepts a host key on first use, so build it from the
   host's own console and check the fingerprint there rather than piping
   `ssh-keyscan` blindly.

### Deploy

Pushing a `vX.Y.Z` tag publishes the images, then — only once `DEPLOY_ENABLED`
is `true` — the `Deploy` job of `release.yml` calls `deploy.yml`, which resolves
the tag to its `sha-<commit>` tag, copies the deploy bundle — the two compose
files, `scripts/deploy.sh`, `scripts/backup.sh`, `scripts/restore.sh` and
`docker/mongo-init.sh` — into `DEPLOY_DIR`, and runs the script there. The script
fixes up the uploads volume ownership once, pulls, restarts with
`up -d --no-build`, and polls `/readyz` inside both containers until they
answer. If the new release never becomes ready, the tag recorded in
`.release.env` is started again and the job fails loudly.

### Rollback and recovery

Rollback is a redeploy of the tag that was running before. Nothing is rebuilt:

```bash
gh workflow run deploy.yml -f version=v1.0.1                  # from CI
cd /srv/pos && IMAGE_TAG=sha-<previous> bash deploy.sh        # or on the host
cat /srv/pos/.release.env                                     # what runs now
```

`IMAGE_TAG=1.0.1` works too, but a version tag can be re-pointed while a
`sha-<commit>` tag cannot, so pin the commit when you want certainty.

Verify a running deployment with the two probes: `GET /healthz` answers while
the process serves, and `GET /readyz` is what a till actually cares about — it
pings MongoDB, and for the file service proves the upload directory accepts a
write, answering 503 otherwise. Both are unauthenticated, and both are what the
compose healthcheck runs every 10 seconds using `/app/probe`, the binary baked
into each image. That is why `docker compose ps` reports `(healthy)` or
`(unhealthy)` on a host with no curl installed.

Backups are automated: see [Backups and restore](#backups-and-restore) below.

### Enabling auth on an existing host

MongoDB authentication is defined in `docker-compose.yml`, but enabling
`--auth` never creates users retroactively — `MONGO_INITDB_ROOT_*` and
`docker/mongo-init.sh` only run while `/data/db` is empty. A host that
already has a populated `mongo-data` volume therefore needs its users
created by hand **before** the first authenticated deploy, or the stack
comes up with an unreachable database:

1. Put the four `MONGO_*` credentials in `/srv/pos/.env` (same names as
   `.env.example`; passwords letters and digits only).
2. While the stack is still running the **old** definition (no auth), exec
   into mongo and create both users. The guards make this idempotent:

   ```bash
   docker compose exec -T mongo mongosh --quiet <<EOF
   use admin
   if (!db.getUser("<MONGO_ROOT_USERNAME from .env>"))
     db.createUser({ user: "<MONGO_ROOT_USERNAME>",
                     pwd:  "<MONGO_ROOT_PASSWORD>",
                     roles: [{ role: "root", db: "admin" }] })
   use pos
   if (!db.getUser("<MONGO_APP_USER from .env>"))
     db.createUser({ user: "<MONGO_APP_USER>",
                     pwd:  "<MONGO_APP_PASSWORD>",
                     roles: [{ role: "readWrite", db: "pos" }] })
   EOF
   ```

3. Deploy the new compose files (normal `deploy.yml` run, or
   `IMAGE_TAG=<current> bash deploy.sh` on the host). `mongo` reappears
   with `--auth`, the healthcheck authenticates as root, and api/file/backup
   connect as the app user.
4. Confirm the gate holds:

   ```bash
   docker compose exec -T mongo mongosh --quiet "mongodb://127.0.0.1:27017/pos" \
     --eval "db.users.countDocuments()"     # must fail: requires authentication
   ```

Recovery path if step 2 was skipped: the deploy comes up with `mongo`
unhealthy (the healthcheck authenticates, and there is no user to
authenticate as). MongoDB's localhost exception is still open — the very
first user on an auth-enabled instance with no users can be created from
inside the container — so run step 2 again with `mongosh --quiet
mongodb://127.0.0.1:27017/admin` (connecting via localhost, no
credentials) and restart the services.

The same runbook applies to a development machine that kept an old
`mongo-data` volume. Deleting the volume and re-seeding is the
alternative when the data does not matter:

```bash
docker compose down && docker volume rm pos_mongo-data && docker compose up -d --build
docker compose exec api /app/seed && docker compose exec file /app/seed
```

### Backups and restore

The `backup` service in `docker-compose.yml` is the answer to the stack's
highest-risk gap: until now `mongo-data` and `file-uploads` had no backup at
all. Why a compose service rather than a host cron: the deploy to a host is
just the bundle `deploy.yml` copies, so a cron line installed by hand would
be setup magic that no pipeline owns and that a rebuilt machine silently
loses. The service travels in the bundle (`scripts/backup.sh`), starts with
the stack, and its container is the plain `mongo:7` image — the same server
version, so `mongodump` can never be older than the database it reads.

Each round (immediately at start, then every `BACKUP_INTERVAL_SECONDS`,
default 6 h) writes to `BACKUP_DIR` on the host disk — deliberately outside
every docker volume, because the disaster being guarded against is losing
the volumes themselves:

* `pos-<UTC stamp>.dump.gz` — `mongodump --archive --gzip` of the `pos`
  database, taken as the app user (its `readWrite` is all `mongodump` needs
  on one database, so no root password lives in this container).
* `uploads-<UTC stamp>.tgz` — the whole `file-uploads` volume, read through
  a read-only mount.
* `.last-success` — epoch of the last clean round; the service's healthcheck
  goes red when that file ages past four intervals, so a loop that quietly
  stopped cannot hide behind a running process.

Both land as `*.part` and are renamed only after success: a round that fails
publishes nothing, leaves `.last-success` where it was and prunes nothing, so
retention can never thin the good archives on the strength of a bad round.
The newest `BACKUP_KEEP` of each kind survive (default 14 — about three and a
half days at six-hourly). Off-site copies are not in scope: a host fire is
still an untested single copy; mirror `BACKUP_DIR` somewhere else if the shop
cannot carry that risk.

The drill is what makes any of this real — an untested backup is not a
backup. `scripts/restore.sh drill` starts a throwaway `mongo:7` container,
restores the newest dump (or one you name) into it, and prints
per-collection document counts. It touches nothing running:

```bash
cd /srv/pos && bash scripts/restore.sh drill
bash scripts/restore.sh drill backups/pos-2026-10-17T060000Z.dump.gz
```

A successful drill still needs human eyes: *do the counts look like this
shop?* Restoring an empty-but-valid database is a failed backup, and only a
person knows the difference. Recommended rhythm: drill after any change to
the backup service, and at least once a quarter.

A real recovery — replacing live data — is the same script's second mode,
and it is destructive by design (it asks for the word `yes`; `--yes` skips
that for runbook rehearsing on a scratch host):

```bash
bash scripts/restore.sh restore backups/pos-<stamp>.dump.gz [backups/uploads-<stamp>.tgz]
```

It `--drop`-restores the `pos` namespace through the running mongo
container using the root credentials already in that container's
environment. It stops `api` and `file` for the duration — a restore racing
live sales can silently discard them — and drops the `pos` database before
replaying, because `--drop` clears only the collections the archive contains
and anything created since the backup would otherwise survive. When an
uploads archive is given it wipes the volume into the archive's contents and
re-hands ownership to uid 65534. It starts both services again and finishes
by waiting for both `/readyz` probes. The application user survives all of
this: its record lives in `admin.system.users`, not in the dropped database.

The database name and `BACKUP_DIR` are read from `.env` the way compose reads
them, so a no-argument drill looks in the directory the backup service really
writes to.

## Run locally (dev)

Requires the pinned Dart SDK (3.13.4) and `dart_frog_cli`
(`dart pub global activate dart_frog_cli 1.2.14`).

```bash
cd POS/file && cp .env.example .env && dart pub get && dart_frog dev --port 8080
cd POS/api  && cp .env.example .env && dart pub get && dart run scripts/seed.dart && dart_frog dev --port 3000
```

(`docker compose up mongo` starts the database, but with authentication: a
plain `MONGODB_URI=mongodb://localhost:27017/pos` is rejected — use the
application user from `.env`, e.g.
`mongodb://<MONGO_APP_USER>:<MONGO_APP_PASSWORD>@localhost:27017/pos?authSource=pos`,
or leave `MONGODB_URI` empty and set the discrete `MONGO_*` parts the
services' `.env.example` files describe.)

## Auth

`POST /api/v1/account/auth/login` with `{"username": "admin@pos.local", "password": "admin123"}`
(`username` may also be the phone) returns a 24 h JWT. Send it as
`Authorization: Bearer <token>`. Roles baked into the token: `Admin = 1`,
`Cashier = 2`; `POST /api/v1/account/auth/switch {"role_id": 2}` re-issues the
token with a different default role. Route groups `/api/v1/admin/*` and
`/api/v1/cashier/*` are guarded by role in the global middleware.

## API surface

Interactive docs: **http://localhost:3000/swagger** (Swagger UI), raw OpenAPI 3.0.3 JSON at **http://localhost:3000/openapi**. Both are public (no token). In the UI click *Authorize* and paste the `token` returned by `/api/v1/account/auth/login`.

```
GET    /                                    health
POST   /api/v1/account/auth/login           login (public)
POST   /api/v1/account/auth/switch          switch default role
GET    /api/v1/account/profile              own profile
PUT    /api/v1/account/profile/update       update own profile
PUT    /api/v1/account/profile/update-password
GET    /api/v1/account/profile/logs         own login history

GET    /api/v1/admin/dashboard              today/week stats + top products
GET    /api/v1/admin/types                  list (pagination)      POST create
GET/PUT/DELETE /api/v1/admin/types/:id
GET    /api/v1/admin/products               list: page, limit, key, type, creator, startDate, endDate, sort_by, order
POST   /api/v1/admin/products               create (image = base64 data URL → file service)
GET    /api/v1/admin/products/setup-data    type/user dropdown refs
GET/PUT/DELETE /api/v1/admin/products/:id
GET    /api/v1/admin/sales                  all orders (same filters + user, platform)
GET    /api/v1/admin/sales/setup-data       cashier dropdown refs
GET/DELETE /api/v1/admin/sales/:id
GET    /api/v1/admin/users                  list                    POST create
GET/PUT/DELETE /api/v1/admin/users/:id
PUT    /api/v1/admin/users/:id/status       activate/deactivate
PUT    /api/v1/admin/users/:id/password     reset password

GET    /api/v1/cashier/ordering/products    types with nested active products
POST   /api/v1/cashier/ordering/order       checkout {"cart": "{\"<productId>\": qty}", "platform": "Web"}
GET    /api/v1/cashier/sales                own sales only
GET/DELETE /api/v1/cashier/sales/:id

GET    /api/v1/reports/invoice/:id          invoice PDF (admin: any order, cashier: own only)

GET    /api/v1/testing/basic                public echo endpoint (no auth)
POST   /api/v1/testing/upload/file          public base64 upload proxy to file service
```

The prefix is declared once, in `api/lib/src/config/api_routes.dart`
(`apiVersionSegment`), and the auth guard keys off it rather than a literal
`/api/admin`, so a version bump cannot leave a guard that matches nothing.
`api/test/unit/api_routes_test.dart` fails if the route tree, that prefix and
the OpenAPI document disagree. The file service is deliberately not
versioned: `/api/file/*` is an internal compose-network address, not part of
the public API contract.

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
