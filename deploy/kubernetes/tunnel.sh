#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Starts (or restarts) the two `kubectl port-forward` tunnels this
# deployment relies on to be reachable from Windows:
#
#   - ingress-nginx-controller:80 -> 127.0.0.1:8090 (in WSL)
#     Windows then reaches this via `netsh interface portproxy` mapping
#     0.0.0.0:80 -> 127.0.0.1:8090 (see the one-time setup note below).
#
#   - livekit's rtc-tcp port 7881 -> 127.0.0.1:7881 (in WSL)
#     Needed for voice/video's ICE-TCP fallback candidate (see the long
#     comment in 32-livekit.yaml -- raw UDP media doesn't work in this
#     WSL2 + minikube docker-driver setup, only this TCP path does).
#     Windows reaches this the same way, via its own netsh portproxy rule
#     for port 7881 (also one-time; see below).
#
# Both `kubectl port-forward` processes die whenever WSL restarts (which
# happens more often than you'd expect -- Windows/WSL idle timeouts,
# `wsl --shutdown`, reboots), so re-run this script any time voice/video or
# the web app stop responding after such a restart. It's idempotent: safe
# to re-run any time, it kills its own previously-started tunnels first.
#
# One-time Windows-side setup (run once per Windows install, survives WSL
# restarts -- only re-run if you change these port numbers):
#   netsh interface portproxy add v4tov4 listenport=80 listenaddress=0.0.0.0 connectport=8090 connectaddress=127.0.0.1
#   netsh interface portproxy add v4tov4 listenport=7881 listenaddress=0.0.0.0 connectport=7881 connectaddress=127.0.0.1
set -euo pipefail

PIDFILE_DIR="/tmp/wallow-tunnel"
mkdir -p "$PIDFILE_DIR"

stop_if_running() {
	local name="$1"
	local pidfile="$PIDFILE_DIR/$name.pid"
	if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
		kill "$(cat "$pidfile")" 2>/dev/null || true
	fi
	rm -f "$pidfile"
}

start_forward() {
	local name="$1"
	shift
	stop_if_running "$name"
	nohup kubectl "$@" >"$PIDFILE_DIR/$name.log" 2>&1 &
	echo $! >"$PIDFILE_DIR/$name.pid"
	echo "started $name (pid $(cat "$PIDFILE_DIR/$name.pid")), logging to $PIDFILE_DIR/$name.log"
}

start_forward http port-forward -n ingress-nginx svc/ingress-nginx-controller 8090:80
start_forward livekit-rtc-tcp port-forward -n wallow deploy/livekit 7881:7881

sleep 2
echo "--- tunnel status ---"
for name in http livekit-rtc-tcp; do
	pidfile="$PIDFILE_DIR/$name.pid"
	if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
		echo "$name: running (pid $(cat "$pidfile"))"
	else
		echo "$name: FAILED to start -- check $PIDFILE_DIR/$name.log"
	fi
done
