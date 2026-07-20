# Scheduled — build a signed .app bundle from the SwiftPM executable.
# Requires only the Xcode Command Line Tools (swift, codesign).

APP_NAME    := Scheduled
BUNDLE_ID   := com.scheduled.app
CONFIG      := release
BUILD_DIR   := .build/$(CONFIG)
DIST_DIR    := dist
APP_BUNDLE  := $(DIST_DIR)/$(APP_NAME).app
MACOS_DIR   := $(APP_BUNDLE)/Contents/MacOS
RES_DIR     := $(APP_BUNDLE)/Contents/Resources
BIN         := $(BUILD_DIR)/$(APP_NAME)
INSTALL_DIR := /Applications

# Code-signing identity. Default is ad-hoc ("-"). Ad-hoc signatures change on
# every rebuild, so macOS re-prompts for Calendar/Reminders after each build.
# Set a STABLE identity to keep the permission grant across rebuilds, e.g.:
#   make CODESIGN_IDENTITY="Apple Development: you@example.com (TEAMID)"
# or a self-signed "code signing" certificate created in Keychain Access.
CODESIGN_IDENTITY ?= -

.PHONY: all build bundle sign run cli install clean help

all: bundle

## build: compile the SwiftPM executable (release)
build:
	swift build -c $(CONFIG)

## bundle: assemble dist/Scheduled.app and ad-hoc code-sign it
bundle: build
	@echo "==> Assembling $(APP_BUNDLE)"
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(MACOS_DIR)" "$(RES_DIR)"
	@cp "$(BIN)" "$(MACOS_DIR)/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(RES_DIR)/AppIcon.icns"
	@printf 'APPL????' > "$(APP_BUNDLE)/Contents/PkgInfo"
	@$(MAKE) --no-print-directory sign
	@echo "==> Built $(APP_BUNDLE)"

## sign: code sign so TCC (Calendar/Reminders) can track the app
sign:
	@echo "==> Code signing (identity: $(CODESIGN_IDENTITY))"
	@codesign --force --deep --sign "$(CODESIGN_IDENTITY)" \
		--identifier "$(BUNDLE_ID)" \
		"$(APP_BUNDLE)" 2>/dev/null || \
		codesign --force --deep --sign "$(CODESIGN_IDENTITY)" "$(APP_BUNDLE)"

## run: build the bundle and launch the menu-bar app
run: bundle
	@open "$(APP_BUNDLE)"

## cli: build, then run a one-off request. Usage: make cli TEXT="gym at 6am"
cli: bundle
	@"$(MACOS_DIR)/$(APP_NAME)" "$(TEXT)"

## install: copy the app into /Applications
install: bundle
	@echo "==> Installing to $(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "==> Installed. Launch from Spotlight or /Applications."

## clean: remove build artifacts
clean:
	@rm -rf .build "$(DIST_DIR)"

## help: list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
