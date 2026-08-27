#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APPLICATION_SIGN_IDENTITY="${APPLICATION_SIGN_IDENTITY:-Developer ID Application}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-21E03A44ACC2B48753BABB3DAE9B5F9A9CFF0480}"
UNIVERSAL_APP="build/SFM.System-universal/SFM.app"
PKG_IDENTIFIER="$(sed -n 's/.*<pkg-ref id="\([^"]*\)".*/\1/p' SFM.System/distribution-universal.xml | head -1)"

[[ -d "$UNIVERSAL_APP" ]] || { echo "error: $UNIVERSAL_APP not found" >&2; exit 1; }

resign() {
	local app="$1"
	local sysext
	sysext="$(echo "$app"/Contents/Library/SystemExtensions/*.systemextension)"
	local target
	for target in \
		"$sysext/Contents/Frameworks/Library.framework" \
		"$sysext" \
		"$app/Contents/Frameworks/Library.framework" \
		"$app"; do
		codesign --force --timestamp \
			--preserve-metadata=entitlements,requirements,flags \
			--sign "$APPLICATION_SIGN_IDENTITY" "$target"
	done
	codesign --verify --deep --strict "$app"
}

build_pkg() {
	local arch="$1" label="$2" app_dir="$3"
	local pkgroot="build/pkgroot-$arch"
	rm -rf "$pkgroot" "build/component-$arch.pkg" "build/SFM-$label.pkg"
	mkdir -p "$pkgroot"
	ditto "$app_dir" "$pkgroot/SFM.app"
	pkgbuild --root "$pkgroot" \
		--component-plist SFM.System/component.plist \
		--identifier "$PKG_IDENTIFIER" \
		--install-location /Applications \
		--min-os-version 13.0 \
		--compression latest \
		"build/component-$arch.pkg"
	productbuild --distribution "SFM.System/distribution-$arch.xml" \
		--package-path build \
		--resources SFM.System/Resources \
		--sign "$INSTALLER_SIGN_IDENTITY" \
		"build/SFM-$label.pkg"
	pkgutil --check-signature "build/SFM-$label.pkg" > /dev/null
	rm -rf "$pkgroot" "build/component-$arch.pkg"
}

for arch in arm64 x86_64; do
	rm -rf "build/SFM.System-$arch-thin"
	mkdir -p "build/SFM.System-$arch-thin"
	ditto --arch "$arch" "$UNIVERSAL_APP" "build/SFM.System-$arch-thin/SFM.app"
	resign "build/SFM.System-$arch-thin/SFM.app"
done

build_pkg arm64 Apple "build/SFM.System-arm64-thin/SFM.app"
build_pkg x86_64 Intel "build/SFM.System-x86_64-thin/SFM.app"
build_pkg universal Universal "$UNIVERSAL_APP"
