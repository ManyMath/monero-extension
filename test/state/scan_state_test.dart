import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monero_extension/services/wallet_lifecycle_manager.dart';
import 'package:monero_extension/services/wallet_persistence_service.dart';
import 'package:monero_extension/services/wallet_polling_service.dart';
import 'package:monero_extension/src/ffi/signal_hub.dart';
import 'package:monero_extension/src/ffi/signal_sender.dart';
import 'package:monero_extension/src/ffi/signal_types.dart';
import 'package:monero_extension/state/scan_state.dart';
import 'package:monero_extension/state/wallet_state.dart';

import '../services/test_backends.dart';

class _Sender implements SignalSender {
  final sent = <({String name, Map<String, dynamic> data})>[];
  final _signals = StreamController<Map<String, dynamic>>.broadcast();

  @override
  void sendSignal(String signalName, Map<String, dynamic> data) {
    sent.add((name: signalName, data: data));
  }

  @override
  Stream<Map<String, dynamic>> onRawSignal(String typeName) => _signals.stream;

  void dispose() => _signals.close();
}

WalletState _walletState(SignalHub hub) => WalletState(
  lifecycle: WalletLifecycleManager(
    persistence: WalletPersistenceService(
      storage: InMemoryStorageBackend(),
      crypto: IdentityCryptoBackend(),
    ),
  ),
  signalHub: hub,
);

OwnedOutput _output(String txHash, int height) => OwnedOutput(
  txHash: txHash,
  outputIndex: 0,
  amount: 1000,
  amountXmr: '0.000000001000',
  key: 'key_$txHash',
  keyOffset: 'offset_$txHash',
  commitmentMask: 'mask_$txHash',
  receivedOutputBytes: 'bytes_$txHash',
  blockHeight: height,
  spent: false,
  keyImage: 'ki_$txHash',
  isCoinbase: false,
  frozen: false,
);

BlockScanResponse _scanned(String txHash, int height) => BlockScanResponse(
  success: true,
  blockHeight: height,
  blockHash: 'bh_$height',
  blockTimestamp: 0,
  txCount: 1,
  outputs: [_output(txHash, height)],
  daemonHeight: height + 10,
  spentKeyImages: const [],
  spentKeyImageTxHashes: const [],
);

/// Put a wallet at a scan height with an output there, without running a scan for it -
/// a scan started while it is the only open wallet would rebind `_singleScanWalletId`
/// and stop being the case under test.
void _seedWallet(
  WalletState walletState,
  String walletId,
  String txHash,
  int height,
) {
  final wallet = walletState.lifecycle.openWallets[walletId]!;
  wallet.outputs.add(_output(txHash, height));
  wallet.currentHeight = height;
}

