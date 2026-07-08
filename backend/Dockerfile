FROM maven:3.9.10-eclipse-temurin-21-alpine AS build

WORKDIR /workspace
COPY pom.xml ./
RUN mvn -B -ntp dependency:go-offline

COPY src ./src
ENV GESTUDIO_HOME=/workspace
# CI executes clean verify with Docker access before this image gate. The image
# build packages the same source without trying to launch Testcontainers inside BuildKit.
RUN mvn -B -ntp -DskipTests clean package

FROM eclipse-temurin:21.0.7_6-jre-alpine

RUN addgroup -S gestudio && adduser -S gestudio -G gestudio
WORKDIR /app
RUN mkdir -p /app/data/receipts /app/imgs && chown -R gestudio:gestudio /app

COPY --from=build --chown=gestudio:gestudio /workspace/target/backend-1.0.jar app.jar
COPY --from=build --chown=gestudio:gestudio /workspace/src/main/resources/firma_mesa-de-trabajo-1.png /app/imgs/firma_mesa-de-trabajo-1.png

ENV GESTUDIO_HOME=/app \
    APP_RECEIPTS_PATH=/app/data/receipts \
    SERVER_PORT=8080

USER gestudio
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD nc -z 127.0.0.1 "$SERVER_PORT" || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
