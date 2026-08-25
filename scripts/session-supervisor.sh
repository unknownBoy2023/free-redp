#!/usr/bin/env bash
# ============================================================================
#  session-supervisor.sh — self-healing supervisor for the browser desktop.
# ----------------------------------------------------------------------------
#  Keeps four components alive and re-establishes them if any one dies:
#    Xvfb :0           (virtual display)
#    xfce4-session     (the desktop)
#    x11vnc :5900      (VNC server)
#    websockify :6080  (serves noVNC over the web)
#    cloudflared       (public https://...trycloudflare.com tunnel)
#
#  Responsibilities:
#   1. Detect + relaunch any crashed component.
#   2. Re-read the rotating public URL whenever cloudflared changes it and
#      write it to $URL_FILE so a client step can read it at any time.
#   3. Emit a timestamped heartbeat + resource snapshot.
#
#  Usage:  bash scripts/session-supervisor.sh  <url_file>
#    <url_file>  where the current public URL is written.
# ============================================================================
set -uo pipefail

URL_FILE="${1:?usage: bash scripts/session-supervisor.sh <url_file>}"
VNC_PORT=5900
WEB_PORT=6080
POLL_SECS=${POLL_SECS:-10}
SESSION_TTL_MIN=${SESSION_TTL_MIN:-0}   # 0 = run until runner cap; else stop after N min
HOME_DIR="${HOME:-/home/$(whoami)}"
CF_LOG="$HOME_DIR/cloudflared.log"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"

export DISPLAY="${DISPLAY:-:0}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

lsof_port() { ss -ltn 2>/dev/null | grep -q ":$1 " || netstat -ltn 2>/dev/null | grep -q ":$1 "; }

ensure_xvfb() {
  if ! pgrep -f "Xvfb :0" >/dev/null 2>&1 && ! pgrep -af "Xvfb" | grep -q ":0"; then
    echo "[$(date -u +%FT%TZ)] Xvfb down — restarting"
    nohup Xvfb :0 -screen 0 "${SCREEN:-1280x800x24}" -nolisten tcp >/tmp/xvfb.log 2>&1 &
    disown || true
    sleep 2
  fi
}

ensure_xfce() {
  if ! pgrep -x xfce4-session >/dev/null 2>&1; then
    echo "[$(date -u +%FT%TZ)] desktop session down — restarting"
    nohup xfce4-session >/tmp/xfce.log 2>&1 &
    disown || true
    sleep 2
  fi
}

ensure_x11vnc() {
  if ! lsof_port $VNC_PORT; then
    echo "[$(date -u +%FT%TZ)] x11vnc not on :$VNC_PORT — restarting"
    pkill -f "x11vnc" 2>/dev/null || true
    sleep 1
    local PASS
    PASS=$(grep "^PASS=" /tmp/creds.txt 2>/dev/null | cut -d= -f2)
    nohup x11vnc -display :0 -passwd "$PASS" -forever -shared -bg -quiet -rfbport $VNC_PORT >/tmp/x11vnc.log 2>&1 &
    disown || true
    sleep 3
  fi
}

ensure_websockify() {
  if ! lsof_port $WEB_PORT; then
    echo "[$(date -u +%FT%TZ)] websockify not on :$WEB_PORT — restarting"
    pkill -f "websockify" 2>/dev/null || true
    sleep 1
    nohup websockify --web=/usr/share/novnc $WEB_PORT localhost:$VNC_PORT >/tmp/novnc.log 2>&1 &
    disown || true
    sleep 3
  fi
}

read_public_url() {
  grep -oE "https://[a-zA-Z0-9-]+\.trycloudflare\.com" "$CF_LOG" 2>/dev/null | tail -1
}

ensure_cloudflared() {
  # Relaunch if the tunnel process died or no URL is registered in the log.
  if ! pgrep -f "cloudflared tunnel --url" >/dev/null 2>&1; then
    echo "[$(date -u +%FT%TZ)] cloudflared down — re-establishing tunnel"
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    sleep 1
    nohup "$HOME_DIR/cloudflared" tunnel --url "http://localhost:$WEB_PORT" --no-autoupdate \
      >"$CF_LOG" 2>&1 &
    disown || true
    sleep 6
  fi
  local URL
  URL=$(read_public_url)
  if [ -n "$URL" ]; then
    printf '%s\n' "$URL" > "$URL_FILE"
  fi
}

echo "============================================================"
echo "  SUPERVISOR ACTIVE"
echo "  - Session TTL : ${SESSION_TTL_MIN} min (0 = until runner cap)"
echo "  - Poll        : ${POLL_SECS}s"
echo "  - URL file    : $URL_FILE"
echo "  Stopping with Ctrl+C / kill."
echo "============================================================"

trap 'echo "[$(date -u +%FT%TZ)] supervisor stopped"; exit 0' INT TERM

START=$(date +%s)
while true; do
  ensure_xvfb
  ensure_xfce
  ensure_x11vnc
  ensure_websockify
  ensure_cloudflared

  URL=$(cat "$URL_FILE" 2>/dev/null || true)
  LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}' || echo "n/a")
  MEM=$(free -h 2>/dev/null | awk '/^Mem:/{print $3"/"$2}' || echo "n/a")
  echo "[$(date -u +%FT%TZ)] heartbeat — url:${URL:-<pending>} load:${LOAD} mem:${MEM}"

  # Optional auto-stop after a fixed TTL (if configured).
  if [ "$SESSION_TTL_MIN" -gt 0 ]; then
    ELAPSED=$(( $(date +%s) - START ))
    if [ "$ELAPSED" -ge $(( SESSION_TTL_MIN * 60 )) ]; then
      echo "[$(date -u +%FT%TZ)] TTL reached (${SESSION_TTL_MIN} min) — stopping"
      exit 0
    fi
  fi

  sleep "$POLL_SECS"
done
