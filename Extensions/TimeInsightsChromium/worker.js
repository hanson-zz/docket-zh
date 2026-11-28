const host = "com.docket_zh.time_insights";
const interval = 750;
let port;
let pending;
let busy = false;
let revision = 0;
let activeTabID;
let activeWindowID;
let lastLease;
let wakeTimer;

// Each port supports one outstanding Native Messaging request. The native host
// returns an empty lease unless Dockling has authorized the foreground browser.
function connect() {
  if (port) return port;
  const next = chrome.runtime.connectNative(host);
  port = next;
  next.onMessage.addListener(message => {
    if (port === next) pending?.(message.lease || "");
  });
  next.onDisconnect.addListener(() => {
    void chrome.runtime.lastError;
    if (port !== next) return;
    port = undefined;
    lastLease = undefined;
    pending?.("");
  });
  return next;
}

function request(message) {
  return new Promise(resolve => {
    const channel = connect();
    const timeout = setTimeout(() => {
      channel.disconnect();
      if (port === channel) port = undefined;
      lastLease = undefined;
      pending?.("");
    }, 1500);
    pending = value => {
      clearTimeout(timeout);
      pending = undefined;
      resolve(value);
    };
    try {
      channel.postMessage(message);
    } catch {
      pending("");
    }
  });
}

const protectedHosts = ["paypal.com", "stripe.com", "alipay.com", "1password.com", "bitwarden.com",
  "mail.google.com", "outlook.live.com", "outlook.office.com", "icloud.com"];
const protectedWord = /(?:^|[^a-z0-9])(?:log[\s_-]?(?:in|on)|sign[\s_-]?(?:in|up|on)|auth(?:entication|orize)?|accounts?|oauth2?|sso|register|password|passkey|checkout|billing|payments?|wallet|banking|finance|medical|health|patient|verify|verification|2fa|mfa)(?:$|[^a-z0-9])/i;
function safeHost(raw) {
  if (!raw || raw.length > 8192) return;
  try {
    const url = new URL(raw);
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) return;
    const host = url.hostname.replace(/\.$/, "");
    if (!/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$/i.test(host) ||
        /\.(?:local|localhost|internal|onion|test|invalid)$/.test(host) ||
        protectedHosts.some(blocked => host === blocked || host.endsWith("." + blocked))) return;
    const surface = decodeURIComponent(url.pathname + url.search + url.hash);
    if (protectedWord.test(host) || protectedWord.test(surface) ||
        /登录|注册|密码|支付|付款|结账|银行卡|账单|病历/.test(surface) ||
        /(?:token|session|credential|secret|api[_-]?key)[^&=]*=/i.test(surface)) return;
    return host;
  } catch {
    return undefined;
  }
}

// Runs in Chromium's isolated world. Inspect presence of form fields and page
// metadata, never field values, document text, cookies, or tab titles.
function inspectPage() {
  function protectedDocument(doc) {
    if (doc.querySelector('input[type="password" i], input[autocomplete*="password" i], input[autocomplete*="username" i], input[autocomplete*="one-time-code" i], input[autocomplete*="cc-" i], input[name*="cardnumber" i], input[name*="cvc" i], form[action*="login" i], form[action*="payment" i]')) {
      return true;
    }
    for (const frame of doc.querySelectorAll("iframe, frame")) {
      if (!frame.contentDocument || protectedDocument(frame.contentDocument)) return true;
    }
    return false;
  }
  return document.readyState !== "loading" && !protectedDocument(document);
}

async function currentTab() {
  const window = await chrome.windows.getLastFocused();
  if (!window.focused || window.type !== "normal") return;
  activeWindowID = window.id;
  if (window.incognito) return { private: true };
  const [tab] = await chrome.tabs.query({ windowId: window.id, active: true });
  activeTabID = tab?.id;
  return tab;
}

async function inspect() {
  if (busy) return;
  busy = true;
  const startingRevision = revision;
  try {
    // Visibility of private windows is required to distinguish them from a
    // regular profile's last-used window. Their tabs are never queried.
    const permitted = await chrome.extension.isAllowedIncognitoAccess() &&
      await chrome.permissions.contains({
        permissions: ["tabs", "scripting"],
        origins: ["http://*/*", "https://*/*"]
      });
    const lease = await request({ status: permitted ? "ready" : "permission" });
    lastLease = lease || undefined;
    if (!lease || startingRevision !== revision) return;

    let tab;
    let domain;
    let status = "tab";
    try {
      tab = await currentTab();
      if (!tab) {
        status = "unfocused";
      } else if (!tab.incognito && !tab.private && tab.status === "complete") {
        domain = safeHost(tab.url);
        if (domain) {
          const [result] = await chrome.scripting.executeScript({
            target: { tabId: tab.id }, func: inspectPage
          });
          const latest = await currentTab();
          if (result?.result !== true || latest?.id !== tab.id ||
              latest.url !== tab.url || latest.status !== "complete") domain = undefined;
        }
      }
    } catch {
      domain = undefined;
    }
    if (startingRevision === revision) {
      await request({ status, lease, observed: Date.now(), ...(domain ? { domain } : {}) });
    }
  } catch {
    lastLease = undefined;
  } finally {
    busy = false;
    if (startingRevision !== revision) schedule();
  }
}

let clearAt;
async function update() {
  if (busy) return;
  if (clearAt && lastLease) {
    const observed = clearAt;
    clearAt = undefined;
    busy = true;
    try {
      await request({ status: "unfocused", lease: lastLease, observed });
    } finally {
      busy = false;
    }
  } else {
    clearAt = undefined;
  }
  await inspect();
}

function schedule() {
  if (wakeTimer !== undefined) return;
  wakeTimer = setTimeout(() => {
    wakeTimer = undefined;
    void update();
  }, 0);
}

function changed() {
  revision += 1;
  clearAt ??= Date.now();
  schedule();
}

chrome.tabs.onActivated.addListener(({ windowId }) => {
  if (windowId === activeWindowID) changed();
});
chrome.tabs.onUpdated.addListener((id, change) => {
  if (id === activeTabID && (change.url !== undefined || change.status === "loading")) changed();
});
chrome.tabs.onRemoved.addListener(id => {
  if (id === activeTabID) changed();
});
chrome.windows.onFocusChanged.addListener(changed);
chrome.permissions.onAdded.addListener(changed);
chrome.permissions.onRemoved.addListener(changed);
chrome.runtime.onStartup.addListener(schedule);
chrome.runtime.onInstalled.addListener(schedule);
setInterval(() => void update(), interval);
schedule();
