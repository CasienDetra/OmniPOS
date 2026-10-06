# Changelog

All notable changes to this project are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions apply to the repository as a whole: `api/` and `file/` are released
under one tag, and the release workflow refuses to publish when a tag
disagrees with either service's `pubspec.yaml` or with an entry here.

## [Unreleased]

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
