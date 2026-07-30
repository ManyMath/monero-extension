const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');
// Not a private copy. This file had its own `reloadExtensionPage`, which left `goto` on
// puppeteer's 30s default and then *slept three seconds* in place of waiting for the
// bindings — so the reload that fixtures.js was hardened against was, in the one file
// where it decides five tests, still the unhardened one.
const { reloadExtensionPage, PAGE_LOAD_BUDGET_MS } = require('./fixtures');

/** Send `signalFnName` and resolve when `responseTypeName` is received. */
async function sendSignalAndWait(page, signalFnName, requestJson, responseTypeName, timeoutMs = 10000) {
  return page.evaluate(
    ({ signalFnName, requestJson, responseTypeName, timeoutMs }) => {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(
          () => reject(new Error(`Timeout waiting for ${responseTypeName} after ${timeoutMs}ms`)),
          timeoutMs
        );
        const origCallback = window._rustSignalCallback;
        window.wasmBindings.register_rust_signal_callback((typeName, json) => {
          if (origCallback) {
            try { origCallback(typeName, json); } catch (e) { /* ignore */ }
          }
          if (typeName === responseTypeName) {
            clearTimeout(timeout);
            resolve(JSON.parse(json));
          }
        });
        window.wasmBindings[signalFnName](requestJson);
      });
    },
    { signalFnName, requestJson, responseTypeName, timeoutMs }
  );
}


