#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Checks this connection's current public IPv4 against the one LiveKit is
# currently advertising (deploy/kubernetes/32-livekit.yaml's node_ip, stored
# in the livekit-node-ip ConfigMap so this script can patch it cleanly). If
# the ISP has handed out a new address, updates the ConfigMap and restarts
# the livekit Deployment so it starts advertising the new one -- without
# this, voice/video breaks silently the next time the address rotates,
# since LiveKit doesn't support a dynamic-DNS hostname for node_ip.
#
# Meant to run periodically (see the crontab line below), not continuously.
# Idempotent and quiet when nothing changed: only writes to the log when it
# actually updates something, so cron mail / log noise stays minimal.
#
# One-time setup to actually schedule this:
#   crontab -e
#   */5 * * * * /usr/bin/env bash /mnt/c/Users/pietr/Documents/Programming/fluxer/deploy/kubernetes/livekit-ip-watch.sh >> /tmp/livekit-ip-watch.log 2>&1
# (cron.service is already enabled/running on this WSL distro via systemd,
# unlike most WSL setups -- confirmed with `systemctl status cron`. If that
# ever stops being true, this script is just as useless as tunnel.sh /
# livekit_relay.py are without something re-launching them, so it's worth
# checking `systemctl status cron` first if voice mysteriously breaks after
# an ISP IP change and this log hasn't been touched in a while.)
set -euo pipefail

# Full paths, not bare command names: cron runs jobs with a minimal PATH
# that doesn't reliably include /usr/local/bin.
KUBECTL="/usr/local/bin/kubectl"
CURL="/usr/bin/curl"

NAMESPACE="wallow"
CONFIGMAP="livekit-node-ip"
KEY="LIVEKIT_NODE_IP"

current_ip="$("$KUBECTL" get configmap "$CONFIGMAP" -n "$NAMESPACE" -o jsonpath="{.data.$KEY}" 2>/dev/null || true)"
detected_ip="$("$CURL" -s -4 --max-time 5 https://ifconfig.me || true)"

if [ -z "$detected_ip" ]; then
	echo "$(date -Iseconds) could not detect public IP this run, skipping"
	exit 0
fi

if [ "$current_ip" = "$detected_ip" ]; then
	exit 0
fi

echo "$(date -Iseconds) public IP changed: '$current_ip' -> '$detected_ip', updating LiveKit"

"$KUBECTL" patch configmap "$CONFIGMAP" -n "$NAMESPACE" --type=merge -p "{\"data\":{\"$KEY\":\"$detected_ip\"}}"
"$KUBECTL" rollout restart deployment livekit -n "$NAMESPACE"
"$KUBECTL" rollout status deployment livekit -n "$NAMESPACE" --timeout=60s

echo "$(date -Iseconds) LiveKit restarted with node_ip=$detected_ip"
echo "$(date -Iseconds) REMINDER: your router's port-forward rules (TCP 7881, UDP 7882) point at a LAN IP, not the public one, so they don't need updating for this -- but if the public IP change came with a new LAN IP for this machine too (DHCP lease renewal), check those forward rules still point at the right target."
