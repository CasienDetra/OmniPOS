import 'package:dart_frog/dart_frog.dart';

/// Swagger UI shell; the spec itself is served from /openapi.
Response onRequest(RequestContext context) {
  return Response(
    body: _html,
    headers: const {'content-type': 'text/html; charset=utf-8'},
  );
}

const _html = '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>POS API — Swagger UI</title>
    <link
      rel="stylesheet"
      href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css"
    />
    <style>
      body { margin: 0; }
      .swagger-ui .topbar { display: none; }
    </style>
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script>
      window.ui = SwaggerUIBundle({
        url: '/openapi',
        dom_id: '#swagger-ui',
        deepLinking: true,
        docExpansion: 'list',
        persistAuthorization: true,
        tryItOutEnabled: true,
      });
    </script>
  </body>
</html>
''';
