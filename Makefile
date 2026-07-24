SHELL = /bin/bash

SCHEME = OttoWM
XCODEBUILD = xcodebuild -scheme $(SCHEME) CODE_SIGNING_ALLOWED=NO
XCBEAUTIFY = xcbeautify --disable-logging

.PHONY: build test

build:
	set -o pipefail; $(XCODEBUILD) build 2>&1 | $(XCBEAUTIFY)

test:
	set -o pipefail; $(XCODEBUILD) test 2>&1 | $(XCBEAUTIFY)
