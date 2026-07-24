SHELL = /bin/bash

SCHEME = OttoWM
XCODEBUILD = xcodebuild -scheme $(SCHEME) CODE_SIGNING_ALLOWED=NO
XCBEAUTIFY := $(if $(shell command -v xcbeautify),xcbeautify --disable-logging,cat)

.PHONY: build test

build:
	set -o pipefail; $(XCODEBUILD) build 2>&1 | $(XCBEAUTIFY)

test:
	set -o pipefail; $(XCODEBUILD) test 2>&1 | $(XCBEAUTIFY)
