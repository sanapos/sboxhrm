#!/bin/bash
# Make Super Admin "Dọn host" able to write a request and have the host run it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p /opt/zkteco/gc /opt/zkteco/bin
install -m 755 "$ROOT/sbox-host-gc.sh" /opt/zkteco/bin/sbox-host-gc.sh
chown 1654:1654 /opt/zkteco/gc
chmod 775 /opt/zkteco/gc
cat > /etc/cron.d/sbox-host-gc <<'EOF'
# Super Admin writes /opt/zkteco/gc/request; this runs the cleanup within a minute.
* * * * * root test -f /opt/zkteco/gc/request && /opt/zkteco/bin/sbox-host-gc.sh >> /opt/zkteco/gc/cron.log 2>&1
EOF
chmod 644 /etc/cron.d/sbox-host-gc
echo "HOST_GC_INSTALLED"
