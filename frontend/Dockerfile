# syntax=docker/dockerfile:1.7
FROM node:22-alpine3.24 AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm,sharing=locked npm ci --no-audit --no-fund

COPY . .

ARG VITE_API_BASE_URL
ARG VITE_APP_TIME_ZONE=America/Argentina/Buenos_Aires
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL \
    VITE_APP_TIME_ZONE=$VITE_APP_TIME_ZONE
RUN npm run build

FROM nginx:1.30.0-alpine3.23

ARG VCS_REF=unknown
ARG COMPOSE_SHA=unknown
ARG SOURCE_SHA=unknown
LABEL org.opencontainers.image.revision="$VCS_REF" \
      org.gestudio.compose.sha256="$COMPOSE_SHA" \
      org.gestudio.source.sha256="$SOURCE_SHA"

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

RUN sed -i '/^user  nginx;/d; s|^[[:space:]]*pid[[:space:]][[:space:]]*[^;]*;|pid /tmp/nginx.pid;|' /etc/nginx/nginx.conf \
    && chown nginx:nginx /var/cache/nginx

USER nginx

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/ || exit 1

ENTRYPOINT ["nginx", "-g", "daemon off;"]
