SHELL = /bin/bash

SCHEME = OttoWM
XCODEBUILD = xcodebuild -scheme $(SCHEME) CODE_SIGNING_ALLOWED=NO
XCBEAUTIFY := $(if $(shell command -v xcbeautify),xcbeautify --disable-logging,cat)

PROJECT = $(SCHEME).xcodeproj/project.pbxproj
VERSION := $(shell awk -F' = ' '/MARKETING_VERSION/ {gsub(/;/, "", $$2); print $$2; exit}' $(PROJECT))
BUILD_NUMBER ?= $(shell git rev-list --count HEAD)
RESOURCES := $(shell find App/Assets.xcassets -type f) App/AppIcon.icon/icon.json
SOURCES := $(shell find App Core -name '*.swift') $(RESOURCES) $(SCHEME).entitlements $(PROJECT)

BUILD_DIR = build
RELEASE_DIR = $(BUILD_DIR)/Release
APP = $(RELEASE_DIR)/$(SCHEME).app
# The bundle directory keeps its timestamp when only the binary inside it is rebuilt,
# so the binary is what the archive is allowed to depend on.
APP_BINARY = $(APP)/Contents/MacOS/$(SCHEME)
ZIP = $(BUILD_DIR)/$(SCHEME)-$(VERSION).zip

HARNESS_SOURCES := $(shell find Harness -name '*.swift')

ACCEPTANCE_SOURCES := $(shell find Acceptance -name '*.swift') $(HARNESS_SOURCES)
ACCEPTANCE = $(BUILD_DIR)/acceptance

BENCHMARK_SOURCES := $(shell find Benchmark -name '*.swift') $(HARNESS_SOURCES)
BENCHMARK = $(BUILD_DIR)/benchmark
BENCHMARK_BUDGET_MS ?= 500
BENCHMARK_ARGS ?=

AXDUMP_SOURCES := $(shell find Tools/AXDump -name '*.swift')
AXDUMP = $(BUILD_DIR)/axdump
AXDUMP_DIR = OttoWMTests/Fixtures/axDumps

INSTALL_DIR ?= /Applications
INSTALLED = $(INSTALL_DIR)/$(SCHEME).app

CODE_SIGN_IDENTITY ?= -

.PHONY: build test acceptance benchmark axdump release install clean version

version:
	@echo $(VERSION)

build:
	set -o pipefail; $(XCODEBUILD) build 2>&1 | $(XCBEAUTIFY)

test:
	set -o pipefail; $(XCODEBUILD) test 2>&1 | $(XCBEAUTIFY)

acceptance: $(ACCEPTANCE)
	$(ACCEPTANCE)

$(ACCEPTANCE): $(ACCEPTANCE_SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc -o $@ $(ACCEPTANCE_SOURCES)

benchmark: $(BENCHMARK)
	$(BENCHMARK) --budget-p95 $(BENCHMARK_BUDGET_MS) $(BENCHMARK_ARGS)

$(BENCHMARK): $(BENCHMARK_SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc -O -o $@ $(BENCHMARK_SOURCES)

axdump: $(AXDUMP)
	$(AXDUMP) $(AXDUMP_DIR) $(ARGS)

$(AXDUMP): $(AXDUMP_SOURCES)
	@mkdir -p $(BUILD_DIR)
	swiftc -o $@ $(AXDUMP_SOURCES)

release: $(ZIP)

$(ZIP): $(APP_BINARY)
	ditto -c -k --keepParent $(APP) $@

$(APP_BINARY): $(SOURCES)
	set -o pipefail; xcodebuild -scheme $(SCHEME) -configuration Release \
		CONFIGURATION_BUILD_DIR=$(CURDIR)/$(RELEASE_DIR) \
		CODE_SIGNING_ALLOWED=YES \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY=$(CODE_SIGN_IDENTITY) \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		DEVELOPMENT_TEAM= \
		PROVISIONING_PROFILE_SPECIFIER= \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		build 2>&1 | $(XCBEAUTIFY)
	codesign --verify --strict --verbose=2 $(APP)

install: $(INSTALLED)

$(INSTALLED): $(ZIP)
	rm -rf $@
	ditto -x -k $(ZIP) $(INSTALL_DIR)
	xattr -cr $@

clean:
	rm -rf $(BUILD_DIR)
