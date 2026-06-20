#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: $1 not found${2:+ ($2)}" >&2; exit 1; }; }
need xcodebuild
need ldid "brew install ldid"
need dpkg-deb "brew install dpkg"
need xz "brew install xz"
[[ -x /usr/libexec/PlistBuddy ]] || { echo "error: /usr/libexec/PlistBuddy missing" >&2; exit 1; }

BASE_PACKAGE_IDENTIFIER="io.nekohasekai.sfajb"
APP_DISPLAY_NAME="sing-box JB"
PRODUCT_NAME="sing-box"
DERIVED_DATA="$REPO_ROOT/build/jailbreak/DerivedData"
APP_SRC="$DERIVED_DATA/Build/Products/Release-iphoneos/$PRODUCT_NAME.app"
DEB_ROOT="$REPO_ROOT/build/jailbreak/debroot"
ENT="$REPO_ROOT/Jailbreak"
DAEMON_BIN="$DERIVED_DATA/Build/Products/Release-iphoneos/sfajb-roothelper"
HELPER_PLIST="io.nekohasekai.sfajb.helper.plist"

echo "Building $PRODUCT_NAME (JAILBREAK, $BASE_PACKAGE_IDENTIFIER)"
build() {
	xcodebuild build \
		-scheme SFI \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-derivedDataPath "$DERIVED_DATA" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) JAILBREAK' \
		BASE_PACKAGE_IDENTIFIER="$BASE_PACKAGE_IDENTIFIER" \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_BITCODE=NO
}
if command -v xcbeautify >/dev/null 2>&1; then
	build | xcbeautify
else
	build
fi

if [[ ! -d "$APP_SRC" ]]; then
	echo "error: app not built at $APP_SRC" >&2
	exit 1
fi

