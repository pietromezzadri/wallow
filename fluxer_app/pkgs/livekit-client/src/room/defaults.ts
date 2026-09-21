// SPDX-FileCopyrightText: 2024 LiveKit, Inc.
//
// SPDX-License-Identifier: Apache-2.0
import type {InternalRoomConnectOptions, InternalRoomOptions} from '../options.ts';
import DefaultReconnectPolicy from './DefaultReconnectPolicy.ts';
import type {AudioCaptureOptions, TrackPublishDefaults, VideoCaptureOptions} from './track/options.ts';
import {AudioPresets, BackupCodecPolicy, ScreenSharePresets, VideoPresets} from './track/options.ts';

export const defaultVideoCodec = 'h264';

export const publishDefaults: TrackPublishDefaults = {
	audioPreset: AudioPresets.music,
	dtx: false,
	red: true,
	forceStereo: false,
	simulcast: true,
	screenShareEncoding: ScreenSharePresets.original.encoding,
	stopMicTrackOnMute: false,
	videoCodec: defaultVideoCodec,
	backupCodec: {codec: 'h264'},
	backupCodecPolicy: BackupCodecPolicy.SIMULCAST,
	degradationPreference: 'maintain-resolution',
	preConnectBuffer: false,
} as const;

export const audioDefaults: AudioCaptureOptions = {
	deviceId: {ideal: 'default'},
	autoGainControl: true,
	echoCancellation: true,
	noiseSuppression: true,
	voiceIsolation: true,
};

export const videoDefaults: VideoCaptureOptions = {
	deviceId: {ideal: 'default'},
	resolution: VideoPresets.h720.resolution,
};

export const roomOptionDefaults: InternalRoomOptions = {
	adaptiveStream: false,
	dynacast: true,
	stopLocalTrackOnUnpublish: true,
	reconnectPolicy: new DefaultReconnectPolicy(),
	disconnectOnPageLeave: true,
	webAudioMix: false,
	singlePeerConnection: true,
} as const;

export const roomConnectOptionDefaults: InternalRoomConnectOptions = {
	autoSubscribe: true,
	maxRetries: 1,
	// Upstream default is 15s, which is enough time when a UDP host/srflx
	// candidate pair connects (typically sub-second). When UDP is entirely
	// unreachable (e.g. self-hosted behind a NAT/tunnel with only an ICE-TCP
	// fallback candidate available) the ICE agent schedules TCP connectivity
	// checks after UDP ones, and a TCP handshake plus STUN-over-TCP framing
	// takes noticeably longer than a UDP round trip -- 15s was consistently
	// timing out before the TCP pair ever got attempted, not just before it
	// succeeded. 45s gives that fallback path room to actually run.
	peerConnectionTimeout: 45_000,
	websocketTimeout: 15_000,
} as const;
