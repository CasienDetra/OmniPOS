# Production image for the POS file service (Dart Frog).
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub global activate dart_frog_cli
RUN dart pub global run dart_frog_cli:dart_frog build
RUN dart compile exe build/bin/server.dart -o /app/server
RUN dart compile exe scripts/seed.dart -o /app/seed

FROM debian:stable-slim
WORKDIR /app
COPY --from=build /app/server /app/server
COPY --from=build /app/seed /app/seed
# dart_frog build copies static assets (public/) next to the binary.
COPY --from=build /app/build/public /app/public
ENV UPLOAD_DIR=public/uploads
EXPOSE 8080
CMD ["/app/server"]
