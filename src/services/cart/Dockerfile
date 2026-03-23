FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY shared/go ./shared/go
COPY services/cart ./services/cart
WORKDIR /app/services/cart
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o /service .

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip && \
    curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip && \
    apt-get purge -y curl unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /service .
EXPOSE 8080
CMD ["./service"]
