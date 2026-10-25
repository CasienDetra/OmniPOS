# Production image for the POS file service (Dart Frog).
#
# Base images are pinned to match api/Dockerfile and the CI workflow, so a
# toolchain release can never change a build behind our back.
FROM dart:3.14.0-315.2.beta AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get --enforce-lockfile
COPY . .
RUN dart pub global activate dart_frog_cli 1.2.14
RUN dart pub global run dart_frog_cli:dart_frog build
RUN dart compile exe build/bin/server.dart -o /app/server
RUN dart compile exe scripts/seed.dart -o /app/seed
RUN dart compile exe scripts/probe.dart -o /app/probe

FROM debian:trixie-slim
WORKDIR /app
COPY --from=build /app/server /app/server
COPY --from=build /app/seed /app/seed
COPY --from=build /app/probe /app/probe
# dart_frog build copies static assets (public/) next to the binary.
COPY --from=build /app/build/public /app/public
# The server writes uploads under this path, so the directory must belong to
# the user the container runs as. When Docker first mounts an empty named
# volume it copies this directory - mode and ownership included - out of the
# image, which is what keeps a plain `docker compose up` working for new
# checkouts. A volume created by the older root-owned image needs the one-time
# chown described in the README instead.
RUN mkdir -p /app/public/uploads \
  && chown 65534:65534 /app/public/uploads \
  && chmod 755 /app/public/uploads
# 65534:nobody - same numeric id as api/Dockerfile, referenced here because
# Debian's /etc/passwd does map it to a name.
USER 65534:65534
ENV UPLOAD_DIR=public/uploads
EXPOSE 8080
CMD ["/app/server"]
