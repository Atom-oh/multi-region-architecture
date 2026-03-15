FROM golang:1.22-alpine AS builder
WORKDIR /build/service
COPY shared/go/go.mod ../shared/go/go.sum* /build/shared/go/
COPY shared/go/pkg /build/shared/go/pkg
COPY go.mod go.sum* ./
RUN go mod download || true
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o /app ./cmd/main.go

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /app /app
EXPOSE 8080
CMD ["/app"]
