-include .env.local

APP_NAME ?= GameStub
CONFIG ?= release

DIST_DIR ?= dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
ZIP_PATH := $(DIST_DIR)/$(APP_NAME).zip

INFO_PLIST := Packaging/Info.plist

BUILD_DIR := .build/$(CONFIG)
RUNNER_BIN := $(BUILD_DIR)/runner
LAUNCHER_BIN := $(BUILD_DIR)/launcher

SIGN_IDENTITY ?=
NOTARY_PROFILE ?=
ENTITLEMENTS ?= Packaging/GameStub.entitlements

SWIFT_DEFINES ?=
SWIFT_FLAGS := $(foreach d,$(SWIFT_DEFINES),-Xswiftc -D -Xswiftc $(d))

.PHONY: all build bundle clean sign notarize zip release

all: bundle

build:
	swift build -c $(CONFIG) $(SWIFT_FLAGS)

bundle: build
	@test -f "$(INFO_PLIST)" || (echo "Missing: $(INFO_PLIST)" && exit 1)
	@test -f "$(RUNNER_BIN)" || (echo "Missing: $(RUNNER_BIN) (did you name the target Runner?)" && exit 1)
	@test -f "$(LAUNCHER_BIN)" || (echo "Missing: $(LAUNCHER_BIN) (did you name the target Launcher?)" && exit 1)

	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)"

	cp "$(INFO_PLIST)" "$(CONTENTS_DIR)/Info.plist"

	cp "$(RUNNER_BIN)" "$(MACOS_DIR)/runner"
	chmod +x "$(MACOS_DIR)/runner"

	cp "$(LAUNCHER_BIN)" "$(MACOS_DIR)/launcher"
	chmod +x "$(MACOS_DIR)/launcher"

sign: bundle
	@test -n "$(SIGN_IDENTITY)" || (echo "Missing: SIGN_IDENTITY" && exit 1)
	@test -f "$(ENTITLEMENTS)" || (echo "Missing: $(ENTITLEMENTS)" && exit 1)

	codesign --force --deep --sign "$(SIGN_IDENTITY)" \
		--options runtime \
		--entitlements "$(ENTITLEMENTS)" \
		"$(APP_DIR)"
	codesign --verify --deep --strict --verbose=4 "$(APP_DIR)"

zip: sign
	rm -f "$(ZIP_PATH)"
	ditto -c -k --keepParent "$(APP_DIR)" "$(ZIP_PATH)"

notarize: zip
	@test -n "$(NOTARY_PROFILE)" || (echo "Missing: NOTARY_PROFILE" && exit 1)

	xcrun notarytool submit "$(ZIP_PATH)" \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	xcrun stapler staple "$(APP_DIR)"
 	xcrun stapler validate "$(APP_DIR)"

release: notarize

clean:
	swift package clean
	rm -rf "$(DIST_DIR)"