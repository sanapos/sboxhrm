# Stage 1: Build Flutter web app
FROM ghcr.io/cirruslabs/flutter:latest AS build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
ARG API_BASE_URL=http://localhost:7070
RUN flutter build web --release --base-href="/" --no-tree-shake-icons \
    --dart-define=API_BASE_URL=$API_BASE_URL && \
    rm -f build/web/flutter_service_worker.js && \
    sed -i 's/_flutter.loader.load({[^}]*});/_flutter.loader.load();/g' build/web/flutter_bootstrap.js 2>/dev/null || true

# Stage 2: Serve with nginx  
FROM nginx:alpine AS production

# Copy built flutter web app (includes home.html, privacy-policy, landing images from web/)
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create entrypoint script to inject API_BASE_URL at runtime
RUN echo '#!/bin/sh' > /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'API_URL="${API_BASE_URL:-http://localhost:7070}"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'GTAG="${GOOGLE_TAG_ID:-__GOOGLE_TAG_ID__}"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'GSC="${GOOGLE_SITE_VERIFICATION:-__GOOGLE_SITE_VERIFICATION__}"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'for f in /usr/share/nginx/html/index.html /usr/share/nginx/html/config.js; do' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo '  [ -f "$f" ] || continue' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo '  sed -i "s|__API_BASE_URL__|$API_URL|g" "$f"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo '  sed -i "s|__GOOGLE_TAG_ID__|$GTAG|g" "$f"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo '  sed -i "s|__GOOGLE_SITE_VERIFICATION__|$GSC|g" "$f"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'done' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'echo "Injected API_BASE_URL=$API_URL GOOGLE_TAG_ID=${GTAG:0:12}..."' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    chmod +x /docker-entrypoint.d/40-inject-api-url.sh

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
