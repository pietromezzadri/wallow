#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Checks that everything voice/video and public access depend on is still
# running, and restarts whatever isn't. Meant to run periodically via cron
# (see the crontab line below), not continuously -- none of these pieces
# are supervised by anything (systemd, a process manager) on their own, so
# a WSL restart (reboot, Windows update, `wsl --shutdown`, sleep/wake) kills
# all of them silently, with no error until someone notices the site is
# down. This has happened repeatedly during initial setup; this script
# exists so it stops requiring a manual restart every time.
#
# Order matters: minikube first (everything else depends on the cluster
# being up), then the two port-forward tunnels (deploy/kubernetes/
# tunnel.sh -- HTTP for the Cloudflare Tunnel origin, the other for
# LiveKit's TCP fallback candidate), then the WSL->minikube media relay
# (deploy/kubernetes/livekit_relay.py). cloudflared itself
# (/home/polenta/services/cloudflared) is intentionally NOT restarted here
# -- it's shared infrastructure for the user's other self-hosted apps, out
# of scope for this project's watchdog.
#
# One-time setup:
#   crontab -e
#   */5 * * * * /usr/bin/env bash /mnt/c/Users/pietr/Documents/Programming/fluxer/deploy/kubernetes/watchdog.sh >> /tmp/wallow-watchdog.log 2>&1
set -uo pipefail

KUBECTL="/usr/local/bin/kubectl"
MINIKUBE="/usr/local/bin/minikube"
REPO_DIR="/mnt/c/Users/pietr/Documents/Programming/fluxer"
RELAY_PIDFILE="/tmp/livekit_relay.pid"
RELAY_LOG="/tmp/livekit_relay.log"

log() { echo "$(date -Iseconds) $*"; }

# --- minikube ---
if ! "$MINIKUBE" status >/dev/null 2>&1; then
	log "minikube is down, starting it (this can take a minute or two)..."
	"$MINIKUBE" start >>/tmp/wallow-watchdog.log 2>&1
	log "minikube start finished"
fi

# --- kubectl port-forward tunnels (deploy/kubernetes/tunnel.sh) ---
need_tunnel_restart=false
for name in http livekit-rtc-tcp; do
	pidfile="/tmp/wallow-tunnel/$name.pid"
	if [ ! -f "$pidfile" ] || ! kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
		need_tunnel_restart=true
	fi
done
if [ "$need_tunnel_restart" = true ]; then
	log "one or both port-forward tunnels are down, restarting via tunnel.sh"
	bash "$REPO_DIR/deploy/kubernetes/tunnel.sh" >>/tmp/wallow-watchdog.log 2>&1
fi

# --- livekit_relay.py (WSL -> minikube's internal Docker bridge for LiveKit's TCP/UDP ports) ---
relay_pid="$(cat "$RELAY_PIDFILE" 2>/dev/null || true)"
if [ -z "$relay_pid" ] || ! kill -0 "$relay_pid" 2>/dev/null; then
	log "livekit_relay.py is down, restarting it"
	nohup python3 "$REPO_DIR/deploy/kubernetes/livekit_relay.py" >"$RELAY_LOG" 2>&1 &
	echo $! >"$RELAY_PIDFILE"
	disown
	log "livekit_relay.py restarted (pid $(cat "$RELAY_PIDFILE"))"
fi
