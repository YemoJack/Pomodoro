(() => {
  if (globalThis.pomodoroFocusOverlay) return;
  globalThis.pomodoroFocusOverlay = true;

  let mounted;
  let expiry;
  let policy = 0;

  function dismiss() {
    clearTimeout(expiry);
    if (!mounted) return;
    mounted.dialog.close();
    mounted.host.remove();
    mounted = null;
  }

  function show(endsAt) {
    clearTimeout(expiry);
    if (!endsAt || endsAt <= Date.now()) {
      dismiss();
      return;
    }
    expiry = setTimeout(dismiss, endsAt - Date.now());
    if (mounted) return;

    const host = document.createElement("div");
    const shadow = host.attachShadow({ mode: "closed" });
    const style = new CSSStyleSheet();
    style.replaceSync(`
      dialog {
        box-sizing: border-box; color-scheme: light dark; color: CanvasText; background: Canvas;
        border: 1px solid color-mix(in srgb, CanvasText 20%, Canvas);
        border-radius: 18px; padding: 28px; max-width: calc(100vw - 2rem);
        font: 16px system-ui; overscroll-behavior: contain;
      }
      dialog::backdrop { background: #161921; overflow: hidden; overscroll-behavior: contain; }
      h1 { font-size: 22px; margin: 0 0 8px; }
      p { margin: 0 0 20px; overflow-wrap: anywhere; }
      button { font: inherit; padding: 8px 14px; cursor: pointer; }
    `);
    shadow.adoptedStyleSheets = [style];
    const dialog = document.createElement("dialog");
    dialog.setAttribute("closedby", "none");
    dialog.setAttribute("aria-labelledby", "pomodoro-title");
    dialog.addEventListener("cancel", (event) => event.preventDefault());

    const title = document.createElement("h1");
    title.id = "pomodoro-title";
    title.textContent = "网站在专注中受限";
    const target = document.createElement("p");
    target.textContent = location.hostname;
    const allow = document.createElement("button");
    allow.textContent = "临时放行 2 分钟";
    allow.autofocus = true;
    allow.addEventListener("click", async (event) => {
      if (!event.isTrusted) return;
      allow.disabled = true;
      const result = await chrome.runtime.sendMessage({ type: "allow" }).catch(() => null);
      if (!result?.endsAt) await refresh();
      setTimeout(() => { allow.disabled = false; }, 800);
    });

    dialog.append(title, target, allow);
    shadow.append(dialog);
    document.documentElement.append(host);
    dialog.showModal();
    mounted = { host, dialog };
  }

  function update(endsAt) {
    const revision = ++policy;
    if (document.documentElement) {
      show(endsAt);
    } else {
      document.addEventListener("DOMContentLoaded", () => {
        if (revision === policy) show(endsAt);
      }, { once: true });
    }
  }

  async function refresh() {
    const revision = policy;
    const result = await chrome.runtime.sendMessage({ type: "check" }).catch(() => null);
    if (revision === policy) update(result?.endsAt);
  }

  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === "policy") update(message.endsAt);
  });
  window.addEventListener("pageshow", refresh);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) void refresh();
  });
  void refresh();
})();
