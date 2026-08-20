# syntax=docker/dockerfile:1.7
FROM maven:3.9.16-eclipse-temurin-21-alpine AS build

ARG VCS_REF=unknown
WORKDIR /workspace
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    mvn -B -ntp dependency:go-offline

COPY src ./src
ENV GESTUDIO_HOME=/workspace
RUN set -eux; \
    migration_root='src/main/resources/db/migration'; \
    versioned_latest="$(find src/main/resources/db/migration -maxdepth 1 -type f -name 'V*__*.sql' -exec basename {} \; \
      | sed -E 's/^V([0-9]+)__.*/\1/' \
      | sort -n \
      | tail -n 1)"; \
    baseline_latest="$(find src/main/resources/db/migration -maxdepth 1 -type f -name 'B*__*.sql' -exec basename {} \; \
      | sed -E 's/^B([0-9]+)__.*/\1/' \
      | sort -n \
      | tail -n 1)"; \
    test -n "$versioned_latest"; \
    test -n "$baseline_latest"; \
    test "$baseline_latest" = "$versioned_latest"; \
    baseline_script="$(find src/main/resources/db/migration -maxdepth 1 -type f \
      -name "B${baseline_latest}__*.sql" -exec basename {} \;)"; \
    test "$(printf '%s\n' "$baseline_script" | grep -c .)" -eq 1; \
    if grep -q '<artifactId>spring-boot-starter-actuator</artifactId>' pom.xml; then \
      health_contract='actuator-readiness-v1'; \
    else \
      health_contract='legacy-api-401-v1'; \
    fi; \
    mkdir -p /workspace/build-metadata; \
    resource_names='/workspace/build-metadata/flyway-resource-names'; \
    find "$migration_root" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort > "$resource_names"; \
    test -s "$resource_names"; \
    printf 'gestudio-flyway-manifest-v1\n' > /workspace/build-metadata/flyway-resources.sha256; \
    tab="$(printf '\t')"; \
    while IFS= read -r resource_name; do \
      test -n "$resource_name"; \
      case "$resource_name" in *"$tab"*) exit 1 ;; esac; \
      resource_sha256="$(sha256sum "$migration_root/$resource_name" | awk '{print $1}')"; \
      printf '%s\t%s\n' "$resource_sha256" "$resource_name" >> /workspace/build-metadata/flyway-resources.sha256; \
    done < "$resource_names"; \
    rm "$resource_names"; \
    printf '%s\n' "$versioned_latest" > /workspace/build-metadata/flyway-latest; \
    printf '%s\n' "$versioned_latest" > /workspace/build-metadata/flyway-versioned-latest; \
    printf '%s\n' "$baseline_script" > /workspace/build-metadata/flyway-baseline-script; \
    printf '%s\n' "$VCS_REF" > /workspace/build-metadata/git-revision; \
    printf '%s\n' "$health_contract" > /workspace/build-metadata/health-contract
# CI executes clean verify with Docker access before this image gate. The image
# build packages the same source without trying to launch Testcontainers inside BuildKit.
RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    mvn -B -ntp -DskipTests clean package

FROM eclipse-temurin:21-jre-alpine-3.23

ARG VCS_REF=unknown
ARG COMPOSE_SHA=unknown
ARG SOURCE_SHA=unknown
LABEL org.opencontainers.image.revision="$VCS_REF" \
      org.gestudio.compose.sha256="$COMPOSE_SHA" \
      org.gestudio.source.sha256="$SOURCE_SHA" \
      org.gestudio.flyway.metadata="/app/build-metadata/flyway-latest" \
      org.gestudio.flyway.versioned-metadata="/app/build-metadata/flyway-versioned-latest" \
      org.gestudio.flyway.baseline-metadata="/app/build-metadata/flyway-baseline-script" \
      org.gestudio.flyway.resources-metadata="/app/build-metadata/flyway-resources.sha256" \
      org.gestudio.health.metadata="/app/build-metadata/health-contract"

RUN addgroup -S gestudio && adduser -S gestudio -G gestudio
WORKDIR /app
RUN mkdir -p /app/data/receipts /app/imgs /app/build-metadata && chown -R gestudio:gestudio /app

COPY --from=build --chown=gestudio:gestudio /workspace/target/backend-1.0.jar app.jar
COPY --from=build --chown=gestudio:gestudio /workspace/src/main/resources/firma_mesa-de-trabajo-1.png /app/imgs/firma_mesa-de-trabajo-1.png
COPY --from=build --chown=gestudio:gestudio /workspace/build-metadata /app/build-metadata

ENV GESTUDIO_HOME=/app \
    APP_RECEIPTS_PATH=/app/data/receipts \
    SERVER_PORT=8080

USER gestudio
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD contract="$(cat /app/build-metadata/health-contract 2>/dev/null || printf 'legacy-api-401-v1')"; \
      case "$contract" in \
        actuator-readiness-v1) wget -qO- "http://127.0.0.1:${SERVER_PORT}/actuator/health/readiness" | grep -q '"status":"UP"' ;; \
        legacy-api-401-v1) wget -S -O /dev/null "http://127.0.0.1:${SERVER_PORT}/api/alumnos" 2>&1 | grep -Eq 'HTTP/[0-9.]+ 401' ;; \
        *) exit 1 ;; \
      esac

ENTRYPOINT ["java", "-jar", "app.jar"]
