FROM maven:3.9.10-eclipse-temurin-21-alpine AS build

ARG VCS_REF=unknown
WORKDIR /workspace
COPY pom.xml ./
RUN mvn -B -ntp dependency:go-offline

COPY src ./src
ENV GESTUDIO_HOME=/workspace
RUN set -eux; \
    latest="$(find src/main/resources/db/migration -maxdepth 1 -type f -name 'V*__*.sql' -exec basename {} \; \
      | sed -E 's/^V([0-9]+)__.*/\1/' \
      | sort -n \
      | tail -n 1)"; \
    test -n "$latest"; \
    mkdir -p /workspace/build-metadata; \
    printf '%s\n' "$latest" > /workspace/build-metadata/flyway-latest; \
    printf '%s\n' "$VCS_REF" > /workspace/build-metadata/git-revision
# CI executes clean verify with Docker access before this image gate. The image
# build packages the same source without trying to launch Testcontainers inside BuildKit.
RUN mvn -B -ntp -DskipTests clean package

FROM eclipse-temurin:21.0.7_6-jre-alpine

ARG VCS_REF=unknown
LABEL org.opencontainers.image.revision="$VCS_REF" \
      org.gestudio.flyway.metadata="/app/build-metadata/flyway-latest"

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
  CMD nc -z 127.0.0.1 "$SERVER_PORT" || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
