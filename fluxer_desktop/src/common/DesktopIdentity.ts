// SPDX-License-Identifier: AGPL-3.0-or-later

import {BUILD_CHANNEL} from '@electron/common/BuildChannel';

export const DESKTOP_APP_NAME = BUILD_CHANNEL === 'canary' ? 'Wallow Canary' : 'Wallow';
export const MACOS_BUNDLE_ID = BUILD_CHANNEL === 'canary' ? 'app.wallow.canary' : 'app.wallow';
export const LINUX_DESKTOP_ENTRY_ID = BUILD_CHANNEL === 'canary' ? 'wallow-canary' : 'wallow';
export const WINDOWS_SHORTCUT_AUTHOR = 'Wallow';
const WINDOWS_VELOPACK_ID = BUILD_CHANNEL === 'canary' ? 'wallow_desktop_canary' : 'wallow_desktop';
export const WINDOWS_APP_USER_MODEL_ID = BUILD_CHANNEL === 'canary' ? 'Wallow.Wallow.Canary' : 'Wallow.Wallow';
export const WINDOWS_LEGACY_APP_USER_MODEL_IDS = [`velopack.${WINDOWS_VELOPACK_ID}`];
export const WINDOWS_TOAST_ACTIVATOR_CLSID =
	BUILD_CHANNEL === 'canary' ? '{A828023C-6E65-4B18-9B8A-83E712FF3DA9}' : '{BEAD2B4F-3121-42D8-9628-C200779C1E79}';
