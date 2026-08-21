# Contributing

## Build and test

```sh
make build      # xcodebuild, code signing disabled
make test       # runs the OttoWMTests unit-test bundle
make bump       # bumps MARKETING_VERSION, also bump/minor and bump/major
make release    # generates a signed OttoWM.app
make install    # copies the signed app to /Applications
make acceptance # e2e of the installed app
make benchmark  # hotkey latency of the installed app
```

Run a single test:

```sh
xcodebuild -scheme OttoWM test CODE_SIGNING_ALLOWED=NO \
  -only-testing:OttoWMTests/WorkspacesTests/testWindowAssignment
```

`ARCHITECTURE.md` is what the app is made of and why.

## Acceptance and benchmark

`Acceptance/` is one scenario, a window sent to another workspace parks at the hidden edge and comes back, and the desk it was standing on goes with the workspace it belongs to. `Benchmark/` times the same hotkeys and prices them; see `Benchmark/README.md`.

Both drive the app installed in `/Applications` through the harness in `Harness/`: real hotkeys through the event tap, real frames read back through the accessibility API. Run `make install` first, and grant Accessibility permission to the terminal running them. `Harness/README.md` covers the desk they run on, the permissions they need and what they leave behind.

CI runs both on every push, on each macOS runner in the matrix.

## Releasing

`MARKETING_VERSION` in `OttoWM.xcodeproj/project.pbxproj` is the version. `make bump` rewrites it and prints the new one, `make bump/minor` or `make bump/major` for the other two digits. Commit the change and push to `main`, then CI tags `v<version>`, builds the universal zip and publishes the release. Pushing without bumping just builds a workflow artifact.
