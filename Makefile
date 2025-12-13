build_all: build_ios build_macos build_macos_standalone build_tvos

build_ios:
	xcodebuild build -scheme SFI -configuration Debug -destination 'generic/platform=iOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

build_macos:
	xcodebuild build -scheme SFM -configuration Debug -destination 'generic/platform=macOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

build_macos_standalone:
	xcodebuild build -scheme SFM.System -configuration Debug -destination 'generic/platform=macOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

build_tvos:
	xcodebuild build -scheme SFT -configuration Debug -destination 'generic/platform=tvOS' | xcbeautify | grep -A 10 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"


release: release_ios release_macos release_tvos

release_ios: archive_ios upload_ios

archive_ios:
	xcodebuild archive -scheme SFI -configuration Release -destination 'generic/platform=iOS' -archivePath build/SFI.xcarchive -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e " ARCHIVE FAILED" -e "❌"

upload_ios:
	xcodebuild -exportArchive -archivePath build/SFI.xcarchive -exportOptionsPlist SFI/Upload.plist -allowProvisioningUpdates

release_maocs: archive_macos upload_macos

archive_macos:
	xcodebuild archive -scheme SFM -configuration Release -archivePath build/SFM.xcarchive -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e " ARCHIVE FAILED" -e "❌"

upload_macos:
	xcodebuild -exportArchive -archivePath build/SFM.xcarchive -exportOptionsPlist SFI/Upload.plist -allowProvisioningUpdates

release_tvos: archive_tvos upload_tvos

archive_tvos:
	xcodebuild archive -scheme SFT -configuration Release -archivePath build/SFT.xcarchive -allowProvisioningUpdates | xcbeautify | grep -A 10 -e "Archive Succeeded" -e " ARCHIVE FAILED" -e "❌"

upload_tvos:
	xcodebuild -exportArchive -archivePath "build/SFT.xcarchive" -exportOptionsPlist SFI/Upload.plist -allowProvisioningUpdates

fmt:
	swiftformat .

fmt_install:
	brew install swiftformat

lint:
	swiftlint

lint_install:
	brew install swiftlint
