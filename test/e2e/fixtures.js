
const NODE_URL = process.env.STAGENET_NODE_URL || 'http://127.0.0.1:38081';
/** Shared E2E test fixtures: wallet constants, signal helpers, node probe. */

// Primary test wallet with verified stagenet outputs
const HONKED_SEED = 'honked bagpipe alpine juicy faked afoot jostle claim cowl tunnel orphans negative pheasants feast jetting quote frown teeming cycling tribal womanly hills cottage daytime daytime';
const HONKED_ADDRESS = '58aWiYGUeqZc5idYcx31rYR58K1EVsCYkN6thrZppU1MGqMowPh1BYy4frVWH5RjGLPWthZy9sRGm5ZC4fgX44HUCmqtGUf';

// Test wallet used in core_functionality.test.js
const HEMLOCK_SEED = 'hemlock jubilee eden hacksaw boil superior inroads epoxy exhale orders cavernous second brunt saved richly lower upgrade hitched launching deepest mostly playful layout lower eden';
const HEMLOCK_ADDRESS = '569ubRY6tYfgF3VpxQumrUCRaEtdyyh6NG8sVD3YRVVJbK1jkpJ3zq8WHLijVzodQ22LxwkdWx7fS2a6JzaRGzkNU654PZu';

// BIP39 test mnemonic
const BIP39_TEST_MNEMONIC = 'color ranch color remove subway public water embrace before begin liberty fault';

// Synthetic unsigned TX hex for offline signing tests
const UNSIGNED_TX_HEX = '0010424242424242424242424242424242424242424242424242424242424242424200e1f5050000000002005f353861576959475565715a63356964596378333172595235384b3145567343596b4e367468725a707055314d47714d6f7750683142597934667256574835526a474c505774685a79397352476d355a433466675834344855436d71744755660040b743ba000000015f34384e5564684d5831455463356964596378333172595235384b3145567343596b4e367468725a707055314d47714d6f7750683142597934667256574835526a474c505774685a79397352476d355a43346667583434485543714463536a58015c356a10ea89d4ca34efbbafe4a820d89aa7f0356bf82670d228e44f67f6e30100eff78a2e0000000001aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa00bb8441d6bd13c0e4f3f0866ae17d8f31db964751e9577fcec87f1daefcec18a4010101010101010101010101010101010101010101010101010101010101010105050505050505050505050505050505050505050505050505050505050505050010a5d4e80000000000000000000000000000000050c30000000000000010d0860364646464646464646464646464646410bb8441d6bd13c0e4f3f0866ae17d8f31db964751e9577fcec87f1daefcec18a45c46896385ff4540620fbb4a359354add8603ce7fbb05aafca98c7d3f406762c857eed804ff087b97f87848f6493e87257a8c5203cb9f422f6e7a7d8a4d299f362485ef787a6ec0fabc79c76d19b87aa1d9381172fc3d14796448c6c44065ef285ce3cf603efcf45b599cce75369e854823864e471ad297d955f32db0ade7d425cc6b0877c06c9e62f3485e89a0e1f1bada60a990a70eb9dd0c22042bbcf6f93980052c1e22f4f2deb0956e62bc712140f2dd568413b02080de278c6a82fcb3de24e118f1a04aa0ad0032b9ab94e4952b5182b10820af934c0f5c80bf7be53a4a49de455dc6038523d5d447da6bc65a3c06454dd9f56f2d42afea0c880ce183f21908bd22ea2a33b290e50e4b60c107db274a4e8c7818c72afbb289e5b7ae90dd171c476742a5ebb9458ca0198bef0031ac79b5c6188fdfe6edf658749adb811bddd1857a540b1f59433e73308eec57aa84368cc6ef0809362023ac6bdd3482c52bf047c41c99269edae7bdd2a6527c213df89929e465647c9b52b0b2dd84d3a0559b76f74e64c3cd7f32e94b8fa98a7f4a009e6497aaa2200a7403dc00b1ef26440a777a0e2c880f8d10491d4435da40c08a8cdb40599b6d958ec8b161ef597fd32d621c1d87592fc6c1e4895121f8cd17e76c6bee017106c83c2ed893d3d6ac5ea64522efd11fe323d2ccc22a6320a9fae8252ab4a5f5e022b72b994f707a5ecf6f01ba7b538a53b59295bb0b83717f9c9299b97596c317e028735364743094704c71f41db8ea6a6811f019b1a08d6a960d44984701e43eea752ff9483ce02b482f1ebc441fef4d4e83a552c1e9559371011f0695495a8e729b21eaeea6685cb90b4ba5a6ad4bf86ffef1535b4237eba1ed085200f49b0e05fe0e71f76c5b01e8efe7091cfc4a4ce01365c95ceed5bb9fb36ef0c8137a0fdd6ee9fda0c35d2e0231af5f56fe4752c17edb2cd57f041940266a7d2f676260d7a8951d20026e98ab1e3b96aa14aa7cd6f4109752bcd4d77d8028085b01712d08c52d62f9124c065a5a4e04068d3590afbacf74e354e1fc2aaa9c845afaa32c34f230c8f2981750d0a77bb481eeda7e5204eb5c8552e455c3acecbcd7befcef113335074a85ecae6cbbc35d30de7e11a87ac6d03a2c696b351cf21dbedcd2c1e123e9fc8a4eb8f7ea7e0271ac3cb76fadbdf643ad8d4b2e941b16a208488f996cd3e3b1f064fdc697419e53c4a50c7936d3645265b4a683dca075c10c5ad074652a349e5aff58cd553b0226126e6dd9012d7c4d09a2b0851db158aea2638bc007c2454fda63555ee9f23fb37a204fc7b6fe7effc6820de222f4a2a118dc07966847f28454976485283424415985c30f0c3b44efe37c7c21bdf58db461d019cae38ad6fdf7b257e';

