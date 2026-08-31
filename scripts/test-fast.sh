#!/bin/sh
# Quick headless development loop. Browser, Puppeteer, wasm, and codegen tiers are in test-all.sh.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/vendor/monero-ffi/scripts/test-fast.sh"
cd "$ROOT"
flutter test --no-pub
