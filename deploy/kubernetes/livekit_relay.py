#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Relays LiveKit's TCP (7881) and UDP (7882) media ports from WSL's own
# network interface (reachable from Windows/the LAN thanks to WSL2 mirrored
# networking, and from a router port-forward) through to the LiveKit pod's
# hostNetwork-bound ports on minikube's internal Docker bridge network
# (192.168.49.2 by default -- confirm with `minikube ip`), which WSL itself
# can reach directly but Windows/the outside world cannot.
#
# No root required: both listen ports are >1024. Run with nohup/systemd/etc
# for it to survive terminal closure -- see deploy/kubernetes/tunnel.sh for
# the pattern this project already uses for kubectl port-forward.
import argparse
import selectors
import socket
import threading

def tcp_relay(listen_port: int, target_host: str, target_port: int) -> None:
	server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
	server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
	server.bind(("0.0.0.0", listen_port))
	server.listen(128)
	print(f"[tcp] listening on 0.0.0.0:{listen_port} -> {target_host}:{target_port}")
	while True:
		client_sock, addr = server.accept()
		threading.Thread(target=_tcp_handle_connection, args=(client_sock, target_host, target_port), daemon=True).start()

def _tcp_pipe(src: socket.socket, dst: socket.socket) -> None:
	try:
		while True:
			data = src.recv(65536)
			if not data:
				break
			dst.sendall(data)
	except OSError:
		pass
	finally:
		try:
			dst.shutdown(socket.SHUT_WR)
		except OSError:
			pass

def _tcp_handle_connection(client_sock: socket.socket, target_host: str, target_port: int) -> None:
	try:
		upstream = socket.create_connection((target_host, target_port), timeout=5)
	except OSError as error:
		print(f"[tcp] upstream connect failed: {error}")
		client_sock.close()
		return
	t1 = threading.Thread(target=_tcp_pipe, args=(client_sock, upstream), daemon=True)
	t2 = threading.Thread(target=_tcp_pipe, args=(upstream, client_sock), daemon=True)
	t1.start()
	t2.start()
	t1.join()
	t2.join()
	client_sock.close()
	upstream.close()

def udp_relay(listen_port: int, target_host: str, target_port: int, idle_timeout: float = 120.0) -> None:
	listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	listener.bind(("0.0.0.0", listen_port))
	target = (target_host, target_port)
	print(f"[udp] listening on 0.0.0.0:{listen_port} -> {target_host}:{target_port}")

	sel = selectors.DefaultSelector()
	sel.register(listener, selectors.EVENT_READ, data="listener")
	# client_addr -> upstream socket dedicated to that client (so replies route back correctly)
	sessions: dict[tuple, socket.socket] = {}
	upstream_to_client: dict[socket.socket, tuple] = {}

	def new_session(client_addr: tuple) -> socket.socket:
		upstream_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
		upstream_sock.setblocking(False)
		sessions[client_addr] = upstream_sock
		upstream_to_client[upstream_sock] = client_addr
		sel.register(upstream_sock, selectors.EVENT_READ, data="upstream")
		return upstream_sock

	while True:
		for key, _ in sel.select(timeout=idle_timeout):
			sock = key.fileobj
			if key.data == "listener":
				data, client_addr = listener.recvfrom(65536)
				upstream_sock = sessions.get(client_addr) or new_session(client_addr)
				try:
					upstream_sock.sendto(data, target)
				except OSError:
					pass
			else:
				try:
					data, _ = sock.recvfrom(65536)
				except OSError:
					continue
				client_addr = upstream_to_client.get(sock)
				if client_addr:
					listener.sendto(data, client_addr)

if __name__ == "__main__":
	parser = argparse.ArgumentParser()
	parser.add_argument("--target-host", default="192.168.49.2")
	parser.add_argument("--tcp-port", type=int, default=7881)
	parser.add_argument("--udp-port", type=int, default=7882)
	args = parser.parse_args()

	threading.Thread(target=tcp_relay, args=(args.tcp_port, args.target_host, args.tcp_port), daemon=True).start()
	udp_relay(args.udp_port, args.target_host, args.udp_port)
