# Production image for the POS API (Dart Frog).
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub global activate dart_frog_cli
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
