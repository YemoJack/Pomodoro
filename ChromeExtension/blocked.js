const button = document.querySelector("#allow");
const heading = document.querySelector("h1");
const status = document.querySelector("#status");

function destination() {
  try {
    const url = new URL(location.hash.slice(1));
    if (["https:", "http:"].includes(url.protocol) && !url.username && !url.password) {
      return new URL(url.origin);
    }
  } catch {
    return null;
  }
  return null;
}

const site = destination();
let blocked = true;
let opening = false;
let revision = 0;

async function refresh() {
  if (!site) return;
  const check = ++revision;
  const result = await chrome.runtime.sendMessage({ type: "check" }).catch(() => null);
  if (check !== revision || !result) return;
  blocked = Boolean(result.endsAt);
  if (!blocked && opening) location.replace(site.href);
  heading.textContent = blocked ? "网站在专注中受限" : "网站已解锁";
  button.textContent = blocked ? "临时放行 2 分钟" : "打开网站";
  button.disabled = opening && blocked;
  status.hidden = true;
}

if (site) {
  document.querySelector("#host").textContent = site.host;
  button.addEventListener("click", async (event) => {
    if (!event.isTrusted) return;
    if (!blocked) {
      location.replace(site.href);
      return;
    }
    opening = true;
    button.disabled = true;
    await chrome.runtime.sendMessage({ type: "allow" }).catch(() => null);
    await refresh();
    if (blocked) {
      setTimeout(async () => {
        await refresh();
        if (blocked) {
          opening = false;
          button.disabled = false;
          status.textContent = "暂时无法放行，请重试。";
          status.hidden = false;
        }
      }, 1800);
    }
  });
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "session" && changes.focusState) void refresh();
  });
  void refresh();
}
