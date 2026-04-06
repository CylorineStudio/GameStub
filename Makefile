APP_NAME ?= GameStub
CONFIG ?= release

DIST_DIR ?= dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

INFO_PLIST := Packaging/Info.plist

BUILD_DIR := .build/$(CONFIG)
RUNNER_BIN := $(BUILD_DIR)/runner
LAUNCHER_BIN := $(BUILD_DIR)/launcher

SWIFT_DEFINES ?=
SWIFT_FLAGS := $(foreach d,$(SWIFT_DEFINES),-Xswiftc -D -Xswiftc $(d))

.PHONY: all build bundle clean

all: bundle

build:
	swift build -c $(CONFIG) $(SWIFT_FLAGS)

bundle: build
	@test -f "$(INFO_PLIST)" || (echo "Missing: $(INFO_PLIST)" && exit 1)
	@test -f "$(RUNNER_BIN)" || (echo "Missing: $(RUNNER_BIN) (did you name the target Runner?)" && exit 1)
	@test -f "$(LAUNCHER_BIN)" || (echo "Missing: $(LAUNCHER_BIN) (did you name the target Launcher?)" && exit 1)

	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"

	cp "$(INFO_PLIST)" "$(CONTENTS_DIR)/Info.plist"

	cp "$(RUNNER_BIN)" "$(MACOS_DIR)/runner"
	chmod +x "$(MACOS_DIR)/runner"

	cp "$(LAUNCHER_BIN)" "$(RESOURCES_DIR)/launcher"
	chmod +x "$(RESOURCES_DIR)/launcher"

clean:
	swift package clean
	rm -rf "$(DIST_DIR)"
	
