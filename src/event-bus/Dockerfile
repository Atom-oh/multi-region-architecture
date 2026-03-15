FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY ../shared/go/go.mod ../shared/go/go.sum* ./shared/go/
COPY ../shared/go/pkg ./shared/go/pkg
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /event-bus ./cmd/main.go

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /event-bus /event-bus
EXPOSE 8080
CMD ["/event-bus"]
