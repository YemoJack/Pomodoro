const origins = ["http://*/*", "https://*/*"];
const scriptID = "pomodoro-overlay";
const hostName = "com.ruidouwang.pomodoro.focus";
const blockedPage = chrome.runtime.getURL("blocked.html");
const expiryAlarm = "pomodoro-expiry";
const retryAlarm = "pomodoro-reconnect";
const redirectPattern = String.raw`^(https?)://(?:[^/?#@]+@)?(\[[0-9a-f:.]+\]|[^/:?#@]+)(:[0-9]+)?(?:[/?#].*)?$`;

let port;
let queue = Promise.resolve();

function serialize(operation) {
  const result = queue.then(operation);
  queue = result.catch((error) => console.error("Pomodoro:", error.message));
  return result;
}

function toURL(value) {
  try {
    const url = new URL(value);
    return ["http:", "https:"].includes(url.protocol) ? url : null;
  } catch {
    return null;
  }
}

function hostOf(url) {
  return url.hostname.replace(/\.+$/, "");
}

function liveState(state) {
  if (!state || state.endsAt <= Date.now()) return null;
  if (state.exception?.endsAt <= Date.now()) return { ...state, exception: null };
  return state;
}

function denies(state, host) {
  if (!state || state.exception?.host === host) return false;
  const matches = state.domains.some((domain) => host === domain || host.endsWith("." + domain));
  return state.mode === "allow" ? !matches : matches;
}

function rulesFor(state) {
  if (!state) return [];
  const domainField = state.mode === "allow" ? "excludedRequestDomains" : "requestDomains";
  const rules = [{
    id: 1,
    priority: 1,
    action: {
      type: "redirect",
      redirect: { regexSubstitution: blockedPage + String.raw`#\1://\2\3` },
    },
    condition: {
      [domainField]: state.domains,
      regexFilter: redirectPattern,
      resourceTypes: ["main_frame"],
    },
  }];

  if (state.exception) {
    const exactHost = state.exception.host.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    rules.push({
      id: 2,
      priority: 2,
      action: { type: "allow" },
      condition: {
        regexFilter: String.raw`^https?://(?:[^/?#@]+@)?${exactHost}\.?(:[0-9]+)?([/?#]|$)`,
        resourceTypes: ["main_frame"],
      },
    });
  }
  return rules;
}

async function applyState(incoming) {
  const state = liveState(incoming);
  const { focusState } = await chrome.storage.session.get("focusState");
  if (state && JSON.stringify(state) === JSON.stringify(focusState)) return;

  try {
    await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: [1, 2], addRules: rulesFor(state) });
  } catch (error) {
    if (state) await applyState(null);
    throw error;
  }
  await chrome.storage.session.set({ focusState: state });
  await chrome.alarms.clear(expiryAlarm);
  if (state) {
    await chrome.alarms.create(expiryAlarm, { when: Math.min(state.endsAt, state.exception?.endsAt ?? Infinity) });
  }

  const tabs = await chrome.tabs.query(state ? { url: origins } : {});
  await Promise.allSettled(tabs.map((tab) => {
    const url = toURL(tab.url);
    const endsAt = url && denies(state, hostOf(url)) ? state.endsAt : null;
    return chrome.tabs.sendMessage(tab.id, { type: "policy", endsAt }, { frameId: 0 });
  }));
}

async function syncPermission() {
  const ready = await chrome.permissions.contains({ origins });
  const scripts = await chrome.scripting.getRegisteredContentScripts({ ids: [scriptID] });
  if (ready && scripts.length === 0) {
    await chrome.scripting.registerContentScripts([{
      id: scriptID, js: ["overlay.js"], matches: origins,
      runAt: "document_start", persistAcrossSessions: true,
    }]);
    const tabs = await chrome.tabs.query({ url: origins });
    await Promise.allSettled(tabs.map((tab) => chrome.scripting.executeScript({
      target: { tabId: tab.id }, files: ["overlay.js"],
    })));
  } else if (!ready) {
    if (scripts.length) await chrome.scripting.unregisterContentScripts({ ids: [scriptID] });
    await applyState(null);
  }

  if (!port) {
    const connection = chrome.runtime.connectNative(hostName);
    port = connection;
    connection.onMessage.addListener((reply) => {
      if (reply.version !== 1 || port !== connection) return;
      void serialize(async () => {
        if (port === connection && await chrome.permissions.contains({ origins })) {
          await applyState(reply.state);
        }
      });
    });
    connection.onDisconnect.addListener(() => {
      if (port !== connection) return;
      void chrome.runtime.lastError;
      port = null;
      void serialize(() => applyState(null));
    });
  }
  port.postMessage({ ready });
  return ready;
}

chrome.runtime.onStartup.addListener(() => { void serialize(syncPermission); });
chrome.permissions.onAdded.addListener(() => { void serialize(syncPermission); });
chrome.permissions.onRemoved.addListener(() => { void serialize(syncPermission); });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === retryAlarm && !port) void serialize(syncPermission);
  if (alarm.name === expiryAlarm) {
    void serialize(async () => {
      const { focusState } = await chrome.storage.session.get("focusState");
      await applyState(focusState);
    });
  }
});

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  const url = toURL(sender.url);
  const fromPage = url && sender.frameId === 0;
  const fromBlockPage = sender.frameId === 0 && sender.url?.split("#", 1)[0] === blockedPage;
  const fromPopup = sender.url === chrome.runtime.getURL("popup.html");

  if (message.type === "connect" && fromPopup) {
    void serialize(syncPermission).then((ready) => reply({ ready }), () => reply({ ready: false }));
    return true;
  }
  if (!(fromPage || fromBlockPage) || !["check", "allow"].includes(message.type)) return false;
  void serialize(async () => {
    const target = fromPage ? url : toURL(sender.url.slice(blockedPage.length + 1));
    const { focusState } = await chrome.storage.session.get("focusState");
    const state = liveState(focusState);
    const host = target && hostOf(target);
    const blocked = host && denies(state, host);
    if (message.type === "allow" && blocked && port) {
      port.postMessage({ ready: true, host, roundID: state.roundID });
    }
    return { endsAt: blocked ? state.endsAt : null, pending: Boolean(blocked && port) };
  }).then(reply, () => reply({ endsAt: null, pending: false }));
  return true;
});

void serialize(async () => {
  await applyState(null);
  await chrome.alarms.create(retryAlarm, { periodInMinutes: 0.5 });
  await syncPermission();
});
