#!/bin/sh
# Run every tier of this repo's tests, including the ones that are opt-in.
#
# This is the half of monero-rust's runner that needs the Flutter app. The other half — the
# rust default suite, monero-rust's own wasm32 build, its wasm32 unit tests, the mock-rpc
# send path and the regtest end-to-end tier — stayed behind with the library and runs from
# vendor/monero-rust/scripts/test-all.sh. Neither script covers the other; run both.
#
# A tier whose toolchain is missing or broken says so and is skipped; a tier that runs and
# fails is reported as a failure. The two are never conflated.
#
#   scripts/test-all.sh
#
# Exits non-zero if any tier fails, and reports which.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=""

for arg in "$@"; do
    case "$arg" in
        *)
            echo "usage: $0" >&2
            exit 2
            ;;
    esac
done

step() {
    echo
    echo "=== $1 ==="
}

record_failure() {
    FAILED="$FAILED
  - $1"
}

# monero_wasm path-depends on vendor/monero-rust/rust/monero-rust, so an uninitialised
# submodule takes the wasm32 tier with it. That is a FAILURE, not a skip: a missing
# toolchain leaves the subject matter intact and is the user's environment, but a missing
# submodule means the crate under test cannot be built at all. Skipping it would let a
# fresh clone print "all tiers passed" having compiled nothing that touches monero-rust,
# which is precisely the kind of green-but-empty check this script exists to stop.
step "monero-rust submodule is checked out"
if [ ! -f "$ROOT/vendor/monero-rust/rust/monero-rust/Cargo.toml" ]; then
    echo "vendor/monero-rust is not checked out. Run:" >&2
    echo "  git submodule update --init --recursive" >&2
    record_failure "monero-rust submodule missing"
else
    echo "ok: $(git -C "$ROOT/vendor/monero-rust" rev-parse --short HEAD)"
fi

step "wasm32 build"
if ! (cd "$ROOT/native/monero_wasm" && cargo check --target wasm32-unknown-unknown); then
    record_failure "monero_wasm wasm32"
fi

step "signal generator's own tests"
# codegen has its own [workspace], so the root workspace's --workspace never reaches these.
# They pin the checks the generator makes on signals/mod.rs — chiefly that Rust cannot skip
# serialising a field the generated Dart casts as required, which no compiler on either side
# would catch. They need neither formatter, so no skip applies.
if ! (cd "$ROOT/native/codegen" && cargo test --quiet); then
    record_failure "codegen unit tests"
fi

step "generated signal surface is current"
# native/monero_wasm/src/signals/mod.rs is the source of truth for the Dart <-> Rust signal
# surface, and codegen emits signal_types.dart, ffi_web.rs and signal_ids.rs from it.
# Nothing ran this check for six months, in which time the generator fell behind the files
# it owns and regenerating would have reverted shipping code. It only means anything while
# it runs.
#
# Both formatters are part of the comparison, so a missing one is a skip, not a failure.
if ! command -v dart >/dev/null 2>&1; then
    echo "dart not on PATH — skipping the codegen check (it formats the Dart output)" >&2
elif ! command -v rustfmt >/dev/null 2>&1; then
    echo "rustfmt not on PATH — skipping the codegen check (it formats the Rust output)" >&2
elif ! (cd "$ROOT/native/codegen" && cargo run --quiet -- --check); then
    record_failure "generated signal surface out of date"
fi

step "dart tests"
if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter not on PATH — skipping the dart tests" >&2
else
    DART_LOG="$(mktemp)"
    if (cd "$ROOT" && flutter test --no-pub) >"$DART_LOG" 2>&1; then
        tail -n 3 "$DART_LOG"
    elif grep -q '/packages/flutter/lib/' "$DART_LOG"; then
        # The failures are inside the SDK's own framework, not our tests: a Flutter
        # checkout whose framework revision and Dart SDK don't match can't compile
        # itself. Report it, but don't blame the repo for it.
        echo "SKIPPED: the Flutter SDK cannot compile its own framework, so no dart" >&2
        echo "test could load. This is the toolchain, not this repo — check" >&2
        echo "'flutter --version' (a detached user-branch checkout will do this) and" >&2
        echo "repair with 'flutter channel stable && flutter upgrade'." >&2
        echo "Full output: $DART_LOG" >&2
    else
        tail -n 20 "$DART_LOG" >&2
        record_failure "dart tests"
    fi
