# syntax=docker/dockerfile:1.7
FROM node:22.23.4-alpine3.24@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm,sharing=locked npm ci --no-audit --no-fund

COPY . .

ARG VITE_API_BASE_URL
ARG VITE_BASE_PATH=/
ARG VITE_APP_TIME_ZONE=America/Argentina/Buenos_Aires
ARG VITE_PUBLIC_DEMO_ENABLED=false
ARG VITE_PUBLIC_DEMO_USERNAME
ARG VITE_PUBLIC_DEMO_PASSWORD
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL \
    VITE_BASE_PATH=$VITE_BASE_PATH \
    VITE_APP_TIME_ZONE=$VITE_APP_TIME_ZONE \
    VITE_PUBLIC_DEMO_ENABLED=$VITE_PUBLIC_DEMO_ENABLED \
    VITE_PUBLIC_DEMO_USERNAME=$VITE_PUBLIC_DEMO_USERNAME \
    VITE_PUBLIC_DEMO_PASSWORD=$VITE_PUBLIC_DEMO_PASSWORD
RUN npm run build

FROM nginx:1.30.6-alpine3.24-slim@sha256:d9322bba63c6cfc63dc9e86522fd4f95fd4d9020a02b5bced282bbf38b8c3960

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
