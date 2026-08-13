FROM ghcr.io/cirruslabs/flutter:stable AS web_builder

WORKDIR /app

COPY frontend/pyeonpick_app/pubspec.yaml ./frontend/pyeonpick_app/pubspec.yaml
WORKDIR /app/frontend/pyeonpick_app
RUN flutter pub get

COPY frontend/pyeonpick_app/ ./
RUN flutter pub get && flutter build web --dart-define=DATA_MODE=remote --pwa-strategy=none

FROM node:20-slim AS runtime

WORKDIR /app

COPY backend/package.json /app/backend/package.json
RUN cd /app/backend && npm install --omit=dev

COPY backend /app/backend
COPY --from=web_builder /app/frontend/pyeonpick_app/build/web /app/frontend/pyeonpick_app/build/web

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "backend/server.js"]
