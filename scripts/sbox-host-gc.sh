#!/bin/bash
# SBOX host garbage collection — only unused deploy leftovers, dangling
# Docker images, build cache, and journal. Never touches running containers,
# named volumes (postgres/redis/uploads), secrets, or compose/.env.
set -u
GC_DIR="${SBOX_GC_DIR:-/opt/zkteco/gc}"
mkdir -p "$GC_DIR"
STATUS="$GC_DIR/status.json"
LOG="$GC_DIR/last.log"
: > "$LOG"
freed_kb=0
items=""

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOG"; }

kb_of() { du -sk "$1" 2>/dev/null | awk '{print $1}'; }

rm_path() {
  local p="$1"
  [ -e "$p" ] || return 0
  local kb
  kb=$(kb_of "$p")
  rm -rf "$p"
  if [ ! -e "$p" ]; then
    freed_kb=$((freed_kb + ${kb:-0}))
    items="${items}\"${p}\","
    log "removed $p (${kb:-0} KB)"
  else
    log "KEEP/FAIL $p"
  fi
}

log "SBOX host GC start"

# --- Docker: dangling images + build cache (no volumes, no running) ---
if command -v docker >/dev/null 2>&1; then
  before=$(df -Pk / | awk 'NR==2{print $3}')
  docker image prune -f >>"$LOG" 2>&1 || true
  # Unused named images that are NOT currently running
  for img in \
    zktecoadms.api:latest \
    zkteco_api:latest \
    zkteco-api:latest \
    ghcr.io/thuylienphat-coder/zktecoadms-api:latest \
    ghcr.io/thuylienphat-coder/zktecoadms-flutter:latest \
    python:3.11-slim \
    curlimages/curl:latest \
    alpine:latest
  do
    if docker ps --format '{{.Image}}' | grep -qx "$img"; then
      log "skip running image $img"
      continue
    fi
    docker image rm -f "$img" >>"$LOG" 2>&1 || true
  done
  docker builder prune -af >>"$LOG" 2>&1 || true
  after=$(df -Pk / | awk 'NR==2{print $3}')
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" -gt "$after" ]; then
    freed_kb=$((freed_kb + before - after))
  fi
  log "docker prune done"
fi

# --- journal ---
if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-size=300M >>"$LOG" 2>&1 || true
  log "journal vacuum 300M"
fi

# --- /tmp leftovers ---
rm_path /tmp/venv
rm_path /tmp/buffalo_l
rm_path /tmp/buffalo_l.zip
rm_path /tmp/publish
rm_path /tmp/web_update
rm_path /tmp/landing_imgs

# --- /root deploy leftovers (keep .ssh / current small ops files) ---
rm_path /root/publish_out
rm_path /root/api_publish
rm_path /root/publish_api
rm_path /root/api_src
rm_path /root/web
rm_path /root/web_build_new
rm_path /root/web_build3
rm_path /root/web_build2
rm_path /root/web_new
rm_path /root/api_src.zip
rm_path /root/api.tar.gz
rm_path /root/api_publish.tar.gz
rm_path /root/publish_api.tar.gz
rm_path /root/api_src.tar
rm_path /root/web_build.zip
rm_path /root/web_build2.zip
rm_path /root/web_build3.zip
rm_path /root/web_dist.zip
rm_path /root/web_update.zip
rm_path /root/flutter_web_test.tar.gz
rm_path /root/dlls_patch.tar.gz

# --- /opt/zkteco leftovers (keep compose, env, secrets, models, bin, gc) ---
if [ -d /opt/zkteco ]; then
  for p in \
    /opt/zkteco/api_src \
    /opt/zkteco/src_new \
    /opt/zkteco/api_build \
    /opt/zkteco/publish_output \
    /opt/zkteco/src \
    /opt/zkteco/src_build \
    /opt/zkteco/api-app \
    /opt/zkteco/wwwroot_backup \
    /opt/zkteco/flutter_web \
    /opt/zkteco/flutter_web_fixed \
    /opt/zkteco/flutter_web_build \
    /opt/zkteco/flutter_build \
    /opt/zkteco/web \
    /opt/zkteco/ZKTecoADMS.Api \
    /opt/zkteco/ZKTecoADMS.Infrastructure \
    /opt/zkteco/ZKTecoADMS.Application \
    /opt/zkteco/ZKTecoADMS.Domain \
    /opt/zkteco/src.zip \
    /opt/zkteco/deploy_backend.zip \
    /opt/zkteco/src_deploy.zip \
    /opt/zkteco/app-debug.apk
  do
    rm_path "$p"
  done
fi

items="${items%,}"
used=$(df -Pk / | awk 'NR==2{print $3}')
avail=$(df -Pk / | awk 'NR==2{print $4}')
pct=$(df -Pk / | awk 'NR==2{print $5}')
cat > "$STATUS" <<EOF
{"ok":true,"ranAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","freedKb":${freed_kb},"diskUsedKb":${used},"diskAvailKb":${avail},"diskUsedPercent":"${pct}","removed":[${items}]}
EOF
rm -f "$GC_DIR/request"
log "SBOX host GC done freed_kb=$freed_kb used=$used avail=$avail"
echo "GC_DONE freed_kb=$freed_kb"
