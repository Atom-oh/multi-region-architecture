---
title: Local Development Environment
sidebar_position: 3
---

# Local Development Environment

A guide for setting up the environment to develop and test microservices locally.

## Docker Compose Environment

Run dependency services (databases, cache, message queue) for local development using Docker Compose.

### docker-compose.yml

```yaml
version: '3.8'

services:
  # PostgreSQL (Aurora replacement)
  postgres:
    image: postgres:15-alpine
    container_name: mall-postgres
    environment:
      POSTGRES_USER: mall_user
      POSTGRES_PASSWORD: mall_password
      POSTGRES_DB: mall_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./scripts/seed-data/seed-aurora.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U mall_user -d mall_db"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MongoDB (DocumentDB replacement)
  mongodb:
    image: mongo:7.0
    container_name: mall-mongodb
    environment:
      MONGO_INITDB_ROOT_USERNAME: mall_user
      MONGO_INITDB_ROOT_PASSWORD: mall_password
      MONGO_INITDB_DATABASE: mall_db
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
      - ./scripts/seed-data/seed-documentdb.js:/docker-entrypoint-initdb.d/init.js
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis (ElastiCache Valkey replacement)
  redis:
    image: redis:7.2-alpine
    container_name: mall-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # OpenSearch
  opensearch:
    image: opensearchproject/opensearch:2.11.0
    container_name: mall-opensearch
    environment:
      - discovery.type=single-node
      - plugins.security.disabled=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
    ports:
      - "9200:9200"
      - "9600:9600"
    volumes:
      - opensearch_data:/usr/share/opensearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:9200/_cluster/health | grep -q 'green\\|yellow'"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Kafka (MSK replacement)
  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    container_name: mall-zookeeper
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    ports:
      - "2181:2181"

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    container_name: mall-kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
      - "29092:29092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://localhost:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
    healthcheck:
      test: ["CMD-SHELL", "kafka-topics --bootstrap-server localhost:9092 --list"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Kafka UI (for development)
  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    container_name: mall-kafka-ui
    depends_on:
      - kafka
    ports:
      - "8090:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:29092

  # Jaeger (Distributed tracing - local)
  jaeger:
    image: jaegertracing/all-in-one:1.52
    container_name: mall-jaeger
    ports:
      - "16686:16686"  # UI
      - "4317:4317"    # OTLP gRPC
      - "4318:4318"    # OTLP HTTP
    environment:
      COLLECTOR_OTLP_ENABLED: "true"

volumes:
  postgres_data:
  mongodb_data:
  redis_data:
  opensearch_data:
```

### Running Docker Compose

```bash
# Start all services
docker-compose up -d

# Start specific services only
docker-compose up -d postgres mongodb redis

# Check logs
docker-compose logs -f kafka

# Check status
docker-compose ps

# Stop
docker-compose down

# Stop including volumes (delete data)
docker-compose down -v
```

## Running Individual Services Locally

### Environment Variable Setup

Create a `.env.local` file for each service:

```bash
# Common environment variables
export REGION=local
export ENVIRONMENT=development

# PostgreSQL
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=mall_user
export DB_PASSWORD=mall_password
export DB_NAME=mall_db

# MongoDB
export MONGODB_URI=mongodb://mall_user:mall_password@localhost:27017/mall_db?authSource=admin

# Redis
export REDIS_HOST=localhost
export REDIS_PORT=6379

# OpenSearch
export OPENSEARCH_ENDPOINT=http://localhost:9200

# Kafka
export KAFKA_BROKERS=localhost:9092

# OpenTelemetry
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_SERVICE_NAME=<service-name>
```

### Running Go Services (Gin)

Go services: `api-gateway`, `event-bus`, `cart`, `search`, `inventory`

```bash
# Example: cart service
cd src/cart

# Install dependencies
go mod download

# Load environment variables
source .env.local

# Run
go run cmd/main.go

# Or run with hot reload using Air
# go install github.com/cosmtrek/air@latest
air
```

#### Go Service Structure

```
src/cart/
├── cmd/
│   └── main.go           # Entry point
├── internal/
│   ├── handler/          # HTTP handlers
│   ├── service/          # Business logic
│   ├── repository/       # Data access
│   └── middleware/       # Middleware
├── go.mod
├── go.sum
└── Dockerfile
```

### Running Java Services (Spring Boot)

Java services: `order`, `payment`, `user-account`, `warehouse`, `returns`, `pricing`, `seller`

```bash
# Example: order service
cd src/order

# Build and run with Gradle
./gradlew bootRun

# Or run from IDE
# IntelliJ: Run > Edit Configurations > Spring Boot

# Specify profile
./gradlew bootRun --args='--spring.profiles.active=local'
```

#### Java Service Structure

```
src/order/
├── src/main/java/com/mall/order/
│   ├── OrderApplication.java    # Main class
│   ├── controller/              # REST controllers
│   ├── service/                 # Business logic
│   ├── repository/              # JPA repositories
│   ├── entity/                  # JPA entities
│   ├── dto/                     # DTO classes
│   └── config/                  # Configuration classes
├── src/main/resources/
│   ├── application.yml
│   └── application-local.yml
├── build.gradle
└── Dockerfile
```

#### application-local.yml Example

```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/mall_db
    username: mall_user
    password: mall_password
  kafka:
    bootstrap-servers: localhost:9092

management:
  tracing:
    sampling:
      probability: 1.0
  otlp:
    tracing:
      endpoint: http://localhost:4317
```

