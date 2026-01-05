build_all: build_ios build_macos build_tvos

build_ios:
	xcodebuild build -scheme SFI -configuration Debug -destination 'generic/platform=iOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

build_macos:
	xcodebuild build -scheme SFM -configuration Debug -destination 'generic/platform=macOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

build_tvos:
	xcodebuild build -scheme SFT -configuration Debug -destination 'generic/platform=tvOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

release: release_ios release_macos release_tvos

release_ios: archive_ios upload_ios

archive_ios:
	rm -rf build/SFI.xcarchive
	xcodebuild archive -scheme SFI -configuration Release -destination 'generic/platform=iOS' -archivePath build/SFI.xcarchive -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e "ARCHIVE FAILED" -e "❌"

upload_ios:
	xcodebuild -exportArchive -archivePath build/SFI.xcarchive -exportOptionsPlist SFI/Upload.plist -allowProvisioningUpdates

release_macos: archive_macos upload_macos

archive_macos:
	rm -rf build/SFM.xcarchive
	xcodebuild archive -scheme SFM -configuration Release -archivePath build/SFM.xcarchive -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e "ARCHIVE FAILED" -e "❌"

upload_macos:
	xcodebuild -exportArchive -archivePath build/SFM.xcarchive -exportOptionsPlist SFI/Upload.plist -allowProvisioningUpdates

release_tvos: archive_tvos upload_tvos

archive_tvos:
	rm -rf build/SFT.xcarchive
	xcodebuild archive -scheme SFT -configuration Release -archivePath build/SFT.xcarchive -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e "ARCHIVE FAILED" -e "❌"

upload_tvos:
	xcodebuild -exportArchive -archivePath build/SFT.xcarchive -exportOptionsPlist SFI/Upload.plist -allowProvisioningUpdates

release_macos_standalone: build_macos_dmg notarize_macos_dmg

build_macos_standalone:
	rm -rf build/SFM.System-arm64.xcarchive build/SFM.System-x86_64.xcarchive
	xcodebuild archive -scheme SFM.System -configuration Release -archivePath build/SFM.System-arm64.xcarchive ARCHS=arm64 -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e "ARCHIVE FAILED" -e "❌"
	xcodebuild archive -scheme SFM.System -configuration Release -archivePath build/SFM.System-x86_64.xcarchive ARCHS=x86_64 -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e "ARCHIVE FAILED" -e "❌"

build_macos_dmg: build_macos_standalone
	rm -rf build/SFM.System-arm64 build/SFM.System-x86_64
	xcodebuild -exportArchive -archivePath build/SFM.System-arm64.xcarchive -exportOptionsPlist SFM.System/Export.plist -exportPath build/SFM.System-arm64 -allowProvisioningUpdates
	xcodebuild -exportArchive -archivePath build/SFM.System-x86_64.xcarchive -exportOptionsPlist SFM.System/Export.plist -exportPath build/SFM.System-x86_64 -allowProvisioningUpdates
	rm -rf build/SFM-arm64.dmg build/SFM-x86_64.dmg
	create-dmg \
		--volname "sing-box" \
		--volicon "build/SFM.System-arm64/SFM.app/Contents/Resources/AppIcon.icns" \
		--icon "SFM.app" 0 0 \
		--hide-extension "SFM.app" \
		--app-drop-link 0 0 \
		--skip-jenkins \
		"build/SFM-arm64.dmg" "build/SFM.System-arm64/SFM.app"
	create-dmg \
		--volname "sing-box" \
		--volicon "build/SFM.System-x86_64/SFM.app/Contents/Resources/AppIcon.icns" \
		--icon "SFM.app" 0 0 \
		--hide-extension "SFM.app" \
		--app-drop-link 0 0 \
		--skip-jenkins \
		"build/SFM-x86_64.dmg" "build/SFM.System-x86_64/SFM.app"

notarize_macos_dmg:
	xcrun notarytool submit "build/SFM-arm64.dmg" --wait --keychain-profile "notarytool-password"
	xcrun notarytool submit "build/SFM-x86_64.dmg" --wait --keychain-profile "notarytool-password"
	xcrun stapler staple "build/SFM-arm64.dmg"
	xcrun stapler staple "build/SFM-x86_64.dmg"

fmt:
	swiftformat .

fmt_install:
	brew install swiftformat

lint:
	swiftlint

lint_install:
	brew install swiftlint

dmg_install:
	brew install create-dmg

clean:
	rm -rf build/SFI.xcarchive
	rm -rf build/SFM.xcarchive
	rm -rf build/SFT.xcarchive
	rm -rf build/SFM.System-arm64.xcarchive
	rm -rf build/SFM.System-x86_64.xcarchive
	rm -rf build/SFM.System-arm64
	rm -rf build/SFM.System-x86_64
	rm -rf build/SFM-arm64.dmg
	rm -rf build/SFM-x86_64.dmg
