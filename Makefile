all: ios macos macos_standalone tvos

ios:
	xcodebuild build -scheme SFI -configuration Debug -destination 'generic/platform=iOS' | xcbeautify | grep -A 3 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

macos:
	xcodebuild build -scheme SFM -configuration Debug -destination 'generic/platform=macOS' | xcbeautify | grep -A 3 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

macos_standalone:
	xcodebuild build -scheme SFM.System -configuration Debug -destination 'generic/platform=macOS' | xcbeautify | grep -A 3 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

tvos:
	xcodebuild build -scheme SFT -configuration Debug -destination 'generic/platform=tvOS' | xcbeautify | grep -A 3 -e "Build Succeeded" -e "BUILD FAILED" -e "❌"

fmt:
	swiftformat .

fmt_install:
	brew install swiftformat

lint:
	swiftlint

lint_install:
	brew install swiftlint
