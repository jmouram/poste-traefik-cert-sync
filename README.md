# Poste.io + Traefik cert sync

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

This repo provides a simple script to copy a Let’s Encrypt certificate issued by Traefik (`acme.json`) into a Poste.io container so SMTP/IMAP/POP3 present a valid TLS certificate (e.g. `mail.hubbr.org`).

## Why
Traefik renews certificates automatically for HTTP(S). Mail protocols are handled directly by Poste.io, so it needs the same certificate files under `/data/ssl`.

## Requirements
- Docker
- A Traefik container with an ACME resolver writing to `/acme.json`
- A Poste.io container using `/data` volume (default for `analogic/poste.io`)
- A valid certificate already issued by Traefik for your mail host (e.g. `mail.hubbr.org`)

## Quick start
1) Copy `traefik-cert-sync.sh` to your server and make it executable:

```bash
chmod +x /opt/poste/traefik-cert-sync.sh
```

2) Edit the top of the script and set:
   - `DOMAIN` (e.g. `mail.hubbr.org`)
   - `TRAEFIK_CONTAINER` (default: `traefik`)
   - `POSTE_CONTAINER` (default: `poste`)

3) Run once to test:

```bash
/opt/poste/traefik-cert-sync.sh
```

4) Add a cron job (daily at 03:00 local time):

```cron
CRON_TZ=America/Fortaleza
0 3 * * * /opt/poste/traefik-cert-sync.sh >> /opt/poste/traefik-cert-sync.log 2>&1
```

If the certificate changed, it will copy `server.crt`, `server.key`, and `ca.crt` into `/data/ssl` inside the Poste.io container and restart it.

## How it works
- Reads `acme.json` from the Traefik container.
- Finds the certificate for your mail hostname.
- Writes `server.crt`, `ca.crt`, and `server.key` into Poste.io `/data/ssl`.
- Restarts Poste.io only when the certificate changes.

## Docker Compose example
See `docker-compose.example.yml`.

## Cron example
Run daily at 03:00 (America/Fortaleza):

```cron
CRON_TZ=America/Fortaleza
0 3 * * * /opt/poste/traefik-cert-sync.sh >> /opt/poste/traefik-cert-sync.log 2>&1
```

## Notes
- Traefik must already have a certificate for the mail host. Ensure you have an HTTPS router for `mail.hubbr.org` so Traefik can solve the ACME challenge.
- The script only restarts Poste.io when the cert changes.
- The private key is copied into Poste.io, so protect access to the host and `/data/ssl`.

## Troubleshooting
- If the script says "No certificate found", confirm the domain is present in Traefik `acme.json` and that Traefik has issued a cert for it.
- If Gmail complains about TLS, verify the SMTP host is the same as the cert CN/SAN (e.g. `mail.hubbr.org`).

## Verify SMTP certificate
Check the cert served on port 587 (STARTTLS):

```bash
openssl s_client -connect 127.0.0.1:587 -starttls smtp -servername mail.hubbr.org </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

## License
MIT. See [LICENSE](LICENSE).