### Running Python Services (FastAPI)

Python services: `product-catalog`, `shipping`, `user-profile`, `recommendation`, `wishlist`, `analytics`, `notification`, `review`

```bash
# Example: product-catalog service
cd src/product-catalog

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Load environment variables
export $(cat .env.local | xargs)

# Run
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Or run directly
python -m app.main
```

#### Python Service Structure

```
src/product-catalog/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app entry
│   ├── api/
│   │   └── routes/          # API routers
│   ├── core/
│   │   └── config.py        # Configuration
│   ├── models/              # Pydantic models
│   ├── services/            # Business logic
│   └── repositories/        # Data access
├── requirements.txt
├── Dockerfile
└── pytest.ini
```

## Running Tests

### Go Tests

```bash
cd src/cart

# Run all tests
go test ./...

# Verbose output
go test -v ./...

# Coverage
go test -cover ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Specific tests
go test -v -run TestCartService ./internal/service/...

# Integration tests (using tags)
go test -v -tags=integration ./...
```

### Java Tests

```bash
cd src/order

# Run all tests
./gradlew test

# Detailed report
./gradlew test --info

# Specific test class
./gradlew test --tests "com.mall.order.service.OrderServiceTest"

# Integration tests
./gradlew integrationTest

# Coverage report
./gradlew jacocoTestReport
# build/reports/jacoco/test/html/index.html
```

### Python Tests

```bash
cd src/product-catalog
source venv/bin/activate

# Run all tests
pytest

# Verbose output
pytest -v

# Coverage
pytest --cov=app --cov-report=html
# htmlcov/index.html

# Specific tests
pytest tests/test_product_service.py -v

# Specific function
pytest tests/test_product_service.py::test_create_product -v

# Marker-based tests
pytest -m "not integration"  # Exclude integration tests
pytest -m integration        # Integration tests only
```

## Local Database Connections

### PostgreSQL Connection

```bash
# psql client
psql -h localhost -U mall_user -d mall_db

# Docker exec
docker exec -it mall-postgres psql -U mall_user -d mall_db

# Check tables
\dt

# Check data
SELECT * FROM products LIMIT 10;
```

### MongoDB Connection

```bash
# mongosh client
mongosh "mongodb://mall_user:mall_password@localhost:27017/mall_db?authSource=admin"

# Docker exec
docker exec -it mall-mongodb mongosh -u mall_user -p mall_password --authenticationDatabase admin mall_db

# Check collections
show collections

# Check data
db.products.find().limit(10).pretty()
```

### Redis Connection

```bash
# redis-cli
redis-cli -h localhost -p 6379

# Docker exec
docker exec -it mall-redis redis-cli

# Check keys
KEYS *

# Check data
GET cart:user123
```

### OpenSearch Connection

```bash
# Cluster status
curl http://localhost:9200/_cluster/health?pretty

# Index list
curl http://localhost:9200/_cat/indices?v

# Search
curl -X GET "http://localhost:9200/products/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"name": "smartphone"}}}'
```

### Kafka Topic Management

```bash
# List topics
docker exec mall-kafka kafka-topics --bootstrap-server localhost:9092 --list

# Create topic
docker exec mall-kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic order.created --partitions 3 --replication-factor 1

# Produce messages
docker exec -it mall-kafka kafka-console-producer \
  --bootstrap-server localhost:9092 --topic order.created

# Consume messages
docker exec -it mall-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic order.created --from-beginning
```

## IDE Setup

### VS Code

`.vscode/settings.json`:

```json
{
  "go.useLanguageServer": true,
  "python.defaultInterpreterPath": "${workspaceFolder}/src/product-catalog/venv/bin/python",
  "java.configuration.updateBuildConfiguration": "automatic",
  "editor.formatOnSave": true,
  "[go]": {
    "editor.defaultFormatter": "golang.go"
  },
  "[python]": {
    "editor.defaultFormatter": "ms-python.black-formatter"
  },
  "[java]": {
    "editor.defaultFormatter": "redhat.java"
  }
}
```

### IntelliJ IDEA

- Go: Install Go plugin
- Java: Native support
- Python: Install Python plugin

Create Run Configuration for each service:
1. Run > Edit Configurations
2. Add configuration for service type
3. Specify environment variable file

## Debugging

### Go Debugging (Delve)

```bash
# Install Delve
go install github.com/go-delve/delve/cmd/dlv@latest

# Run in debug mode
dlv debug cmd/main.go

# VS Code launch.json setup
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Launch Cart Service",
      "type": "go",
      "request": "launch",
      "mode": "debug",
      "program": "${workspaceFolder}/src/cart/cmd/main.go",
      "envFile": "${workspaceFolder}/src/cart/.env.local"
    }
  ]
}
```

### Java Debugging

```bash
# Open debug port
./gradlew bootRun --debug-jvm

# Connect remote debugging (port 5005)
```

### Python Debugging

```bash
# Install debugpy
pip install debugpy

# Run in debug mode
python -m debugpy --listen 5678 --wait-for-client -m uvicorn app.main:app
```

## Next Steps

- Understand [Project Structure](./project-structure)
- Refer to [Service Development Guide](/services/overview)
- Learn [Testing Strategy](/deployment/ci-cd-pipeline)
