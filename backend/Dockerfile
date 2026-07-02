# ── Stage 1: build ───────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# ── Stage 2: run ────────────────────────────────────────────────────────────
FROM alpine:latest
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/server .
# Migration files must be at ./db/migrations relative to the working directory
COPY --from=builder /app/db/migrations ./db/migrations
EXPOSE 8080
CMD ["./server"]
