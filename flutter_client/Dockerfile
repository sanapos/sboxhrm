# Stage 1: Build Flutter web app
FROM ghcr.io/cirruslabs/flutter:latest AS build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
ARG API_BASE_URL=http://localhost:7070
RUN flutter build web --release --base-href="/" --no-tree-shake-icons \
    --dart-define=API_BASE_URL=$API_BASE_URL

# Stage 2: Serve with nginx  
FROM nginx:alpine AS production

# Copy built flutter web app
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create entrypoint script to inject API_BASE_URL at runtime
RUN echo '#!/bin/sh' > /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'API_URL="${API_BASE_URL:-http://localhost:7070}"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'echo "Injecting API_BASE_URL=$API_URL"' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'sed -i "s|__API_BASE_URL__|$API_URL|g" /usr/share/nginx/html/index.html' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    echo 'sed -i "s|__API_BASE_URL__|$API_URL|g" /usr/share/nginx/html/config.js' >> /docker-entrypoint.d/40-inject-api-url.sh && \
    chmod +x /docker-entrypoint.d/40-inject-api-url.sh

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
