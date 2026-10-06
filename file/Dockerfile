# Production image for the POS file service (Dart Frog).
#
# Base images are pinned to match api/Dockerfile and the CI workflow, so a
# toolchain release can never change a build behind our back.
FROM dart:3.13.4 AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get --enforce-lockfile
COPY . .
RUN dart pub global activate dart_frog_cli 1.2.14
RUN dart pub global run dart_frog_cli:dart_frog build
RUN dart compile exe build/bin/server.dart -o /app/server
RUN dart compile exe scripts/seed.dart -o /app/seed

FROM debian:trixie-slim
WORKDIR /app
COPY --from=build /app/server /app/server
COPY --from=build /app/seed /app/seed
# dart_frog build copies static assets (public/) next to the binary.
COPY --from=build /app/build/public /app/public
ENV UPLOAD_DIR=public/uploads
EXPOSE 8080
CMD ["/app/server"]
