FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY ../shared/java /app/shared/java
RUN cd /app/shared/java && mvn install -DskipTests
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
ADD https://github.com/aws-observability/aws-otel-java-instrumentation/releases/download/v1.32.6/aws-opentelemetry-agent.jar /app/aws-opentelemetry-agent.jar
EXPOSE 8080
CMD ["java", "-javaagent:/app/aws-opentelemetry-agent.jar", "-jar", "app.jar"]
