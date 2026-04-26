# HTTPS for `signalk.rpi.cb84.io` — how it works

  ## Goal
  Reach a Pi-hosted service over HTTPS from devices on the home LAN (incl. a smartwatch with no Tailscale client), with auto-renewing Let's Encrypt certs.

  ## Architecture

  ```
  Browser/Watch
     |  https://signalk.rpi.public
     v
  Hetzner DNS (public)        →  192.168.0.1   (Pi LAN IP)
     |
     v
  Caddy on 192.168.0.1:443 (TLS terminator)
     |  reverse_proxy
     v
  SignalK on 127.0.0.1:3000   (plain HTTP, internal only)
  ```

  - DNS is **public**, but resolves to a **private (RFC1918) IP** — unroutable from the internet.
  - Caddy binds to the **LAN interface only** (not `0.0.0.0`), so even with an accidental port-forward it wouldn't be exposed.
  - LE certs are obtained via **DNS-01 challenge** (no inbound port 80/443 from the internet needed).

  ## Components

  | Piece | Role |
  |---|---|
  | **Hetzner DNS (Hetzner Console, project-scoped)** | Authoritative DNS for `cb84.io`. `*.rpi.cb84.io` A record → `192.168.0.1`. |
  | **Hetzner Cloud API token** | Lets Caddy create/delete `_acme-challenge` TXT records during ACME validation. |
  | **Caddy** (Debian package + `caddy-dns/hetzner@v2.0.0` plugin) | TLS termination, automatic ACME, reverse proxy. |
  | **Static LAN IP via Deco DHCP reservation** | Stable `192.168.0.1` regardless of lease churn. |
  | **SignalK** | The actual app, plain HTTP on `:3000`. |

  ## Caddyfile (`/etc/caddy/Caddyfile`)

  ```caddyfile
  {
      email <your-email>
  }

  (common_tls) {
      bind 192.168.0.1
      tls {
          dns hetzner {env.HETZNER_API_TOKEN}
          propagation_delay 30s
          resolvers 1.1.1.1 8.8.8.8
      }
  }

  signalk.rpi.public {
      import common_tls
      reverse_proxy localhost:3000
  }
  ```

  Add a new service = add a new site block + import `common_tls`. No new DNS record required (covered by the wildcard A).

  ## Token storage

  - `/etc/caddy/caddy.env` (mode `0600`, group `caddy`):
    ```
    HETZNER_API_TOKEN=<token>
    ```
  - Loaded via systemd drop-in `/etc/systemd/system/caddy.service.d/override.conf`:
    ```
    [Service]
    EnvironmentFile=/etc/caddy/caddy.env
    ExecStart=
    ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile
    ```
    The empty `ExecStart=` clears the inherited line; the replacement drops the package's `--environ` flag (which would dump `HETZNER_API_TOKEN=...` to the
  systemd journal at every start).

  ## Renewal

  Fully automatic. Caddy renews ~30 days before expiry using the same DNS-01 flow. No cron, no certbot timers. Renewal failures will email the address in the
  global `email` directive.

  ## Install summary

  ```bash
  # Caddy + Hetzner DNS plugin
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | sudo tee /etc/apt/sources.list.d/caddy-stable.list
  sudo apt update && sudo apt install -y caddy
  sudo caddy add-package github.com/caddy-dns/hetzner@v2.0.0

  # Token + systemd drop-in (see above)
  sudo install -m 600 -o root -g caddy /dev/null /etc/caddy/caddy.env
  # write HETZNER_API_TOKEN=... into the file
  sudo systemctl edit caddy   # add EnvironmentFile + ExecStart override

  # Apply Caddyfile
  sudo caddy validate --config /etc/caddy/Caddyfile
  sudo systemctl restart caddy
  ```

  ## Gotchas worth remembering

  - **Hetzner API migration (May 2026):** the legacy `dns.hetzner.com` API is being retired. Use the new project-scoped Hetzner Cloud API token
  (`api.hetzner.cloud/v1`) and `caddy-dns/hetzner@v2.0.0` (uses `libdns/hetzner/v2`).
  - **Don't use the package's stock `caddy.service`** without overriding `ExecStart` — its `--environ` flag leaks every env var (including `HETZNER_API_TOKEN`)
   into the journal at startup.
  - **Coexistence with Tailscale `:443`:** fine, because Tailscale binds the tailscale interface IP (`100.93.69.x`) and Caddy binds only the LAN IP. The `bind`
   directive is essential.
  - **DNS rebinding protection:** check before assuming. Deco doesn't strip private answers from public DNS by default; some routers (Fritz!Box, pfSense,
  AdGuard) do. If they do, run `dnsmasq` on the Pi and point the LAN's DHCP DNS at it.