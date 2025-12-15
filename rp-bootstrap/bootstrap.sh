#!/usr/bin/env sh
set -euo pipefail
# tools needed by the prep script
apk add --no-cache bash git sed grep coreutils gettext python3
# 1) Clone examples + lib
git clone --depth 1 https://github.com/italia/spid-cie-oidc-django.git /work
cd /work
# 2) Patch docker-prepare.sh to use your HTTPS hosts
: "${TA_BASE:=http://ta-hp6cp1fk91.192.168.1.5.nip.io}"
: "${RP_BASE:=http://192.168.1.5:8001}"
: "${OP_BASE:=http://op-hp6cp1fk91.192.168.1.5.nip.io}"
: "${WTA_BASE:=http://wta-acme.migcloud.bluetensor.ai}"
sed -i \
  -e "s|^export SUB_AT=.*$|export SUB_AT='s,http://127.0.0.1:8000,${TA_BASE},g'|" \
  -e "s|^export SUB_RP=.*$|export SUB_RP='s,http://127.0.0.1:8001,${RP_BASE},g'|" \
  -e "s|^export SUB_OP=.*$|export SUB_OP='s,http://127.0.0.1:8002,${OP_BASE},g'|" \
  -e "s|^export SUB_WTA=.*$|export SUB_WTA='s,http://127.0.0.1:8000,${WTA_BASE},g'|" \
  docker-prepare.sh
# 3) Prepare docker examples
bash docker-prepare.sh
# 4) Ensure proxy/HTTPS settings in RP settingslocal.py (idempotent)
SLP="/work/examples-docker/relying_party/relying_party/settingslocal.py"
[ -f "$SLP" ] || cp /work/examples/relying_party/relying_party/settingslocal.py.example "$SLP"
grep -q '^import os$' "$SLP" || printf '%s\n' 'import os' >> "$SLP"
grep -q '^USE_X_FORWARDED_HOST' "$SLP" || printf '%s\n' 'USE_X_FORWARDED_HOST = True' >> "$SLP"
grep -q '^SECURE_PROXY_SSL_HEADER' "$SLP" || printf '%s\n' 'SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO","http")' >> "$SLP"
grep -q 'DJANGO_ALLOWED_HOSTS' "$SLP" || printf '%s\n' 'ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS","*").split(",")' >> "$SLP"
grep -q '^from aiohttp import ClientTimeout' "$SLP" || printf '%s\n' 'from aiohttp import ClientTimeout' >> "$SLP"
printf '%s\n' 'HTTPC_PARAMS = {"connection": {"ssl": (os.environ.get("HTTPC_SSL",False))}, "session": {"timeout": ClientTimeout(total=float(os.environ.get("HTTPC_TIMEOUT_TOTAL","30")))}}' >> "$SLP"
# 5) Copy prepared examples + override into shared volumes
rm -rf /opt/examples/* /opt/examples/.* 2>/dev/null || true
mkdir -p /opt/examples
cp -a /work/examples-docker/. /opt/examples/
mkdir -p /opt/override
rm -rf /opt/override/spid_cie_oidc
cp -a /work/spid_cie_oidc /opt/override/
mkdir -p /opt/examples/relying_party/logs