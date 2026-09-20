// SPDX-License-Identifier: AGPL-3.0-or-later
// One-off branding asset generator for the Wallow rebrand. Not part of the build.
import sharp from 'sharp';
import {writeFileSync, mkdirSync} from 'node:fs';
import path from 'node:path';

const ROOT = '/mnt/c/Users/pietr/Documents/Programming/fluxer';
const ICON_SVG = path.join(ROOT, 'branding/source/wallow-icon.svg');
const STABLE_DIR = path.join(ROOT, 'fluxer_desktop/build_resources/icons-stable');

async function renderPng(svgPath, size, outPath) {
	mkdirSync(path.dirname(outPath), {recursive: true});
	const buf = await sharp(svgPath, {density: 384}).resize(size, size).png().toBuffer();
	writeFileSync(outPath, buf);
	return buf;
}

function buildIco(pngBuffers) {
	// PNG-in-ICO format (Vista+): ICONDIR header + one ICONDIRENTRY per image + raw PNG blobs.
	const count = pngBuffers.length;
	const headerSize = 6 + 16 * count;
	let offset = headerSize;
	const header = Buffer.alloc(6);
	header.writeUInt16LE(0, 0);
	header.writeUInt16LE(1, 2);
	header.writeUInt16LE(count, 4);
	const entries = [];
	for (const {size, buf} of pngBuffers) {
		const entry = Buffer.alloc(16);
		entry.writeUInt8(size >= 256 ? 0 : size, 0);
		entry.writeUInt8(size >= 256 ? 0 : size, 1);
		entry.writeUInt8(0, 2);
		entry.writeUInt8(0, 3);
		entry.writeUInt16LE(1, 4);
		entry.writeUInt16LE(32, 6);
		entry.writeUInt32LE(buf.length, 8);
		entry.writeUInt32LE(offset, 12);
		offset += buf.length;
		entries.push(entry);
	}
	return Buffer.concat([header, ...entries, ...pngBuffers.map((p) => p.buf)]);
}

async function main() {
	// Square PNG set used directly by electron-builder / the tray code.
	const squareSizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024];
	const rendered = {};
	for (const size of squareSizes) {
		rendered[size] = await renderPng(ICON_SVG, size, path.join(STABLE_DIR, `${size}x${size}.png`));
		console.log(`wrote ${size}x${size}.png`);
	}
	// 128x128@2x.png is just the 256px render under a HiDPI filename.
	writeFileSync(path.join(STABLE_DIR, '128x128@2x.png'), rendered[256]);
	console.log('wrote 128x128@2x.png');

	// Master icon.png (electron-builder's default source icon).
	writeFileSync(path.join(STABLE_DIR, 'icon.png'), rendered[1024]);
	console.log('wrote icon.png');

	// Multi-resolution icon.ico from the standard Windows icon size ladder.
	const icoSizes = [16, 24, 32, 48, 64, 128, 256];
	const icoBuffers = icoSizes.map((size) => ({size, buf: rendered[size]}));
	writeFileSync(path.join(STABLE_DIR, 'icon.ico'), buildIco(icoBuffers));
	console.log('wrote icon.ico');

	// Windows Store/MSIX tile assets — simple centered scale, no special safe-zone padding.
	const tileSizes = [30, 44, 71, 89, 107, 142, 150, 284, 310];
	for (const size of tileSizes) {
		const buf = await renderPng(ICON_SVG, size, path.join(STABLE_DIR, `Square${size}x${size}Logo.png`));
		console.log(`wrote Square${size}x${size}Logo.png`);
	}
	await renderPng(ICON_SVG, 50, path.join(STABLE_DIR, 'StoreLogo.png'));
	console.log('wrote StoreLogo.png');
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});
