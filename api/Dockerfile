# Production image for the POS API (Dart Frog).
#
# The toolchain is pinned so CI, local builds and deployments compile
# identically. Bump deliberately, together with the base image of the file
# service and the job containers in .github/workflows/ci.yml.
FROM dart:3.14.0-315.2.beta AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get --enforce-lockfile
COPY . .

# Gate the image on the unit suite: failing code never reaches a binary.
RUN dart test test/unit

RUN dart pub global activate dart_frog_cli 1.2.14
RUN dart pub global run dart_frog_cli:dart_frog build
RUN dart compile exe build/bin/server.dart -o /app/server
RUN dart compile exe scripts/seed.dart -o /app/seed
RUN dart compile exe scripts/probe.dart -o /app/probe

FROM scratch
WORKDIR /app
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
COPY --from=build /app/seed /app/seed
COPY --from=build /app/probe /app/probe
# scratch has no /etc/passwd, so the id must be numeric. 65534 is nobody on
# Debian, which is what the file service runs as: both containers share the
# uploads volume's owner even though only file writes it. Ports above 1024
# mean this costs nothing, and a uid 0 process reached by an exploit would
# still be root only inside a container the compose layer has already taken
# its capabilities away from - belt and braces.
USER 65534:65534
EXPOSE 3000
CMD ["/app/server"]
