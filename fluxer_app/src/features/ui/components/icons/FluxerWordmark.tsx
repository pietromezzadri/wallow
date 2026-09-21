// SPDX-License-Identifier: AGPL-3.0-or-later

import RuntimeConfig from '@app/features/app/state/RuntimeConfig';
import {type BrandSvgProps, getDataFlx, getImageSizingProps} from '@app/features/ui/components/icons/BrandImageUtils';
import FluxerWordmarkMonochromeAsset from '@app/media/images/fluxer-logo-wordmark-monochrome.svg?react';
import FluxerWordmarkAsset from '@app/media/images/fluxer-wordmark.svg?react';
import {msg} from '@lingui/core/macro';
import {useLingui} from '@lingui/react/macro';
import {observer} from 'mobx-react-lite';
import type React from 'react';

const APPLICATION_WORDMARK_DESCRIPTOR = msg({
	message: '{productName} wordmark',
	comment: 'Accessible label for the application wordmark.',
});

interface FluxerWordmarkProps extends BrandSvgProps {
	variant?: 'default' | 'monochrome';
}

export const FluxerWordmark = observer(({variant = 'default', ...props}: FluxerWordmarkProps) => {
	const {i18n} = useLingui();
	const productName = RuntimeConfig.productName;
	const ariaLabel = i18n._(APPLICATION_WORDMARK_DESCRIPTOR, {productName});
	if (RuntimeConfig.wordmarkUrl) {
		return (
			<img
				{...getImageSizingProps(props)}
				src={RuntimeConfig.wordmarkUrl}
				alt={ariaLabel}
				data-flx={getDataFlx(props, 'ui.icons.fluxer-wordmark.img')}
			/>
		);
	}
	// Compared against the literal upstream name, not DEFAULT_APP_PUBLIC_CONFIG's
	// product_name: that constant is this fork's own fallback ("Wallow"), used
	// elsewhere for "what to show before runtime config loads." The bundled
	// FluxerWordmark*Asset SVGs below still contain the original Fluxer artwork,
	// so this check has to ask "is productName still literally Fluxer" to decide
	// whether that bundled art is still accurate -- not "does it match our own
	// fallback," which would always be true now and skip straight to the stale art.
	if (productName !== 'Fluxer') {
		const style: React.CSSProperties = {
			...(props.style as React.CSSProperties | undefined),
			alignItems: 'center',
			display: 'inline-flex',
			fontWeight: 800,
			lineHeight: 1,
		};
		return (
			<span
				className={props.className}
				style={style}
				role="img"
				aria-label={ariaLabel}
				data-flx={getDataFlx(props, 'ui.icons.fluxer-wordmark.text')}
			>
				{productName}
			</span>
		);
	}
	const Asset = variant === 'monochrome' ? FluxerWordmarkMonochromeAsset : FluxerWordmarkAsset;
	return <Asset role="img" aria-label={ariaLabel} data-flx="ui.icons.fluxer-wordmark.img" {...props} />;
});
