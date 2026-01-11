# Poste.io + Traefik cert sync

This repo provides a simple script to copy a Let’s Encrypt certificate issued by Traefik (`acme.json`) into a Poste.io container so SMTP/IMAP/POP3 present a valid TLS certificate (e.g. `mail.hubbr.org`).

## Why
Traefik renews certificates automatically for HTTP(S). Mail protocols are handled directly by Poste.io, so it needs the same certificate files under `/data/ssl`.

## Requirements
- Docker
- A Traefik container with an ACME resolver writing to `/acme.json`
- A Poste.io container using `/data` volume (default for `analogic/poste.io`)
- A valid certificate already issued by Traefik for your mail host (e.g. `mail.hubbr.org`)

## Usage
1) Copy `traefik-cert-sync.sh` to your server.
2) Edit the top of the script and set:
   - `DOMAIN` (e.g. `mail.hubbr.org`)
   - `TRAEFIK_CONTAINER` (default: `traefik`)
   - `POSTE_CONTAINER` (default: `poste`)
3) Run once to test:

```bash
./traefik-cert-sync.sh
```

If the certificate changed, it will copy `server.crt`, `server.key`, and `ca.crt` into `/data/ssl` inside the Poste.io container and restart it.

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

## License
MIT
