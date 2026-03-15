---
title: 로컬 개발 환경
sidebar_position: 3
---

# 로컬 개발 환경

로컬에서 마이크로서비스를 개발하고 테스트하기 위한 환경 설정 가이드입니다.

## Docker Compose 환경

로컬 개발을 위한 의존성 서비스(데이터베이스, 캐시, 메시지 큐)를 Docker Compose로 실행합니다.

### docker-compose.yml

```yaml
version: '3.8'

services:
  # PostgreSQL (Aurora 대체)
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

  # MongoDB (DocumentDB 대체)
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

  # Redis (ElastiCache Valkey 대체)
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

  # Kafka (MSK 대체)
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

  # Kafka UI (개발용)
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

  # Jaeger (분산 추적 - 로컬용)
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

### Docker Compose 실행

```bash
# 전체 서비스 시작
docker-compose up -d

# 특정 서비스만 시작
docker-compose up -d postgres mongodb redis

# 로그 확인
docker-compose logs -f kafka

# 상태 확인
docker-compose ps

# 종료
docker-compose down

# 볼륨 포함 종료 (데이터 삭제)
docker-compose down -v
```

## 개별 서비스 로컬 실행

### 환경 변수 설정

각 서비스별 `.env.local` 파일을 생성합니다:

```bash
# 공통 환경 변수
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

### Go 서비스 실행 (Gin)

Go 서비스: `api-gateway`, `event-bus`, `cart`, `search`, `inventory`

```bash
# 예: cart 서비스
cd src/cart

# 의존성 설치
go mod download

# 환경 변수 로드
source .env.local

# 실행
go run cmd/main.go

# 또는 Air로 핫 리로드 실행
# go install github.com/cosmtrek/air@latest
air
```

#### Go 서비스 구조

```
src/cart/
├── cmd/
│   └── main.go           # 엔트리 포인트
├── internal/
│   ├── handler/          # HTTP 핸들러
│   ├── service/          # 비즈니스 로직
│   ├── repository/       # 데이터 액세스
│   └── middleware/       # 미들웨어
├── go.mod
├── go.sum
└── Dockerfile
```

### Java 서비스 실행 (Spring Boot)

Java 서비스: `order`, `payment`, `user-account`, `warehouse`, `returns`, `pricing`, `seller`

```bash
# 예: order 서비스
cd src/order

# Gradle로 빌드 및 실행
./gradlew bootRun

# 또는 IDE에서 실행
# IntelliJ: Run > Edit Configurations > Spring Boot

# 프로필 지정
./gradlew bootRun --args='--spring.profiles.active=local'
```

#### Java 서비스 구조

```
src/order/
├── src/main/java/com/mall/order/
│   ├── OrderApplication.java    # 메인 클래스
│   ├── controller/              # REST 컨트롤러
│   ├── service/                 # 비즈니스 로직
│   ├── repository/              # JPA 리포지토리
│   ├── entity/                  # JPA 엔티티
│   ├── dto/                     # DTO 클래스
│   └── config/                  # 설정 클래스
├── src/main/resources/
│   ├── application.yml
│   └── application-local.yml
├── build.gradle
└── Dockerfile
```

#### application-local.yml 예시

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

### Python 서비스 실행 (FastAPI)

Python 서비스: `product-catalog`, `shipping`, `user-profile`, `recommendation`, `wishlist`, `analytics`, `notification`, `review`

```bash
# 예: product-catalog 서비스
cd src/product-catalog

# 가상 환경 생성
python3 -m venv venv
source venv/bin/activate

# 의존성 설치
pip install -r requirements.txt

# 환경 변수 로드
export $(cat .env.local | xargs)

# 실행
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 또는 직접 실행
python -m app.main
```

#### Python 서비스 구조

```
src/product-catalog/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI 앱 엔트리
│   ├── api/
│   │   └── routes/          # API 라우터
│   ├── core/
│   │   └── config.py        # 설정
│   ├── models/              # Pydantic 모델
│   ├── services/            # 비즈니스 로직
│   └── repositories/        # 데이터 액세스
├── requirements.txt
├── Dockerfile
└── pytest.ini
```