# The SFI MARKETING_VERSION is stripped to X.Y.Z for App Store Connect; the SFM.System
# standalone target keeps the full prerelease form (set by sing-box's update_apple_version).
VERSION="$(awk -F' = ' '
	/MARKETING_VERSION = / { v=$2; gsub(/[";]/,"",v) }
	/PRODUCT_BUNDLE_IDENTIFIER = io\.nekohasekai\.sfavt\.standalone;/ { print v; exit }
' sing-box.xcodeproj/project.pbxproj)"
[[ -n "$VERSION" ]] || { echo "error: could not read standalone MARKETING_VERSION from project.pbxproj" >&2; exit 1; }
echo "Packaging $PRODUCT_NAME $VERSION"

echo "Building sfajb-roothelper daemon ($VERSION)"
build_daemon() {
	xcodebuild build \
		-scheme JailbreakDaemon \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-derivedDataPath "$DERIVED_DATA" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) JAILBREAK' \
		BASE_PACKAGE_IDENTIFIER="$BASE_PACKAGE_IDENTIFIER" \
		MARKETING_VERSION="$VERSION" \
		CODE_SIGNING_ALLOWED=NO
}
if command -v xcbeautify >/dev/null 2>&1; then
	build_daemon | xcbeautify
else
	build_daemon
fi
if [[ ! -f "$DAEMON_BIN" ]]; then
	echo "error: daemon not built at $DAEMON_BIN" >&2
	exit 1
fi
ldid -S"$REPO_ROOT/JailbreakDaemon/RootHelper.entitlements" "$DAEMON_BIN"

rm -rf "$DEB_ROOT"
APP_DEST="$DEB_ROOT/var/jb/Applications/$PRODUCT_NAME.app"
mkdir -p "$DEB_ROOT/var/jb/Applications" "$DEB_ROOT/var/jb/usr/libexec" "$DEB_ROOT/var/jb/Library/LaunchDaemons" "$DEB_ROOT/DEBIAN"
cp -R "$APP_SRC" "$APP_DEST"

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_DISPLAY_NAME" "$APP_DEST/Info.plist" 2>/dev/null \
	|| /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_DISPLAY_NAME" "$APP_DEST/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DEST/Info.plist"

# /Applications apps aren't registered with usernotificationsd by installd; this key is what
# makes it accept and present local notifications. Redundant (and a private key) for the App Store build.
/usr/libexec/PlistBuddy -c "Add :SBAppUsesLocalNotifications bool true" "$APP_DEST/Info.plist" 2>/dev/null \
	|| /usr/libexec/PlistBuddy -c "Set :SBAppUsesLocalNotifications true" "$APP_DEST/Info.plist"

rm -rf "$APP_DEST/SC_Info" "$APP_DEST/_CodeSignature" "$APP_DEST/embedded.mobileprovision" "$APP_DEST/Export.plist"
find "$APP_DEST" -name '.DS_Store' -delete

cp "$DAEMON_BIN" "$DEB_ROOT/var/jb/usr/libexec/sfajb-roothelper"
chmod 755 "$DEB_ROOT/var/jb/usr/libexec/sfajb-roothelper"
cp "$REPO_ROOT/JailbreakDaemon/$HELPER_PLIST" "$DEB_ROOT/var/jb/Library/LaunchDaemons/"

# ldid signs per-binary: its recursive directory mode can't give nested code (the
# appexes) distinct entitlement sets.
sign() { echo "  sign $(basename "$1")"; ldid -S"$2" "$1"; }
adhoc() { echo "  sign $(basename "$1") (ad-hoc)"; ldid -S "$1"; }

MAIN="sing-box"
SIGN_TABLE="\
PlugIns/Extension.appex/Extension|Extension.plist
PlugIns/FileProviderExtension.appex/FileProviderExtension|FileProvider.plist
PlugIns/WidgetExtension.appex/WidgetExtension|Widget.plist
Extensions/IntentsExtension.appex/IntentsExtension|Intents.plist"

is_entitled() {
	[[ "$1" == "$APP_DEST/$MAIN" ]] && return 0
	local rel
	while IFS='|' read -r rel _; do
		[[ -n "$rel" && "$1" == "$APP_DEST/$rel" ]] && return 0
	done <<< "$SIGN_TABLE"
	return 1
}

while IFS= read -r macho; do
	is_entitled "$macho" && continue
	adhoc "$macho"
done < <(find "$APP_DEST" -type f -perm +111 -exec sh -c 'file -b "$1" | grep -q "Mach-O" && echo "$1"' _ {} \;)

while IFS='|' read -r rel ent; do
	[[ -z "$rel" ]] && continue
	if [[ -f "$APP_DEST/$rel" ]]; then
		sign "$APP_DEST/$rel" "$ENT/$ent"
	else
		echo "  skip $rel (not built)"
	fi
done <<< "$SIGN_TABLE"

sign "$APP_DEST/$MAIN" "$ENT/App.plist"

export COPYFILE_DISABLE=1
find "$DEB_ROOT" -print0 | xargs -0 xattr -c 2>/dev/null || true
find "$DEB_ROOT" -name '._*' -delete
find "$DEB_ROOT" -name '.DS_Store' -delete

INSTALLED_SIZE="$(du -ks "$DEB_ROOT/var" | cut -f1)"
# dpkg sorts '~' before everything, so 1.14.0~alpha.33 < 1.14.0 (the eventual release);
# a literal '-' would parse as a Debian revision and sort *after* it, breaking upgrades.
DEB_VERSION="${VERSION//-/\~}"
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: $BASE_PACKAGE_IDENTIFIER
Name: sing-box JB
Version: $DEB_VERSION
Architecture: iphoneos-arm64
Installed-Size: $INSTALLED_SIZE
Description: sing-box but privileged
Maintainer: nekohasekai
Author: nekohasekai
Section: Networking
Depends: firmware (>= 15.0)
EOF

cat > "$DEB_ROOT/DEBIAN/postinst" <<EOF
#!/bin/sh
PLIST=/var/jb/Library/LaunchDaemons/$HELPER_PLIST
launchctl bootout system "\$PLIST" 2>/dev/null
launchctl bootstrap system "\$PLIST" 2>/dev/null
uicache -p /var/jb/Applications/sing-box.app
exit 0
EOF

cat > "$DEB_ROOT/DEBIAN/prerm" <<EOF
#!/bin/sh
launchctl bootout system /var/jb/Library/LaunchDaemons/$HELPER_PLIST 2>/dev/null
uicache -u /var/jb/Applications/sing-box.app 2>/dev/null
exit 0
EOF

chmod 755 "$DEB_ROOT/DEBIAN/postinst" "$DEB_ROOT/DEBIAN/prerm"

( cd "$DEB_ROOT" && find . -type f ! -path './DEBIAN/*' | sed 's|^\./||' | LC_ALL=C sort \
	| while IFS= read -r f; do printf '%s  %s\n' "$(md5 -q "$f")" "$f"; done ) > "$DEB_ROOT/DEBIAN/md5sums"
chmod 644 "$DEB_ROOT/DEBIAN/md5sums"

DEB_OUT="$REPO_ROOT/build/jailbreak/SFI-${VERSION}-iphoneos-arm64.deb"

dpkg-deb --root-owner-group -Zxz -z9 --build "$DEB_ROOT" "$DEB_OUT"

work="$(mktemp -d)"
( cd "$work" && ar x "$DEB_OUT" )
xz -dc "$work/data.tar.xz" | xz -c --arm64 --lzma2=preset=9e > "$work/data.tar.new"
mv -f "$work/data.tar.new" "$work/data.tar.xz"
rm -f "$DEB_OUT"
# Without S, macOS ar adds a __.SYMDEF member that makes dpkg reject the .deb.
( cd "$work" && ar rcS "$DEB_OUT" debian-binary control.tar.xz data.tar.xz )
rm -rf "$work"
echo "Built $DEB_OUT"
