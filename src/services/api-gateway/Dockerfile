FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY shared/go ./shared/go
COPY services/api-gateway ./services/api-gateway
WORKDIR /app/services/api-gateway
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o /service .

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /service .
EXPOSE 8080
CMD ["./service"]
