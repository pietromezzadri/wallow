// SPDX-License-Identifier: AGPL-3.0-or-later

import {Logger} from '@app/features/platform/utils/AppLogger';
import {
	getGeneratorVideoCtor,
	getNativeScreenCaptureApi,
	getVideoFrameCtor,
	markNativeScreenShareTrack,
	MAX_GENERATOR_PENDING_VIDEO_FRAMES,
	type NativeScreenBridgeHandle,
} from '@app/features/voice/utils/native_screen_capture_bridge/shared';
import type {NativeScreenCaptureSourceKind} from '@app/types/electron.d';

const logger = new Logger('NativeWindowScreenCaptureBridge');

export interface NativeWindowScreenShareBridgeOptions {
	width?: number;
	height?: number;
	frameRate?: number;
}

export async function createNativeWindowScreenShareBridge(
	sourceId: string,
	sourceKind: NativeScreenCaptureSourceKind,
	options: NativeWindowScreenShareBridgeOptions = {},
): Promise<NativeScreenBridgeHandle> {
	const api = getNativeScreenCaptureApi();
	if (!api) {
		throw new Error('Native screen capture is unavailable outside the desktop app');
	}
	const stopNativeCapture = api.stop.bind(api);
	const startNativeCapture = api.start.bind(api);
	const onNativeFrame = api.onFrame.bind(api);
	const GeneratorCtor = getGeneratorVideoCtor();
	const VideoFrameCtor = getVideoFrameCtor();
	if (!GeneratorCtor || !VideoFrameCtor) {
		throw new Error('This runtime does not support MediaStreamTrackGenerator/VideoFrame');
	}

	const generator = new GeneratorCtor({kind: 'video'});
	markNativeScreenShareTrack(generator);
	const writer = generator.writable.getWriter();

	let cleanedUp = false;
	let pendingWrites = 0;
	let captureId: string | null = null;

	const unsubscribeFrame = onNativeFrame((message) => {
		if (cleanedUp || captureId === null || message.captureId !== captureId) return;
		if (pendingWrites >= MAX_GENERATOR_PENDING_VIDEO_FRAMES) {
			return;
		}
		let frame: InstanceType<typeof VideoFrameCtor>;
		try {
			frame = new VideoFrameCtor(message.data, {
				format: 'BGRA',
				codedWidth: message.width,
				codedHeight: message.height,
				timestamp: message.timestampUs,
			});
		} catch (error) {
			logger.warn('Failed to construct a VideoFrame from a native capture buffer', {error});
			return;
		}
		pendingWrites += 1;
		writer
			.write(frame)
			.catch((error) => {
				logger.debug('Failed to write a native capture frame to the generator', {error});
			})
			.finally(() => {
				pendingWrites -= 1;
			});
	});

	async function cleanup(stopRemote: boolean = true): Promise<void> {
		if (cleanedUp) return;
		cleanedUp = true;
		unsubscribeFrame();
		if (stopRemote && captureId) {
			await stopNativeCapture(captureId).catch((error) => {
				logger.warn('Failed to stop native screen capture', {error, captureId});
			});
		}
		try {
			await writer.close();
		} catch {}
	}

	try {
		const result = await startNativeCapture({
			sourceId,
			sourceKind,
			width: options.width,
			height: options.height,
			frameRate: options.frameRate,
			deliverFrames: true,
		});
		captureId = result.captureId;
	} catch (error) {
		await cleanup(false);
		throw error;
	}

	logger.debug('Native window screen share bridge started', {sourceId, sourceKind, captureId});

	return {track: generator, cleanup};
}