## 테스트 실행

### Go 테스트

```bash
cd src/cart

# 전체 테스트
go test ./...

# 상세 출력
go test -v ./...

# 커버리지
go test -cover ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# 특정 테스트
go test -v -run TestCartService ./internal/service/...

# 통합 테스트 (태그 사용)
go test -v -tags=integration ./...
```

### Java 테스트

```bash
cd src/order

# 전체 테스트
./gradlew test

# 상세 리포트
./gradlew test --info

# 특정 테스트 클래스
./gradlew test --tests "com.mall.order.service.OrderServiceTest"

# 통합 테스트
./gradlew integrationTest

# 커버리지 리포트
./gradlew jacocoTestReport
# build/reports/jacoco/test/html/index.html
```

### Python 테스트

```bash
cd src/product-catalog
source venv/bin/activate

# 전체 테스트
pytest

# 상세 출력
pytest -v

# 커버리지
pytest --cov=app --cov-report=html
# htmlcov/index.html

# 특정 테스트
pytest tests/test_product_service.py -v

# 특정 함수
pytest tests/test_product_service.py::test_create_product -v

# 마커 기반 테스트
pytest -m "not integration"  # 통합 테스트 제외
pytest -m integration        # 통합 테스트만
```

## 로컬 데이터베이스 연결

### PostgreSQL 연결

```bash
# psql 클라이언트
psql -h localhost -U mall_user -d mall_db

# Docker exec
docker exec -it mall-postgres psql -U mall_user -d mall_db

# 테이블 확인
\dt

# 데이터 확인
SELECT * FROM products LIMIT 10;
```

### MongoDB 연결

```bash
# mongosh 클라이언트
mongosh "mongodb://mall_user:mall_password@localhost:27017/mall_db?authSource=admin"

# Docker exec
docker exec -it mall-mongodb mongosh -u mall_user -p mall_password --authenticationDatabase admin mall_db

# 컬렉션 확인
show collections

# 데이터 확인
db.products.find().limit(10).pretty()
```

### Redis 연결

```bash
# redis-cli
redis-cli -h localhost -p 6379

# Docker exec
docker exec -it mall-redis redis-cli

# 키 확인
KEYS *

# 데이터 확인
GET cart:user123
```

### OpenSearch 연결

```bash
# 클러스터 상태
curl http://localhost:9200/_cluster/health?pretty

# 인덱스 목록
curl http://localhost:9200/_cat/indices?v

# 검색
curl -X GET "http://localhost:9200/products/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"name": "스마트폰"}}}'
```

### Kafka 토픽 관리

```bash
# 토픽 목록
docker exec mall-kafka kafka-topics --bootstrap-server localhost:9092 --list

# 토픽 생성
docker exec mall-kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic order.created --partitions 3 --replication-factor 1

# 메시지 프로듀싱
docker exec -it mall-kafka kafka-console-producer \
  --bootstrap-server localhost:9092 --topic order.created

# 메시지 컨슈밍
docker exec -it mall-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic order.created --from-beginning
```

## IDE 설정

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

- Go: Go 플러그인 설치
- Java: 기본 지원
- Python: Python 플러그인 설치

각 서비스별 Run Configuration 생성:
1. Run > Edit Configurations
2. 서비스 유형에 맞는 설정 추가
3. 환경 변수 파일 지정

## 디버깅

### Go 디버깅 (Delve)

```bash
# Delve 설치
go install github.com/go-delve/delve/cmd/dlv@latest

# 디버그 모드 실행
dlv debug cmd/main.go

# VS Code에서 launch.json 설정
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

### Java 디버깅

```bash
# 디버그 포트 열기
./gradlew bootRun --debug-jvm

# 원격 디버깅 연결 (포트 5005)
```

### Python 디버깅

```bash
# debugpy 설치
pip install debugpy

# 디버그 모드 실행
python -m debugpy --listen 5678 --wait-for-client -m uvicorn app.main:app
```

## 다음 단계

- [프로젝트 구조](./project-structure) 이해
- [서비스 개발 가이드](/services/overview) 참고
- [테스트 전략](/deployment/ci-cd-pipeline) 학습
