#!/usr/bin/env bash
source /etc/default/gestudio-backend
exec /usr/bin/java \
  -Dspring.config.additional-location=classpath:/application.properties \
  -jar "$GESTUDIO_HOME/backend/target/backend-1.0.jar"
