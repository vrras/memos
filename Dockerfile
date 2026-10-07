# syntax=docker/dockerfile:1

# Self-contained build for Coolify: frontend + backend built inside the image.
# The repo's scripts/Dockerfile expects `pnpm release` to be run on the host first.

FROM node:24-alpine AS frontend
RUN npm install -g pnpm@11.0.1
WORKDIR /build
COPY web/package.json web/pnpm-lock.yaml web/pnpm-workspace.yaml ./web/
COPY web/patches ./web/patches
RUN cd web && pnpm install --frozen-lockfile
COPY web/ ./web/
RUN cd web && pnpm release

FROM golang:1.27.0-alpine AS backend
WORKDIR /backend-build
RUN apk add --no-cache git ca-certificates
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN rm -rf server/frontend/dist
COPY --from=frontend /build/server/frontend/dist ./server/frontend/dist
ARG VERSION="" COMMIT=unknown
RUN VERSION=${VERSION:-$(date -u +%y.%m)} && \
    CGO_ENABLED=0 \
    go build -trimpath \
      -ldflags="-s -w -X github.com/usememos/memos/internal/version.Version=${VERSION} -X github.com/usememos/memos/internal/version.Commit=${COMMIT} -extldflags '-static'" \
      -tags netgo,osusergo \
      -o memos ./cmd/memos

FROM alpine:3.21
RUN apk add --no-cache tzdata ca-certificates su-exec && \
    addgroup -g 10001 -S nonroot && \
    adduser -u 10001 -S -G nonroot -h /var/opt/memos nonroot && \
    mkdir -p /var/opt/memos /usr/local/memos && \
    chown -R nonroot:nonroot /var/opt/memos
COPY --from=backend /backend-build/memos /usr/local/memos/memos
COPY --from=backend /backend-build/scripts/entrypoint.sh /usr/local/memos/entrypoint.sh
RUN chmod 755 /usr/local/memos/entrypoint.sh
USER root
WORKDIR /var/opt/memos
VOLUME /var/opt/memos
ENV TZ="UTC" \
    MEMOS_PORT="5230"
EXPOSE 5230
ENTRYPOINT ["/usr/local/memos/entrypoint.sh", "/usr/local/memos/memos"]
