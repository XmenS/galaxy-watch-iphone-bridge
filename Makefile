.DEFAULT_GOAL := help
SHELL := /bin/bash

# Override at the command line, e.g. `make test-ios IOS_SIM='iPhone 16'`.
IOS_SIM ?= iPhone 16 Pro
IOS_SIM_OS ?= 18.6

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: test-wearos test-ios ## Run all unit tests

test-wearos: ## Run Wear OS unit tests
	cd apps/wearos && ./gradlew :app:testDebugUnitTest --no-daemon

build-wearos: ## Build the Wear OS debug APK
	cd apps/wearos && ./gradlew :app:assembleDebug --no-daemon
	@echo "APK: apps/wearos/app/build/outputs/apk/debug/app-debug.apk"

generate-ios: ## Regenerate the Xcode project from project.yml
	cd apps/ios && xcodegen generate

test-ios: generate-ios ## Build + test the iOS app on a simulator
	cd apps/ios && xcodebuild \
	  -project GalaxyHealthBridge.xcodeproj \
	  -scheme GalaxyHealthBridge \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIM),OS=$(IOS_SIM_OS)' \
	  -configuration Debug \
	  CODE_SIGNING_ALLOWED=NO \
	  build test

clean: ## Remove build outputs
	rm -rf apps/wearos/app/build apps/wearos/build apps/wearos/.gradle
	rm -rf apps/ios/build apps/ios/DerivedData apps/ios/GalaxyHealthBridge.xcodeproj
