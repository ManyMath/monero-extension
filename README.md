# monero-extension
Flutter web extension demonstrating monero-rust. Runs as an extension rather
than a local webserver because of CORS restrictions.

Split out of `monero-rust/flutter/web`, whose history it keeps. The library it
wraps is a submodule at `vendor/monero-rust`, and `native/monero_wasm`
path-depends into it.

## Requirements
- Flutter 3.24.3
- Rust 1.89.0, with the `wasm32-unknown-unknown` target

## Setup
```sh
git submodule update --init --recursive   # vendor/monero-rust
flutter pub get
```

Nothing here builds without the submodule: `native/monero_wasm` depends on
`vendor/monero-rust/rust/monero-rust`.

## Build
```sh
dart run tool/build_extension.dart
```

Output: `build/extension/` (unpacked) and `build/monero-extension.zip`

Load in Chrome: open `chrome://extensions`, enable Developer mode, click "Load unpacked", select `build/extension/`.

For UI-only changes, rebuild just the Flutter Web aspect and pack a new .zip as in:

```sh
dart run tool/build_ui.dart
```

## Testing
Everything, in one command:
```sh
scripts/test-all.sh
```

Five tiers: the `monero_wasm` wasm32 build, the signal generator's own tests, the
generated-signal-surface check, the dart suite and the browser suite. A missing or
broken toolchain is reported as a **skip**; a tier that runs and fails is a
**failure**. The two are never conflated — keep it that way.

`flutter test` silently skips `@TestOn('browser')` files, which is why the browser
tier gets its own invocation, and why the runner *discovers* those files by
annotation rather than reading a hand-written list.

The library's own tiers — the rust suite, its wasm32 build and unit tests, the
mock-rpc send path and the regtest end-to-end tests — live with the library:
```sh
vendor/monero-rust/scripts/test-all.sh
```
Neither script covers the other.

Individually:
```sh
cd native/monero_wasm && cargo test --lib
flutter test
```

E2E:
```sh
npm install
npm run test:signal-e2e -- test/e2e/multi_wallet_scan.test.js
npm run test:signal-e2e:v1.2
npm test
```

Use `npm run test:signal-e2e -- <jest paths...>` for the dedicated signal-level Puppeteer/Jest entrypoint.
Use `npm test` only for the broader repo-style path that also runs the Rust suite; unrelated Rust regressions can still fail that command.
