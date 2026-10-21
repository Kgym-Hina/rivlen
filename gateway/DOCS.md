# Rivlen Gateway

Rivlen Gateway gives authorized Rivlen devices access to an existing Node-RED instance. Node-RED stays on its existing network and port; the gateway exposes only its own pairing page and authenticated API.

## Install

Add `https://github.com/Kgym-Hina/rivlen` as an Apps repository, install **Rivlen Gateway**, then open its **Configuration** tab before starting it. The first installation pulls a prebuilt multi-architecture image for Home Assistant OS devices on amd64 or aarch64.

## Configure

- **Node-RED URL:** Use the direct address and port that the gateway can reach. `http://homeassistant:1880` is a starting value when Node-RED exposes port 1880 through Home Assistant. If the installed Node-RED app uses another port or host, enter that address. Do not use its Ingress URL.
- **Node-RED authentication:** Select `none` when Node-RED has no authentication; `admin` for a Node-RED Admin API username and password; `basic` for the Home Assistant username and password protecting the Node-RED app's direct port; or `token` for a Node-RED Admin API Bearer token.
- **Username / password:** Fill these only for `admin` or `basic`. A local-only Home Assistant account can be used with `basic` when the gateway connects over the local Home Assistant network. A Home Assistant long-lived access token is not a substitute for this username and password.
- **Node-RED Admin token:** Fill this only for `token`; leave the username and password empty.
- **Pairing password:** Set a separate password with at least 12 characters. Do not reuse a Node-RED or Home Assistant login password.
- **Public gateway URL:** Leave empty for local network use. Set a fixed HTTPS URL only when a reverse proxy or tunnel sends traffic to the gateway and supports WebSockets.

Save the configuration and start the App. It listens on TCP 8787 by default. The **Open Web UI** button opens the pairing page. The port can be changed in the App's Network settings if 8787 is already in use.

## Pair Rivlen

1. Open the gateway page and enter the pairing password.
2. Select **Generate pairing QR code**.
3. In Rivlen, choose **Connect new instance → Pair through gateway**, scan the QR code, and enter the same pairing password.
4. Name the device and finish pairing. The first paired device becomes the owner.

Pairing invitations can be used once and expire after ten minutes. If scanning is unavailable, download the pairing file from the gateway page and import it in Rivlen.

## Access and data

The default port is intended for private network access. For public access, use HTTPS at a reverse proxy and set **Public gateway URL** to the final HTTPS address. Keep Node-RED's port private; forward only the gateway. The gateway requires WebSocket forwarding for Node-RED Debug.

The Supervisor keeps `/data/gateway.json` in this App's persistent data and includes it in Home Assistant backups. Preserve the App data when updating or moving Home Assistant to retain its gateway ID and paired devices. `/healthz` only confirms that the gateway process responds; complete pairing and load a Flow to verify Node-RED access.