describe('Core Monero WASM', () => {
  let browser;
  let extPage;
  let extId;

  const EXT_PATH = path.join(__dirname, '../../build/extension');

  const TEST_SEED = 'hemlock jubilee eden hacksaw boil superior inroads epoxy exhale orders cavernous second brunt saved richly lower upgrade hitched launching deepest mostly playful layout lower eden';
  const EXPECTED_ADDRESS = '569ubRY6tYfgF3VpxQumrUCRaEtdyyh6NG8sVD3YRVVJbK1jkpJ3zq8WHLijVzodQ22LxwkdWx7fS2a6JzaRGzkNU654PZu';

  beforeAll(async () => {
    if (!fs.existsSync(EXT_PATH)) {
      throw new Error(`Extension not found at: ${EXT_PATH}. Run 'npm run build' first.`);
    }

    browser = await puppeteer.launch({
      headless: false,
      args: [
        `--disable-extensions-except=${EXT_PATH}`,
        `--load-extension=${EXT_PATH}`,
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--window-size=1280,1024'
      ],
      executablePath: process.env.CHROME_PATH || undefined,
      defaultViewport: { width: 1280, height: 1024 }
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
  }, 120000);

  afterAll(async () => {
    if (browser) await browser.close();
  });

  it('loads extension with WASM bindings', async () => {
    const result = await extPage.evaluate(() => ({
      hasWasmBindgen: typeof wasm_bindgen !== 'undefined',
      hasWasmBindings: !!(window.wasmBindings),
      hasTestApi: !!(window.wasmBindings && window.wasmBindings.TestApi),
    }));

    expect(result.hasWasmBindings || result.hasWasmBindgen).toBe(true);
    expect(result.hasTestApi).toBe(true);
  });

  it('generates valid 25-word seed', async () => {
    const seed = await extPage.evaluate(() => {
      return window.wasmBindings.TestApi.generate_seed();
    });

    const words = seed.split(' ');
    expect(words).toHaveLength(25);
    for (const word of words) {
      // 12, not 10: monero's English list holds 'demonstrate' and 'verification', and a
      // seed is 25 draws from 1626 words, so the old bound failed about one run in 33 on
      // a seed that was perfectly valid. A random input needs its assertion checked
      // against the whole domain, not against the draws that happened to come up.
      expect(word).toMatch(/^[a-z]{3,12}$/);
    }
  });

  it('derives correct address from seed', async () => {
    const address = await extPage.evaluate((seed) => {
      return window.wasmBindings.TestApi.derive_address(seed, 'stagenet');
    }, TEST_SEED);

    expect(address).toBe(EXPECTED_ADDRESS);
  });

  it('derives all keys from seed', async () => {
    const keys = await extPage.evaluate((seed) => {
      return window.wasmBindings.TestApi.derive_keys(seed, 'stagenet');
    }, TEST_SEED);

    expect(keys.address).toBeTruthy();
    expect(keys.secret_spend_key).toHaveLength(64);
    expect(keys.secret_view_key).toHaveLength(64);
    expect(keys.public_spend_key).toHaveLength(64);
    expect(keys.public_view_key).toHaveLength(64);
  });

  describe('Multi-network TestApi coverage', () => {
    it('derives distinct addresses for mainnet, stagenet, and testnet', async () => {
      const addresses = await extPage.evaluate((seed) => {
        const networks = ['mainnet', 'stagenet', 'testnet'];
        const results = {};
        for (const net of networks) {
          results[net] = window.wasmBindings.TestApi.derive_address(seed, net);
        }
        return results;
      }, TEST_SEED);

      expect(addresses.mainnet).toHaveLength(95);
      expect(addresses.stagenet).toHaveLength(95);
      expect(addresses.testnet).toHaveLength(95);
      expect(addresses.mainnet[0]).toBe('4');
      expect(addresses.stagenet[0]).toBe('5');
      expect(['9', 'A']).toContain(addresses.testnet[0]);
      expect(addresses.stagenet).toBe(EXPECTED_ADDRESS);
      const uniqueAddresses = new Set([addresses.mainnet, addresses.stagenet, addresses.testnet]);
      expect(uniqueAddresses.size).toBe(3);
    });

    it('derives keys for all three networks', async () => {
      const allKeys = await extPage.evaluate((seed) => {
        const networks = ['mainnet', 'stagenet', 'testnet'];
        const results = {};
        for (const net of networks) {
          results[net] = window.wasmBindings.TestApi.derive_keys(seed, net);
        }
        return results;
      }, TEST_SEED);

      const networks = ['mainnet', 'stagenet', 'testnet'];
      for (const net of networks) {
        const keys = allKeys[net];
        expect(keys.address).toBeTruthy();
        expect(keys.secret_spend_key).toHaveLength(64);
        expect(keys.secret_view_key).toHaveLength(64);
        expect(keys.public_spend_key).toHaveLength(64);
        expect(keys.public_view_key).toHaveLength(64);
      }

      expect(allKeys.stagenet.address).toBe(EXPECTED_ADDRESS);
      const viewKeys = new Set(networks.map(net => allKeys[net].secret_view_key));
      expect(viewKeys.size).toBe(1);
      const addresses = new Set(networks.map(net => allKeys[net].address));
      expect(addresses.size).toBe(3);
    });
  });

  describe('Wallet creation (E2E-01)', () => {
    it('signal round-trip: MoneroTestRequest receives MoneroTestResponse', async () => {
      const response = await sendSignalAndWait(
        extPage,
        'send_monero_test_request',
        JSON.stringify({}),
        'MoneroTestResponse',
        15000
      );

      expect(response).toBeDefined();
      expect(response.result).toBeDefined();
    }, 15000);

    it('creates wallet via signal and verifies address via TestApi', async () => {
      const response = await sendSignalAndWait(
        extPage,
        'send_create_wallet_request',
        JSON.stringify({ password: 'test_password', network: 'stagenet' }),
        'WalletCreatedResponse',
        15000
      );

      expect(response).toBeDefined();
      expect(response).not.toBeNull();
      expect(typeof response.address).toBe('string');

      const derivedAddress = await extPage.evaluate(
        (seed) => window.wasmBindings.TestApi.derive_address(seed, 'stagenet'),
        TEST_SEED
      );

      expect(derivedAddress).toBe(EXPECTED_ADDRESS);
    }, 20000);
  });

  describe('Wallet persistence (E2E-02)', () => {
    it('WASM bindings survive extension page reload', async () => {
      const beforeReload = await extPage.evaluate(() =>
        window.wasmBindings.TestApi.test_wasm()
      );
      expect(beforeReload).toBe('WASM OK');

      await extPage.close();
      extPage = await reloadExtensionPage(browser, extId);

      const hasBindings = await extPage.evaluate(() =>
        !!(window.wasmBindings && window.wasmBindings.TestApi)
      );
      expect(hasBindings).toBe(true);

      const afterReload = await extPage.evaluate(() =>
        window.wasmBindings.TestApi.test_wasm()
      );
      expect(afterReload).toBe('WASM OK');
      // The test's own ceiling has to sit *above* the page-load budget, or the budget
      // decides nothing: this reload was measured at 3.3s and at over 30s on identical
      // code within one session, and at 30000 the jest timeout fired first either way.
      // The spread itself is still unexplained — see SECURITY-REVIEW.md.
    }, PAGE_LOAD_BUDGET_MS + 30000);

    it('derives same address after extension reload', async () => {
      const address = await extPage.evaluate(
        (seed) => window.wasmBindings.TestApi.derive_address(seed, 'stagenet'),
        TEST_SEED
      );
      expect(address).toBe(EXPECTED_ADDRESS);
    });
  });

  describe('Key file export (E2E-03)', () => {
    it('derive_keys returns complete key material for export', async () => {
      const keys = await extPage.evaluate(
        (seed) => window.wasmBindings.TestApi.derive_keys(seed, 'stagenet'),
        TEST_SEED
      );

      expect(keys.address).toBe(EXPECTED_ADDRESS);
      expect(keys.secret_spend_key).toMatch(/^[0-9a-f]{64}$/);
      expect(keys.secret_view_key).toMatch(/^[0-9a-f]{64}$/);
      expect(keys.public_spend_key).toMatch(/^[0-9a-f]{64}$/);
      expect(keys.public_view_key).toMatch(/^[0-9a-f]{64}$/);
      expect(keys.secret_spend_key).not.toMatch(/^0+$/);
      expect(keys.secret_view_key).not.toMatch(/^0+$/);
    });

    it('key material is consistent across derivations', async () => {
      const keys1 = await extPage.evaluate(
        (seed) => window.wasmBindings.TestApi.derive_keys(seed, 'stagenet'),
        TEST_SEED
      );
      const keys2 = await extPage.evaluate(
        (seed) => window.wasmBindings.TestApi.derive_keys(seed, 'stagenet'),
        TEST_SEED
      );

      expect(keys1.address).toBe(keys2.address);
      expect(keys1.secret_spend_key).toBe(keys2.secret_spend_key);
      expect(keys1.secret_view_key).toBe(keys2.secret_view_key);
      expect(keys1.public_spend_key).toBe(keys2.public_spend_key);
      expect(keys1.public_view_key).toBe(keys2.public_view_key);
    });

    it('export signal function availability check', async () => {
      const hasExportSignal = await extPage.evaluate(() =>
        typeof window.wasmBindings.send_export_keys_file_request === 'function'
      );

      if (!hasExportSignal) {
        console.warn(
          'send_export_keys_file_request not in current WASM build — ' +
          'skipping signal-based export test. Rebuild WASM to enable.'
        );
        return;
      }

      const response = await sendSignalAndWait(
        extPage,
        'send_export_keys_file_request',
        // seed is required. Omitting it made the JSON fail to deserialise before it
        // reached the actor, so send_* returned an error, the bridge turned that into a
        // bridge-error signal nothing here listens for, and this waited out the full
        // timeout for a response that could never arrive.
        JSON.stringify({ seed: TEST_SEED, password: 'test_password', network: 'stagenet' }),
        'ExportKeysFileResponse',
        15000
      );

      expect(response).toBeDefined();
      expect(response.success).toBeDefined();
      expect(response.file_bytes_hex).toBeDefined();
    });
  });
});
