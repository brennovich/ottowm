SHELL = /bin/bash

SCHEME = OttoWM
XCODEBUILD = xcodebuild -scheme $(SCHEME) CODE_SIGNING_ALLOWED=NO
XCBEAUTIFY := $(if $(shell command -v xcbeautify),xcbeautify --disable-logging,cat)

PROJECT = $(SCHEME).xcodeproj/project.pbxproj
VERSION := $(shell awk -F' = ' '/MARKETING_VERSION/ {gsub(/;/, "", $$2); print $$2; exit}' $(PROJECT))
SOURCES := $(shell find App Core -name '*.swift') $(SCHEME).entitlements $(PROJECT)

BUILD_DIR = build
RELEASE_DIR = $(BUILD_DIR)/Release
APP = $(RELEASE_DIR)/$(SCHEME).app
ZIP = $(BUILD_DIR)/$(SCHEME)-$(VERSION).zip

INSTALL_DIR ?= /Applications
INSTALLED = $(INSTALL_DIR)/$(SCHEME).app

CODE_SIGN_IDENTITY ?= -

.PHONY: build test release install clean

build:
	set -o pipefail; $(XCODEBUILD) build 2>&1 | $(XCBEAUTIFY)

test:
	set -o pipefail; $(XCODEBUILD) test 2>&1 | $(XCBEAUTIFY)

release: $(ZIP)

$(ZIP): $(APP)
	ditto -c -k --keepParent $(APP) $@

$(APP): $(SOURCES)
	set -o pipefail; xcodebuild -scheme $(SCHEME) -configuration Release \
		CONFIGURATION_BUILD_DIR=$(CURDIR)/$(RELEASE_DIR) \
		CODE_SIGNING_ALLOWED=YES \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY=$(CODE_SIGN_IDENTITY) \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		DEVELOPMENT_TEAM= \
		PROVISIONING_PROFILE_SPECIFIER= \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		build 2>&1 | $(XCBEAUTIFY)
	codesign --verify --strict --verbose=2 $@

install: $(INSTALLED)

$(INSTALLED): $(ZIP)
	rm -rf $@
	ditto -x -k $(ZIP) $(INSTALL_DIR)
	xattr -cr $@

clean:
	rm -rf $(BUILD_DIR)
