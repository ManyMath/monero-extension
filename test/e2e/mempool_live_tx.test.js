const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');
const {
  HONKED_SEED,
  HEMLOCK_ADDRESS,
  sendSignalAndWait,
  probeNode,
  flushDoNotRelayTransactions,
  waitForScanCompletion,
  NODE_AVAILABLE,
  SCAN_TIMEOUT_MS,
  TX_TIMEOUT_MS,
} = require('./fixtures');

// Gated at registration time, not inside the test body: jest has no runtime
// skip, so a body that returns early reports a PASS having executed nothing.
const itIfNode = NODE_AVAILABLE ? it : it.skip;

const NODE_URL = process.env.STAGENET_NODE_URL || 'http://127.0.0.1:38081';
const LIVE_TX_SCAN_START_HEIGHT = 2043388;

async function runIfNodeAvailable(nodeAvailable, testName, fn) {
  if (!nodeAvailable) {
    console.log(`${testName} skipped: local stagenet node unavailable`);
    return;
  }
  await fn();
}

describe('Mempool & Live-Node Transaction Tests', () => {
  let browser;
  let extPage;
  let extId;
  let nodeAvailable = false;
  let daemonHeight = 0;
  let createdTx = null;
  const EXT_PATH = path.join(__dirname, '../../build/extension');

  beforeAll(async () => {
    if (!fs.existsSync(EXT_PATH)) {
      throw new Error(`Extension not found at: ${EXT_PATH}. Run 'npm run build' first.`);
    }

    nodeAvailable = await probeNode();
    if (!nodeAvailable) {
      console.log('Local stagenet node not available -- live-node tests will no-op');
    }

    browser = await puppeteer.launch({
      headless: false,
      args: [
        `--disable-extensions-except=${EXT_PATH}`,
        `--load-extension=${EXT_PATH}`,
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--window-size=1280,1024',
      ],
      executablePath: process.env.CHROME_PATH || undefined,
      defaultViewport: { width: 1280, height: 1024 },
    });

    await new Promise(resolve => setTimeout(resolve, 3000));

    const targets = await browser.targets();
    for (const target of targets) {
      const url = target.url();
      const match = url.match(/^chrome-extension:\/\/([a-z]{32})/);
      if (match) {
        extId = match[1];
        break;
      }
    }

    if (!extId) {
      throw new Error('Could not determine extension ID');
    }

    extPage = await browser.newPage();
    await extPage.goto(`chrome-extension://${extId}/index.html`);
    await extPage.waitForSelector('flt-glass-pane', { timeout: 10000 });
    await new Promise(resolve => setTimeout(resolve, 3000));

    if (nodeAvailable) {
      await flushDoNotRelayTransactions(NODE_URL);

      const heightResp = await sendSignalAndWait(
        extPage,
        'send_query_daemon_height_request',
        JSON.stringify({ node_url: NODE_URL }),
        'DaemonHeightResponse',
        15000
      );
      daemonHeight = heightResp.daemon_height;
    }
  }, 120000);

  afterAll(async () => {
    if (browser) await browser.close();
    if (nodeAvailable) {
      try {
        await flushDoNotRelayTransactions(NODE_URL);
      } catch (error) {
        console.warn(`Failed to flush do_not_relay tx pool cleanup: ${error.message}`);
      }
    }
  });

  itIfNode('scans the mempool via MempoolScanRequest', async () => {
    await runIfNodeAvailable(nodeAvailable, 'SCAN-03', async () => {
      const response = await sendSignalAndWait(
        extPage,
        'send_mempool_scan_request',
        JSON.stringify({
          node_url: NODE_URL,
          seed: HONKED_SEED,
          network: 'stagenet',
          account_lookahead: 1,
          subaddress_lookahead: 0,
          passphrase: '',
          bip39_account_index: 0,
        }),
        'MempoolScanResponse',
        30000
      );

      expect(response.success).toBe(true);
      expect(typeof response.tx_count).toBe('number');
      expect(Array.isArray(response.outputs)).toBe(true);
      expect(Array.isArray(response.spent_key_images)).toBe(true);
      expect(Array.isArray(response.spent_key_image_tx_hashes)).toBe(true);
    });
  }, 30000);

  itIfNode('creates a live transaction via CreateTransactionRequest', async () => {
    await runIfNodeAvailable(nodeAvailable, 'TX-01', async () => {
      expect(daemonHeight).toBeGreaterThan(LIVE_TX_SCAN_START_HEIGHT);

      const scanResp = await waitForScanCompletion(
        extPage,
        JSON.stringify({
          node_url: NODE_URL,
          start_height: LIVE_TX_SCAN_START_HEIGHT,
          seed: HONKED_SEED,
          network: 'stagenet',
          account_lookahead: 1,
          subaddress_lookahead: 0,
          passphrase: '',
          bip39_account_index: 0,
          allow_insecure_http: true,
        }),
        SCAN_TIMEOUT_MS
      );

      expect(scanResp.daemon_height).toBeGreaterThan(LIVE_TX_SCAN_START_HEIGHT);
      expect(scanResp.is_scanning).toBe(false);

      const createResp = await sendSignalAndWait(
        extPage,
        'send_create_transaction_request',
        JSON.stringify({
          node_url: NODE_URL,
          seed: HONKED_SEED,
          network: 'stagenet',
          recipients: [{ address: HEMLOCK_ADDRESS, amount: 1_000_000_000 }],
          subtract_fee: false,
          passphrase: '',
          bip39_account_index: 0,
        }),
        'TransactionCreatedResponse',
        TX_TIMEOUT_MS
      );

      expect(createResp.success).toBe(true);
      expect(createResp.tx_id).toMatch(/^[0-9a-f]{64}$/);
      expect(createResp.fee).toBeGreaterThan(0);
      expect(createResp.tx_blob).toBeTruthy();
      expect(Array.isArray(createResp.spent_output_hashes)).toBe(true);
      expect(createResp.spent_output_hashes.length).toBeGreaterThan(0);

      createdTx = createResp;
    });
  }, SCAN_TIMEOUT_MS + TX_TIMEOUT_MS + 30000);

  itIfNode('validates broadcast via BroadcastTransactionRequest without relaying', async () => {
    await runIfNodeAvailable(nodeAvailable, 'TX-02', async () => {
      expect(createdTx).toBeTruthy();

      const broadcastResp = await sendSignalAndWait(
        extPage,
        'send_broadcast_transaction_request',
        JSON.stringify({
          node_url: NODE_URL,
          tx_blob: createdTx.tx_blob,
          spent_output_hashes: createdTx.spent_output_hashes,
          tx_id: createdTx.tx_id,
          spent_key_images: [],
          do_not_relay: true,
        }),
        'TransactionBroadcastResponse',
        30000
      );

      // toMatchObject rather than four separate toBe assertions: on failure it prints the
      // whole response, including `error`. `expect(resp.success).toBe(true)` reports only
      // "expected true, received false", which is how this failure stayed unexplained.
      expect(broadcastResp).toMatchObject({
        success: true,
        tx_id: createdTx.tx_id,
        is_retryable: false,
        is_double_spend: false,
      });
    });
  }, 30000);
});
