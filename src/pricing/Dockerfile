FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY shared/java /app/shared/java
RUN cd /app/shared/java && mvn install -DskipTests -q
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q
ADD https://github.com/aws-observability/aws-otel-java-instrumentation/releases/download/v1.32.6/aws-opentelemetry-agent.jar /otel-agent.jar

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
COPY --from=builder /otel-agent.jar /otel-agent.jar
EXPOSE 8080
ENV JAVA_TOOL_OPTIONS="-javaagent:/otel-agent.jar"
CMD ["java", "-jar", "app.jar"]
