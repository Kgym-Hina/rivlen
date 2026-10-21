# Rivlen

Rivlen is a Flutter mobile editor for existing Node-RED instances. It edits the
runtime's Flow JSON through the Admin API and does not run a separate automation
engine. The optional [Rivlen Gateway](gateway/README.md) lets the phone reach a
private Node-RED instance through a separately exposed, device-authenticated
port.

## Run

```sh
flutter pub get
flutter run
```

The project targets Android and iOS. A Node-RED address can include a reverse
proxy path, for example `https://automation.example.com/nodered`.

## Connection and deployment

- Reads and deploys through `GET /flows` and `POST /flows`.
- Supports unauthenticated instances, Node-RED username/password login, and a
  manually supplied Bearer token.
- Supports pairing to Rivlen Gateway by scanning a QR code or importing its
  short-lived pairing file. The first paired phone can review authorized
  devices, revoke access, and view each device's last access time.
- Uses the v2 API revision when available. A revision conflict blocks deployment;
  the local draft can be copied before loading the instance's latest version.
- For older v1 APIs without revision support, checks that the instance Flow has
  not changed immediately before deployment.
- Node attributes and unknown fields are preserved. The palette includes common
  built-in nodes; unsupported node editors can still be adjusted through the
  full node JSON editor.

Connection profiles are saved in the app's local preferences; passwords and
gateway tokens are stored in the platform secure storage. The connection screen
accepts both HTTP (useful for private LAN instances) and HTTPS addresses.
Gateway pairing requires the custom password set on the gateway; the password
is not included in pairing QR codes or files.

## Design source

[Rivlen｜移动端 Flow 编辑器·交互设计](https://app.notion.com/p/4005e5c0e4c0814793a2dd632254ea23)

## Gateway

The Go gateway and its deployment instructions are in [`gateway/`](gateway/).
Node-RED remains private; only the `GET /flows` and `POST /flows` Admin API
operations are proxied to authorized Rivlen devices. See the gateway guide for
password, TLS, reverse-proxy, and Docker configuration.
