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

Six tiers: the `monero_wasm` wasm32 build, the signal generator's own tests, the
generated-signal-surface check, the dart suite, the browser suite, and the puppeteer
e2e suite. A missing or broken toolchain is reported as a **skip**; a tier that runs
and fails is a **failure**. The two are never conflated — keep it that way.

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

### E2E (Puppeteer/Jest)
`scripts/test-all.sh` runs the whole suite as its sixth tier — 70 tests, ~460
assertions, in a real Chrome with the built extension loaded. It needs `npm install`
once; without `node_modules` the tier reports a skip rather than passing quietly.

The tier **rebuilds the extension every run**. That is not incidental: the artifact
under test has to match the source that produced it, and a stale `build/extension`
hides a fix exactly as well as it hides a bug.

It runs **every** file, not a curated subset. With no node reachable the suite settles
at **50 passed / 20 skipped / 0 failed**. A hand-written "these are the safe ones" list
would be the same trap as a hand-written browser-test list: the file left off it looks
exactly like one that passed.

**Node-dependent tests are gated at registration time**, via `NODE_AVAILABLE` in
`fixtures.js`, which probes synchronously when the module is required. That is not a
style choice. Jest evaluates `describe` bodies before any `beforeAll` runs, so the old
`describeIfNode = nodeAvailable ? describe : describe.skip` was reading a flag that was
still `false` — it was *always* `describe.skip`, and 9 tests behind it could never run
under any conditions. A further 15 used a `runIfNodeAvailable()` wrapper *inside* the
test body, which returned early and reported a **pass having executed nothing**. Both
now resolve to `it.skip`/`describe.skip` when no node answers, so a skip is a skip and
a pass is a pass.

To run it directly, or to exercise the 20 node-dependent tests:

```sh
npm install
STAGENET_NODE_URL=http://127.0.0.1:$PORT npx jest --runInBand test/e2e
npm run test:signal-e2e -- test/e2e/multi_wallet_scan.test.js   # single file
```

**Always set `STAGENET_NODE_URL` explicitly.** Unset, it falls back to
`http://127.0.0.1:38081` — the stagenet port, which other projects routinely bind for
their own regtest daemons, so the result would depend on a foreign process and
`flushDoNotRelayTransactions()` would act on somebody else's chain. The tier pins it to
an unreachable address unless you override it, for exactly that reason.

Against a node, all 70 execute and 69 passed on a public stagenet node. Two caveats,
both about *shared* nodes rather than the code:

- **Scan time varies enormously.** The same ~130k-block scan took 31s, 130s and 186s on
  consecutive runs against a public node. `E2E_SCAN_TIMEOUT_MS` (default 300000) is a
  ceiling, not a delay — raise it for a slow remote, lower it for a local one.
- **The live-broadcast tests depend on mempool state you do not control.** `TX-02`
  ("validates broadcast … without relaying") passes in isolation and fails after another
  file has put a conflicting do-not-relay transaction in a *shared* pool.
  `flushDoNotRelayTransactions()` cleans up, but a public node will usually refuse the
  admin RPC. These want a private node.

So: a public node is fine for confirming the suite runs, and a dedicated node is what
makes the live-transaction tests reliable.

`npm test` is the broader repo-style path that also runs the Rust suite; unrelated Rust
regressions can fail it.
