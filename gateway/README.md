# Rivlen Gateway

Rivlen Gateway exposes a small, authenticated Node-RED Admin API surface on a
separate port. Node-RED stays on the private network; the gateway reads and
deploys flows through its local Admin API connection.

The public API only forwards `GET /flows` and `POST /flows`. Device tokens are
random, stored as hashes on the gateway, and can be revoked by the first paired
device. Pairing files are one-time invitations that expire after ten minutes.
The custom pairing password is required both to create an invitation and to
exchange it for a device token.

## Configure and run

Go 1.23 or newer is required. Set a custom pairing password with at least 12
characters. For a gateway running on the same host as Node-RED, the default
target is `http://127.0.0.1:1880`.

```sh
cd gateway
export RIVLEN_PAIRING_PASSWORD='use-a-private-password-of-at-least-12-characters'
export RIVLEN_NODE_RED_URL='http://127.0.0.1:1880'
export RIVLEN_PUBLIC_URL='https://flows.example.com'
go run .
```

Configuration:

| Variable | Default | Purpose |
| --- | --- | --- |
| `RIVLEN_GATEWAY_LISTEN` | `127.0.0.1:8787` | Gateway bind address and port |
| `RIVLEN_NODE_RED_URL` | `http://127.0.0.1:1880` | Node-RED base URL, including any reverse proxy path |
| `RIVLEN_PUBLIC_URL` | Request host | Optional fixed URL encoded in pairing files; leave it blank to use the browser request URL |
| `RIVLEN_PAIRING_PASSWORD` | Required | Custom password used for pairing |
| `RIVLEN_DATA_FILE` | `./data/gateway.json` | Persistent gateway ID, device names, token hashes, and access times |
| `RIVLEN_NODE_RED_AUTH_MODE` | `admin` | Use `basic` for a Home Assistant App port protected by Home Assistant credentials |
| `RIVLEN_NODE_RED_TOKEN` | Empty | Node-RED Admin API bearer token |
| `RIVLEN_NODE_RED_USERNAME` | Empty | Node-RED Admin API username |
| `RIVLEN_NODE_RED_PASSWORD` | Empty | Node-RED Admin API password |
| `RIVLEN_TLS_CERT` | Empty | TLS certificate for direct HTTPS access |
| `RIVLEN_TLS_KEY` | Empty | TLS private key for direct HTTPS access |

For an authenticated Node-RED instance, set either `RIVLEN_NODE_RED_TOKEN` or
both `RIVLEN_NODE_RED_USERNAME` and `RIVLEN_NODE_RED_PASSWORD`. The gateway
exchanges username and password for a Node-RED token and refreshes it after an
upstream 401 response. Give that account `flows.read` and `flows.write` scopes.

For the Home Assistant Community Node-RED App's direct port, set
`RIVLEN_NODE_RED_AUTH_MODE=basic` and provide a Home Assistant username and
password using `RIVLEN_NODE_RED_USERNAME` and `RIVLEN_NODE_RED_PASSWORD`. The
App checks those credentials through Home Assistant before forwarding requests
to Node-RED; this is separate from Node-RED's Admin API token login.

When the gateway is behind a reverse proxy, leave `RIVLEN_PUBLIC_URL` empty if
the proxy preserves the browser `Host` and `X-Forwarded-Proto` headers. New
pairing files then use the URL currently shown in the browser. Set the variable
only when the proxy does not preserve those headers or when a fixed canonical
URL is required.

## Connect Rivlen

1. Open the gateway URL in a browser and enter the custom pairing password.
2. Scan the QR code in Rivlen with **连接新实例 → 通过网关配对**, or download the
   pairing file and import it in the app.
3. Enter the same pairing password in Rivlen and name the device.
4. The first paired device becomes the owner and can manage authorizations from
   that gateway's connection menu.

The pairing file contains the gateway URL, gateway ID, short-lived invitation
ID, and expiry time. It does not contain the pairing password or device token.
The password is checked again when the app exchanges the file.

## Public access and TLS

Use HTTPS for pairing and API access over the public internet. HTTP pairing URLs
are accepted only for localhost and private LAN addresses. The gateway listens
on localhost by default. A reverse proxy can terminate TLS while the gateway
runs on a private interface. For example, with Caddy:

```caddyfile
flows.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

Set `RIVLEN_PUBLIC_URL=https://flows.example.com`. Forward only the gateway
port through a tunnel or reverse proxy; keep Node-RED's port private. The
gateway does not enable cross-origin access and does not proxy arbitrary paths.

For direct HTTPS without a reverse proxy, configure `RIVLEN_TLS_CERT` and
`RIVLEN_TLS_KEY`, bind the gateway to the intended public interface, and set
`RIVLEN_PUBLIC_URL` to the HTTPS address and port. Do not expose an unencrypted
gateway port to the public internet.

For a binary or `go run` deployment, a direct TLS setup looks like:

```sh
export RIVLEN_GATEWAY_LISTEN='0.0.0.0:8787'
export RIVLEN_PUBLIC_URL='https://flows.example.com:8787'
export RIVLEN_TLS_CERT='/etc/letsencrypt/live/flows.example.com/fullchain.pem'
export RIVLEN_TLS_KEY='/etc/letsencrypt/live/flows.example.com/privkey.pem'
go run .
```

For Docker, copy `.env.example` to `.env`, replace its password and public URL,
then run:

```sh
cd gateway
cp .env.example .env
docker compose up -d --build
```

The compose file binds its host port to localhost by default and connects to
Node-RED at `host.docker.internal:1880`.
When both services use the same Docker network, set `RIVLEN_NODE_RED_URL` to
the Node-RED service name instead. Keep `.env` and the `certs/` directory private.
For direct HTTPS, place the certificate and key under `gateway/certs/`, then
set `RIVLEN_BIND=0.0.0.0`, `RIVLEN_TLS_CERT=/certs/fullchain.pem`, and
`RIVLEN_TLS_KEY=/certs/privkey.pem` in `.env`. Ensure the container's non-root
user can read both files; a host TLS reverse proxy is simpler when certificates
are restricted to root.

## Device access

The owner device can list authorizations and revoke other device tokens from
the app. Every authorized gateway request updates that device's last-access
time. The owner cannot revoke itself from the app; to reset ownership, stop the
gateway, remove its data file, and restart it. This creates a new gateway ID
and invalidates all existing device tokens.

The data file is created with owner-only filesystem permissions. Back it up to
retain the gateway ID and device registry. Pairing passwords and Node-RED
credentials are read from the process environment and are not written into the
data file.
