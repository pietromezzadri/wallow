// SPDX-License-Identifier: AGPL-3.0-or-later

// `crypto.randomUUID()` is only exposed in secure contexts (https:, or
// http://localhost/127.0.0.1) -- a self-hosted instance reached over plain
// HTTP on any other hostname (e.g. a LAN name like wallow.local) never gets
// it, even though the rest of the Web Crypto API (including
// crypto.getRandomValues, used below) stays available regardless of secure
// context. Every call site that generates an id needs to tolerate that, so
// this is the one place that does.
export function randomUUID(): string {
	if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
		return crypto.randomUUID();
	}
	if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
		const bytes = crypto.getRandomValues(new Uint8Array(16));
		bytes[6] = (bytes[6] & 0x0f) | 0x40;
		bytes[8] = (bytes[8] & 0x3f) | 0x80;
		const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
		return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
	}
	return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}
