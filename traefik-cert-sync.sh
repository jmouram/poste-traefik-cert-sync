#!/usr/bin/env bash
set -euo pipefail

DOMAIN="mail.hubbr.org"
TRAEFIK_CONTAINER="traefik"
POSTE_CONTAINER="poste"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Read ACME data from Traefik
if ! docker exec "$TRAEFIK_CONTAINER" cat /acme.json > "$TMPDIR/acme.json"; then
  echo "Failed to read /acme.json from $TRAEFIK_CONTAINER" >&2
  exit 1
fi

python3 - "$DOMAIN" "$TMPDIR" <<'PY'
import sys, json, base64, os, re

domain = sys.argv[1]
tmpdir = sys.argv[2]

with open(os.path.join(tmpdir, "acme.json"), "r") as f:
    data = json.load(f)

certs = data.get("letsencrypt", {}).get("Certificates", [])
match = None
for c in certs:
    dom = c.get("domain", {})
    main = dom.get("main")
    sans = dom.get("sans") or []
    if domain == main or domain in sans:
        match = c
        break

if not match:
    print(f"No certificate found for {domain}", file=sys.stderr)
    sys.exit(2)

fullchain = base64.b64decode(match["certificate"])
key = base64.b64decode(match["key"])

with open(os.path.join(tmpdir, "fullchain.pem"), "wb") as f:
    f.write(fullchain)

with open(os.path.join(tmpdir, "privkey.pem"), "wb") as f:
    f.write(key)

pem = open(os.path.join(tmpdir, "fullchain.pem"), "r").read()
cert_list = re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----\n?", pem, re.S)
if not cert_list:
    print("No PEM certificates found in fullchain", file=sys.stderr)
    sys.exit(3)

with open(os.path.join(tmpdir, "server.crt"), "w") as f:
    f.write(cert_list[0])

with open(os.path.join(tmpdir, "ca.crt"), "w") as f:
    f.write("".join(cert_list[1:]) or cert_list[0])

with open(os.path.join(tmpdir, "server.key"), "wb") as f:
    f.write(key)
PY

new_server_hash=$(sha256sum "$TMPDIR/server.crt" | awk '{print $1}')
new_ca_hash=$(sha256sum "$TMPDIR/ca.crt" | awk '{print $1}')
new_key_hash=$(sha256sum "$TMPDIR/server.key" | awk '{print $1}')

get_hash() {
  docker exec "$POSTE_CONTAINER" sh -c "sha256sum /data/ssl/$1 2>/dev/null | awk '{print \$1}'" || true
}

current_server_hash=$(get_hash server.crt)
current_ca_hash=$(get_hash ca.crt)
current_key_hash=$(get_hash server.key)

changed=0
if [ "$new_server_hash" != "$current_server_hash" ]; then
  changed=1
fi
if [ "$new_ca_hash" != "$current_ca_hash" ]; then
  changed=1
fi
if [ "$new_key_hash" != "$current_key_hash" ]; then
  changed=1
fi

if [ "$changed" -eq 0 ]; then
  echo "Certificate unchanged for $DOMAIN"
  exit 0
fi

# Copy updated certs into Poste volume
if ! docker cp "$TMPDIR/server.crt" "$POSTE_CONTAINER:/data/ssl/server.crt"; then
  echo "Failed to copy server.crt into $POSTE_CONTAINER" >&2
  exit 1
fi
if ! docker cp "$TMPDIR/ca.crt" "$POSTE_CONTAINER:/data/ssl/ca.crt"; then
  echo "Failed to copy ca.crt into $POSTE_CONTAINER" >&2
  exit 1
fi
if ! docker cp "$TMPDIR/server.key" "$POSTE_CONTAINER:/data/ssl/server.key"; then
  echo "Failed to copy server.key into $POSTE_CONTAINER" >&2
  exit 1
fi

docker exec "$POSTE_CONTAINER" sh -c "chmod 644 /data/ssl/server.crt /data/ssl/ca.crt && chmod 600 /data/ssl/server.key"

docker restart "$POSTE_CONTAINER" >/dev/null

echo "Certificate updated for $DOMAIN and Poste restarted"
