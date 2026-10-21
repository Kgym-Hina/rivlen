ARG BUILD_FROM=ghcr.io/home-assistant/base:3.23
FROM golang:1.23-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/rivlen-gateway .

FROM ${BUILD_FROM}

WORKDIR /app
COPY --from=build /out/rivlen-gateway /app/rivlen-gateway
ENV RIVLEN_GATEWAY_LISTEN=0.0.0.0:8787
ENV RIVLEN_DATA_FILE=/data/gateway.json
EXPOSE 8787
VOLUME ["/data"]
ENTRYPOINT ["/app/rivlen-gateway"]