/**
 * Whether a node answered, decided at require() time.
 *
 * This has to be synchronous, and that is the whole point. Jest evaluates describe
 * bodies during registration, before any beforeAll runs, so a `nodeAvailable` set in
 * beforeAll is still false when `describeIfNode = nodeAvailable ? describe : describe.skip`
 * is evaluated. That gate was therefore always describe.skip and the tests behind it could
 * never run — not "were skipped because no node", but *could not run at all*, even with a
 * node verified reachable in 128ms.
 *
 * Node has no synchronous HTTP, so this spawns a short-lived child to do the request.
 * ~50ms once per test file, which is cheap against a suite that launches Chrome.
 */
function probeNodeSync(url = NODE_URL + '/get_info', timeoutMs = 8000) {
  const { execFileSync } = require('child_process');
  const script =
    "const http=require('http');" +
    "const req=http.get(process.argv[1],{timeout:Number(process.argv[2])},(r)=>{" +
    "r.resume();process.stdout.write(r.statusCode===200?'1':'0');process.exit(0);});" +
    "req.on('error',()=>{process.stdout.write('0');process.exit(0);});" +
    "req.on('timeout',()=>{req.destroy();process.stdout.write('0');process.exit(0);});";
  try {
    const out = execFileSync(process.execPath, ['-e', script, url, String(timeoutMs)], {
      encoding: 'utf8',
      timeout: timeoutMs + 4000,
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return out.trim() === '1';
  } catch {
    return false;
  }
}

const NODE_AVAILABLE = probeNodeSync();

/** Returns true if the stagenet node at `url` responds with HTTP 200. */
function probeNode(url = NODE_URL + '/get_info', timeoutMs = 3000) {
  const http = require('http');
  return new Promise((resolve) => {
    const req = http.get(url, { timeout: timeoutMs }, (res) => {
      res.resume();
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

function jsonRpcUrl(nodeUrl) {
  const trimmed = nodeUrl.replace(/\/+$/, '');
  return trimmed.endsWith('/json_rpc') ? trimmed : `${trimmed}/json_rpc`;
}

function rpcUrl(nodeUrl, path) {
  const trimmed = nodeUrl.replace(/\/+$/, '');
  const base = trimmed.endsWith('/json_rpc') ? trimmed.slice(0, -'/json_rpc'.length) : trimmed;
  return `${base}${path}`;
}

function callJsonRpc(nodeUrl, method, params = {}, timeoutMs = 10000) {
  const http = require('http');
  const payload = JSON.stringify({
    jsonrpc: '2.0',
    id: '0',
    method,
    params,
  });
  const rpcUrl = new URL(jsonRpcUrl(nodeUrl));

  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: rpcUrl.hostname,
        port: rpcUrl.port || 80,
        path: rpcUrl.pathname,
        method: 'POST',
        timeout: timeoutMs,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => {
          if (res.statusCode !== 200) {
            reject(new Error(`RPC ${method} failed with HTTP ${res.statusCode}: ${body}`));
            return;
          }
          try {
            const parsed = JSON.parse(body);
            if (parsed.error) {
              reject(new Error(`RPC ${method} returned error: ${JSON.stringify(parsed.error)}`));
              return;
            }
            resolve(parsed.result || {});
          } catch (error) {
            reject(new Error(`RPC ${method} returned invalid JSON: ${error.message}`));
          }
        });
      }
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy(new Error(`RPC ${method} timed out after ${timeoutMs}ms`));
    });
    req.write(payload);
    req.end();
  });
}

function callRpc(nodeUrl, path, params = {}, timeoutMs = 10000) {
  const http = require('http');
  const payload = JSON.stringify(params);
  const endpoint = new URL(rpcUrl(nodeUrl, path));

  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: endpoint.hostname,
        port: endpoint.port || 80,
        path: endpoint.pathname,
        method: 'POST',
        timeout: timeoutMs,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => {
          if (res.statusCode !== 200) {
            reject(new Error(`RPC ${path} failed with HTTP ${res.statusCode}: ${body}`));
            return;
          }
          try {
            resolve(JSON.parse(body));
          } catch (error) {
            reject(new Error(`RPC ${path} returned invalid JSON: ${error.message}`));
          }
        });
      }
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy(new Error(`RPC ${path} timed out after ${timeoutMs}ms`));
    });
    req.write(payload);
    req.end();
  });
}

