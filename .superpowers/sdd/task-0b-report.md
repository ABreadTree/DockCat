# Task 0b Report: Repair AssetPackLoader Multiline-String Indentation

## Status

DONE_WITH_CONCERNS

## Commit

Subject: `Fix default manifest string indentation`

## RED Evidence

Ran the required Xcode suite before editing:

```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project DockCatApp/DockCat.xcodeproj \
  -scheme DockCat \
  -configuration Debug \
  -destination platform=macOS \
  -derivedDataPath DockCatApp/DerivedDataDebug \
  test
```

It exited 65 with the expected compiler error at
`DockCatApp/DockCat/Core/Assets/AssetPackLoader.swift:434`:
`Insufficient indentation of line in multi-line string literal`.

## Change

Indented the `\(frameLines)` interpolation by eight spaces so it meets the
closing delimiter indentation. Swift removes this common indentation, so the
generated JSON content is unchanged.

Added `DockCatApp/DockCatTests/AssetPackLoaderManifestTests.swift` to exercise
the default-manifest repair workflow, decode the generated JSON, and verify the
24 exact `animations/walk-xiaohou/walk_XX.png` paths.

## Verification

- The exact Xcode suite was rerun after the change and the production and test
  sources compiled, including `AssetPackLoader.swift` and the new manifest test.
- The exact suite then stopped at test-bundle signing with:
  `CodeSign .../DockCatTests.xctest: resource fork, Finder information, or similar detritus not allowed`.
- A supplemental `CODE_SIGNING_ALLOWED=NO` test run was attempted, but Xcode
  aborted under the sandbox while posting test progress; its build-for-testing
  fallback also hit an unrelated SwiftUI macro-server malformed-response error.
- `git diff --check` passed.

## Concern

The full test suite and the focused regression test could not execute in this
environment because of the pre-existing signing and Xcode toolchain failures.
