FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY shared/go ./shared/go
COPY services/inventory ./services/inventory
WORKDIR /app/services/inventory
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o /service .

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /service .
EXPOSE 8080
CMD ["./service"]