void main() {
  late _Sender sender;

  setUp(() {
    sender = _Sender();
    setSignalSender(sender);
  });

  tearDown(() => sender.dispose());

  // Switching or loading a wallet does not stop a running scan, and a BlockScanResponse
  // says nothing about which wallet it was scanned for. Its multi-wallet sibling routes
  // every result by the address it belongs to; this path credited whichever wallet
  // happened to be active when the batch came back.
  test('a block scanned for another wallet is not credited to the active one', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();
    expect(
      sender.sent.map((s) => s.name),
      contains('send_start_continuous_scan_request'),
      reason: 'premise: a single-wallet scan is running for wallet_a',
    );

    // The user opens another wallet while that scan is in flight.
    walletState.openWallet('wallet_b', 'seed b words', 'stagenet', 'addr_b');
    expect(walletState.activeWalletId, 'wallet_b');

    hub.onBlockScan!(_scanned('scanned_for_a', 500));

    expect(
      walletState.lifecycle.openWallets['wallet_b']!.outputs,
      isEmpty,
      reason: 'wallet B must not be credited with a block scanned for wallet A',
    );
    expect(
      walletState.lifecycle.openWallets['wallet_b']!.currentHeight,
      0,
      reason: 'wallet B must not record a height it never scanned to',
    );
  });

  // The negative control. A guard that dropped everything would leave every wallet empty
  // and still satisfy the test above.
  test('a block scanned for the active wallet is credited to it', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();

    hub.onBlockScan!(_scanned('scanned_for_a', 500));

    expect(
      walletState.lifecycle.openWallets['wallet_a']!.outputs
          .map((o) => o.txHash),
      ['scanned_for_a'],
    );
    expect(
      walletState.lifecycle.openWallets['wallet_a']!.currentHeight,
      500,
    );
  });

  // A scan of a seed typed into the field has no wallet id to bind to, and the wallet it
  // belongs to is opened once its address derives - after the scan starts. Requiring a
  // match would discard results the app has always kept.
  test('a scan started before any wallet was open still credits the wallet', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.seedController.text = List.filled(25, 'word').join(' ');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    hub.onBlockScan!(_scanned('scanned_before_open', 500));

    expect(
      walletState.lifecycle.openWallets['wallet_a']!.outputs
          .map((o) => o.txHash),
      ['scanned_before_open'],
    );
  });

  // The reorg is the other outcome of the same scan, and it depended on nothing at all.
  // `handleReorgDetected` rewinds `activeWallet.currentHeight` to `splitHeight - 1` and
  // rebuilds its transaction list - so a fork found while scanning a wallet at height
  // 700000 moved a wallet sitting at 200 *forward* past every block it had yet to scan,
  // and it then reports itself synced over outputs it never looked for.
  test('a reorg found scanning another wallet is not applied to the active one', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    // A scan is running for wallet A, far up the chain.
    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();

    // The user opens wallet B, which has scanned as far as block 200 and holds an output
    // there. A's scan keeps running; nothing stops it.
    walletState.openWallet('wallet_b', 'seed b words', 'stagenet', 'addr_b');
    _seedWallet(walletState, 'wallet_b', 'b_own_output', 200);
    expect(walletState.activeWalletId, 'wallet_b');

    // A's scan reports a fork at 700000 - a height B has never been anywhere near.

    hub.onReorgDetected!(
      ReorgDetectedResponse(
        splitHeight: 700000,
        blocksDetached: 3,
        outputsRemoved: 0,
        outputsUnspent: 0,
        removedKeyImages: const [],
        unspentKeyImages: const [],
      ),
    );

    expect(
      walletState.lifecycle.openWallets['wallet_b']!.currentHeight,
      200,
      reason: 'wallet B was moved to a fork point found while scanning wallet A',
    );
  });

  // The other half of the same signal, and the destructive one. Before this was bound,
  // the Rust `HandleReorg` rolled back whatever wallet the actor then held, so the key
  // images it reports removed are the *active* wallet's own - which Dart then deletes.
  test("a reorg found scanning another wallet does not delete the active one's outputs", () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();

    walletState.openWallet('wallet_b', 'seed b words', 'stagenet', 'addr_b');
    _seedWallet(walletState, 'wallet_b', 'b_own_output', 200);

    hub.onReorgDetected!(
      ReorgDetectedResponse(
        splitHeight: 150,
        blocksDetached: 51,
        outputsRemoved: 1,
        outputsUnspent: 0,
        removedKeyImages: const ['ki_b_own_output'],
        unspentKeyImages: const [],
      ),
    );

    expect(
      walletState.lifecycle.openWallets['wallet_b']!.outputs
          .map((o) => o.txHash),
      ['b_own_output'],
      reason: "wallet B's own output was deleted by another wallet's reorg",
    );
    expect(
      walletState.lifecycle.openWallets['wallet_b']!.currentHeight,
      200,
      reason: 'wallet B was rewound to a fork point found while scanning wallet A',
    );
  });

  // The negative control. Refusing every reorg would leave a wallet on an orphaned chain
  // crediting itself with outputs that no longer exist, and would still pass the test
  // above.
  test('a reorg found scanning the active wallet is applied to it', () {
    final hub = SignalHub();
    final walletState = _walletState(hub);
    addTearDown(walletState.dispose);
    final scanState = ScanState(
      walletState: walletState,
      pollingService: WalletPollingService(),
      signalHub: hub,
    );
    addTearDown(scanState.dispose);

    walletState.openWallet('wallet_a', 'seed a words', 'stagenet', 'addr_a');
    walletState.nodeUrlController.text = 'http://127.0.0.1:18081';
    walletState.blockHeightController.text = '100';
    scanState.startContinuousScan();
    hub.onBlockScan!(_scanned('orphaned', 500));

    hub.onReorgDetected!(
      ReorgDetectedResponse(
        splitHeight: 400,
        blocksDetached: 101,
        outputsRemoved: 1,
        outputsUnspent: 0,
        removedKeyImages: const ['ki_orphaned'],
        unspentKeyImages: const [],
      ),
    );

    expect(
      walletState.lifecycle.openWallets['wallet_a']!.outputs,
      isEmpty,
      reason: 'the orphaned output must be dropped from the wallet that scanned it',
    );
    expect(
      walletState.lifecycle.openWallets['wallet_a']!.currentHeight,
      399,
      reason: 'the wallet that scanned the fork must rewind to it',
    );
  });
}
