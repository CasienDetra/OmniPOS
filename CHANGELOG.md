# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions apply to the repository as a whole: `api/` and `file/` are released
under one tag, and the release workflow refuses to publish when a tag
disagrees with either service's `pubspec.yaml` or with an entry here.

## [Unreleased]

### Added

- Liveness and readiness probes on both services: `GET /healthz` answers while
  the process serves, `GET /readyz` checks MongoDB — and for the file service,
  that the upload directory actually accepts a write — and answers 503
  otherwise. Both are unauthenticated and documented in the OpenAPI file.
- `/app/probe`, a second compiled binary in every image, so the compose
  healthcheck can run the readiness probe on a host with neither a shell nor
  curl; the API image is `FROM scratch`.
- `deploy.yml`, `docker-compose.deploy.yml` and `scripts/deploy.sh`: pushing a
  release tag now restarts the production stack on that commit's pinned image,
  waits for readiness, and rolls back to the previously recorded tag when the
  new one never becomes ready.
- `API_BIND_ADDRESS` and `FILE_BIND_ADDRESS`, so a deployment can publish on
  loopback or on a single LAN address instead of every interface.
- `.github/dependabot.yml` covering both packages, the pinned base images and
  the GitHub Actions.
- `.githooks/pre-commit` and `.githooks/commit-msg`, opt-in with
  `git config core.hooksPath .githooks`.
- MongoDB authentication: the server starts with `--auth`, a root user is
  created from `MONGO_ROOT_*` on a fresh volume, `docker/mongo-init.sh`
  creates the least-privilege `MONGO_APP_*` user (readWrite on `pos`), and
  api, file and backup all connect as the app user. A runbook in the README
  covers the retroactive case — enabling auth never creates users on an
  existing volume.
- A `backup` service: hourly-cadence `mongodump --archive --gzip` of `pos`
  plus a tar of the uploads volume into `BACKUP_DIR` on host disk, with
  count-based retention, `.part`-then-rename writes, a freshness healthcheck,
  and `scripts/restore.sh drill` to prove an archive restores into a
  throwaway container. Both scripts travel in the deploy bundle.
- Container hardening: both images run as uid 65534; the deploy overlay adds
  `cap_drop: ALL` (with only what each entrypoint proves it needs added
  back), `no-new-privileges`, and read-only root filesystems with tmpfs
  where a path genuinely must be writable.
- Resource ceilings in the deploy overlay — memory, CPU and pids per service,
  sized and justified for a small shop's single 4 GB host.

### Changed

- **Breaking:** every versioned endpoint moved from `/api/...` to
  `/api/v1/...`, so clients written against 1.0.0 must change their base path.
  The prefix now lives in one constant
  (`api/lib/src/config/api_routes.dart`), the role guards match the segment
  under that prefix rather than a literal `/api/admin`, and
  `api/test/unit/api_routes_test.dart` fails if the route tree, those guards
  and the OpenAPI document disagree. `/healthz`, `/readyz`, `/openapi`,
  `/swagger` and the file service's `/api/file/*` keep their paths: the first
  four are infrastructure, the last is internal to the compose network.
- `MONGO_ROOT_*` and `MONGO_APP_*` are required compose interpolations next
  to `JWT_SECRET`: the stack refuses to start credential-free.
- Both services receive discrete `MONGO_*` connection variables instead of a
  hardcoded `MONGODB_URI`, so passwords with symbols still connect (the
  services percent-encode).
- The deploy bundle grew: `deploy.yml` now also copies `scripts/backup.sh`,
  `scripts/restore.sh` and `docker/mongo-init.sh`, and `deploy.sh` chowns
  the uploads volume to uid 65534 before starting the stack.

- `api` waits for the file service to report healthy rather than merely
  started.
- `main` is a protected branch: changes arrive through a pull request whose
  `API`, `File service`, `Check workflow syntax` and `Live stack` checks are
  green, and cannot be force-pushed over.

### Fixed

- `scripts/backup.sh` can no longer publish a failed round as a good backup.
  Every step propagates its own failure: a `mongodump` or `tar` that exits
  non-zero leaves no archive, does not move `.last-success`, does not prune,
  and has its `*.part` cleaned up. Previously the `if !` that called the
  function suppressed `set -e` for its whole body, so a half-written dump was
  renamed as a complete one and the freshness marker advanced over it.
- `scripts/restore.sh restore` stops `api` and `file` while it runs, so a sale
  or upload arriving mid-restore can no longer be silently discarded.
- `scripts/restore.sh restore` drops the `pos` database before replaying the
  archive. `mongorestore --drop` clears only the collections the archive
  contains, so anything created since the backup used to survive a restore and
  the database never returned to the chosen snapshot.
- `scripts/restore.sh` resolves `BACKUP_DIR` from `.env` the way compose does,
  so a no-argument `drill` looks at the directory the backup service actually
  writes to instead of `./backups`.
- The uploads archive name is passed to the unpack container as an argument
  rather than interpolated into its `sh -c` program, closing command execution
  through a crafted filename.
- `docker/mongo-init.sh` reads the credentials from the environment inside
  `mongosh` rather than interpolating them into the script text, so a password
  containing a quote stays data instead of becoming executable code.
- `.env.example` ships blank MongoDB passwords. Non-empty placeholders
  satisfied the compose non-empty check, so a quick-start install could be
  serving real sales with published credentials.

## [1.0.0] - 2026-10-06

First release of the Dart Frog + MongoDB POS backend.

### Added

- `api/` service on port 3000: JWT login, role switching between Admin and
  Cashier, product and product-type catalogue, sales and order lifecycle, user
  administration, dashboard aggregates, invoice PDF rendering, and self-service
  documentation (Swagger UI at `/swagger`, OpenAPI 3.0.3 JSON at `/openapi`).
- `file/` service on port 8080: multipart and base64 upload plus static serving
  from `public/uploads/`.
- One response envelope across every endpoint, with field-level validation
  errors, pagination metadata, and a `503 Database connection failed` answer
  from the global error boundary when MongoDB is unreachable.
- `docker-compose.yml` with a healthchecked MongoDB published on loopback only,
  start-up gating on that healthcheck, and a `JWT_SECRET` that compose requires
  instead of defaulting.
- Idempotent seed programs compiled into both images as `/app/seed`, and
  `api/scripts/smoke.dart` for a live-stack request sweep.
- GitHub Actions `ci.yml`: per service, enforced lockfile install, strict
  formatting, analysis and unit tests. `e2e.yml`: actionlint gate, real image
  builds, a booted compose stack, seeded database, then the integration suite
  and smoke script against it.
- One pinned toolchain everywhere (`dart:3.13.4`, `dart_frog_cli` 1.2.14) plus
  committed `pubspec.lock` files, so every install runs
  `dart pub get --enforce-lockfile` and no build can resolve an unreviewed
  dependency set.
- GitHub Actions `release.yml`: images to GHCR on every merge to `main`, and
  versioned images plus a GitHub Release on an annotated `vX.Y.Z` tag.
