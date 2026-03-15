FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY ../shared/go/go.mod ../shared/go/go.sum* ./shared/go/
COPY ../shared/go/pkg ./shared/go/pkg
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /cart ./cmd/main.go

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /cart /cart
EXPOSE 8080
CMD ["/cart"]
