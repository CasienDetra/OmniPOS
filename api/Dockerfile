# Production image for the POS API (Dart Frog).
#
# The toolchain is pinned so CI, local builds and deployments compile
# identically. Bump deliberately, together with the base image of the file
# service and the job containers in .github/workflows/ci.yml.
FROM dart:3.13.4 AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .

# Gate the image on the unit suite: failing code never reaches a binary.
RUN dart test test/unit

RUN dart pub global activate dart_frog_cli 1.2.14
RUN dart pub global run dart_frog_cli:dart_frog build
RUN dart compile exe build/bin/server.dart -o /app/server
RUN dart compile exe scripts/seed.dart -o /app/seed

FROM scratch
WORKDIR /app
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
COPY --from=build /app/seed /app/seed
EXPOSE 3000
CMD ["/app/server"]
