FROM golang:1.23-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/rivlen-gateway .
RUN mkdir -p /out/data && touch /out/data/.keep

FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app
COPY --from=build /out/rivlen-gateway /app/rivlen-gateway
COPY --from=build --chown=65532:65532 /out/data/.keep /data/.keep
ENV RIVLEN_GATEWAY_LISTEN=0.0.0.0:8787
ENV RIVLEN_DATA_FILE=/data/gateway.json
EXPOSE 8787
VOLUME ["/data"]
ENTRYPOINT ["/app/rivlen-gateway"]