async function flushDoNotRelayTransactions(nodeUrl = NODE_URL) {
  const pool = await callRpc(nodeUrl, '/get_transaction_pool');
  const txIds = (pool.transactions || [])
    .filter((tx) => tx.do_not_relay)
    .map((tx) => tx.id_hash);

  if (!txIds.length) {
    return [];
  }

  await callJsonRpc(nodeUrl, 'flush_txpool', { txids: txIds });
  return txIds;
}

// Scanning from LIVE_TX_SCAN_START_HEIGHT to the stagenet tip is ~130k blocks. Against a
// local node that is quick; against a public one over the internet it is not, and 120s was
// not enough. Overridable so a slow remote node does not look like a product failure —
// these tests only register at all when a node is configured, so a longer ceiling costs the
// default run nothing.
// 120000 was marginal, not wrong: the same ~130k-block scan finished in 31s on one run and
// blew past 130s on another, so the failures looked deterministic and were not. This is a
// ceiling, not a delay — a scan that finishes in 31s still takes 31s.
const SCAN_TIMEOUT_MS = Number(process.env.E2E_SCAN_TIMEOUT_MS || 300000);

// Building a transaction fetches ring members over RPC, so it is latency-bound the same way
// the scan is. 60s was enough locally and not against a public node — one run finished tx
// creation in 31s total and another spent the whole 60s on this step alone.
const TX_TIMEOUT_MS = Number(process.env.E2E_TX_TIMEOUT_MS || 120000);

async function waitForScanCompletion(page, requestJson, timeoutMs = SCAN_TIMEOUT_MS) {
  await page.waitForFunction(
    () =>
      !!window.wasmBindings &&
      typeof window.wasmBindings.register_rust_signal_callback === 'function',
    { timeout: timeoutMs }
  );

  return page.evaluate(
    ({ requestJson, timeoutMs }) => {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(
          () => reject(new Error(`Timeout waiting for SyncProgressResponse after ${timeoutMs}ms`)),
          timeoutMs
        );

        const origCallback = window._rustSignalCallback;
        window.wasmBindings.register_rust_signal_callback((typeName, json) => {
          if (origCallback) {
            try { origCallback(typeName, json); } catch (e) { /* ignore */ }
          }

          if (typeName !== 'SyncProgressResponse') {
            return;
          }

          const message = JSON.parse(json);
          if (message.is_scanning === false) {
            clearTimeout(timeout);
            resolve(message);
          }
        });

        window.wasmBindings.send_start_continuous_scan_request(requestJson);
      });
    },
    { requestJson, timeoutMs }
  );
}

// ---------------------------------------------------------------------------
// Signal round-trip helper
// ---------------------------------------------------------------------------

/** Send `signalFnName` and resolve when `responseTypeName` is received. */
async function sendSignalAndWait(page, signalFnName, requestJson, responseTypeName, timeoutMs = 10000) {
  await page.waitForFunction(
    () =>
      !!window.wasmBindings &&
      typeof window.wasmBindings.register_rust_signal_callback === 'function',
    { timeout: timeoutMs }
  );

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

/**
 * Navigate to a fresh extension page and wait for WASM initialization.
 *
 * The navigation timeout is explicit because puppeteer's 30s default was a race, not
 * headroom. After the oversized-history test puts four wallets of 3,200 outputs each into
 * IndexedDB, this reload was measured at 2.7s, 27.6s, and over 30s on different runs of
 * the same code — so whether the suite passed came down to timing rather than behaviour.
 * The spread is the interesting part and is not explained here; a reload that sometimes
 * takes ten times as long as others is worth profiling on its own.
 */
const PAGE_LOAD_BUDGET_MS = Number(process.env.E2E_PAGE_LOAD_TIMEOUT_MS || 90000);

async function reloadExtensionPage(browser, extId) {
  const newPage = await browser.newPage();
  await newPage.goto(`chrome-extension://${extId}/index.html`, {
    timeout: PAGE_LOAD_BUDGET_MS,
  });
  await newPage.waitForSelector('flt-glass-pane', { timeout: PAGE_LOAD_BUDGET_MS });
  await newPage.waitForFunction(
    () =>
      !!window.wasmBindings &&
      typeof window.wasmBindings.register_rust_signal_callback === 'function',
    { timeout: PAGE_LOAD_BUDGET_MS }
  );
  return newPage;
}

module.exports = {
  HONKED_SEED, HONKED_ADDRESS,
  HEMLOCK_SEED, HEMLOCK_ADDRESS,
  BIP39_TEST_MNEMONIC,
  UNSIGNED_TX_HEX,
  sendSignalAndWait,
  reloadExtensionPage,
  probeNode,
  NODE_AVAILABLE,
  NODE_URL,
  flushDoNotRelayTransactions,
  waitForScanCompletion,
  SCAN_TIMEOUT_MS,
  TX_TIMEOUT_MS,
};
