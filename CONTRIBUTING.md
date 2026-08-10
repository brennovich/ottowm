
# Contributing

## Build and test

```sh
make build      # xcodebuild, code signing disabled
make test       # runs the OttoWMTests unit-test bundle
make release    # generates a signed OttoWM.app
make install    # copies the signed app to /Applications
make acceptance # e2e of the installed app
```

Run a single test:

```sh
xcodebuild -scheme OttoWM test CODE_SIGNING_ALLOWED=NO \
  -only-testing:OttoWMTests/WorkspacesTests/testWindowAssignment
```

## Releasing

`MARKETING_VERSION` in `OttoWM.xcodeproj/project.pbxproj` is the version. Bump it, commit, and push to `main`, then CI tags `v<version>`, builds the universal zip and publishes the release. Pushing without bumping just builds an workflow artifact.