fi

step "browser tests"
# @TestOn('browser') files are silently skipped by `flutter test`, so they need their own
# invocation. They went unrun long enough for ten of them to rot unnoticed.
if ! command -v flutter >/dev/null 2>&1; then
    echo "flutter not on PATH — skipping the browser tests" >&2
elif [ ! -x "$(command -v google-chrome || command -v chromium || true)" ]; then
    echo "no chrome on PATH — skipping the browser tests" >&2
else
    # Discovered, not listed. A hand-written list is the same trap one level up: the file
    # that gets forgotten is invisible, because a browser test omitted from it looks exactly
    # like one that passed. Anything carrying the annotation runs.
    # Either quote style, since missing a file is the whole failure this replaces. No
    # backreference tying the two quotes together — ugrep, which is what `grep` is on this
    # machine, rejects one in an ERE.
    BROWSER_TESTS="$(cd "$ROOT" \
        && grep -rlE "@TestOn\(['\"]browser['\"]\)" test | sort | tr '\n' ' ')"
    if [ -z "$BROWSER_TESTS" ]; then
        echo "no @TestOn('browser') files found — the browser tier has nothing to run," >&2
        echo "which is itself suspicious; there were four." >&2
        record_failure "browser tests vanished"
    else
        echo "browser tests: $BROWSER_TESTS"
        # shellcheck disable=SC2086
        if ! (cd "$ROOT" && flutter test --no-pub --platform chrome $BROWSER_TESTS); then
            record_failure "browser tests"
        fi
    fi
fi

step "end-to-end in a real browser (puppeteer)"
# 70 tests, ~460 assertions, and until now nothing ran any of them. The whole suite runs
# here, not a hand-picked subset: the files that need a live daemon skip themselves through
# fixtures.js's probeNode(), so with no node reachable this settles at 61 passed / 9
# skipped / 0 failed. A hand-written "these ones are safe" list would be the same trap as a
# hand-written browser-test list — the file left off it looks exactly like one that passed.
#
# STAGENET_NODE_URL is pinned to an unreachable address unless the caller sets it, and that
# is deliberate. Left unset the suite defaults to 127.0.0.1:38081, which on this machine is
# routinely bound by another project's regtest daemon — so the tier's result would depend on
# a foreign process, and fixtures.js's flushDoNotRelayTransactions() would act on somebody
# else's chain. Set it yourself to exercise the 9 node-dependent tests.
if ! command -v npm >/dev/null 2>&1; then
    echo "npm not on PATH — skipping the e2e tier" >&2
elif [ ! -d "$ROOT/node_modules" ]; then
    echo "node_modules absent — skipping the e2e tier. Run:" >&2
    echo "  npm install" >&2
elif ! command -v wasm-pack >/dev/null 2>&1; then
    echo "wasm-pack not on PATH — skipping the e2e tier (it builds the extension)" >&2
    echo "  cargo install wasm-pack" >&2
elif ! command -v flutter >/dev/null 2>&1; then
    echo "flutter not on PATH — skipping the e2e tier (it builds the extension)" >&2
else
    # Always rebuild. The artifact under test has to match the source that produced it —
    # the extension_bridge.js class-binding bug was only visible once the extension was
    # rebuilt, and a stale build/extension would have hidden the fix as easily as the bug.
    E2E_BUILD_LOG="$(mktemp)"
    if ! (cd "$ROOT" && dart run tool/build_extension.dart) >"$E2E_BUILD_LOG" 2>&1; then
        tail -n 20 "$E2E_BUILD_LOG" >&2
        record_failure "e2e extension build"
    elif ! (cd "$ROOT" && STAGENET_NODE_URL="${STAGENET_NODE_URL:-http://127.0.0.1:9}" \
            npx jest --runInBand test/e2e); then
        record_failure "e2e tests"
    fi
fi

echo
if [ -n "$FAILED" ]; then
    echo "FAILED:$FAILED"
    exit 1
fi
echo "all tiers passed"
