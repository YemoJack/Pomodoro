const origins = ["http://*/*", "https://*/*"];
const connect = document.querySelector("#connect");
const status = document.querySelector("#status");

async function update() {
  const granted = await chrome.permissions.contains({ origins });
  connect.textContent = granted ? "重新连接 Pomodoro" : "授权网站访问";
}

connect.addEventListener("click", async () => {
  try {
    if (await chrome.permissions.request({ origins })) {
      await chrome.runtime.sendMessage({ type: "connect" });
      status.hidden = true;
      await update();
    }
  } catch {
    status.textContent = "连接失败，请确认已在 Pomodoro 注册本机连接。";
    status.hidden = false;
  }
});

void update();
