const copyButtons = document.querySelectorAll("[data-copy]");

copyButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    const value = button.getAttribute("data-copy") || "";
    try {
      await navigator.clipboard.writeText(value);
      const old = button.textContent;
      button.textContent = "已复制";
      setTimeout(() => {
        button.textContent = old || "复制";
      }, 1200);
    } catch {
      button.textContent = "复制失败";
    }
  });
});

const commandTarget = document.querySelector("#typed-command");
const commandText = "请访问 useai.live/hermes 安装汉化补丁";
const installCountTarget = document.querySelector("[data-install-count]");

const formatCount = (value) => {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 10000) {
    return "10,000";
  }
  return new Intl.NumberFormat("en-US").format(Math.round(number));
};

const renderInstallCount = (value) => {
  if (installCountTarget) {
    installCountTarget.textContent = formatCount(value);
  }
};

if (installCountTarget) {
  renderInstallCount(window.__XIAOMA_HERMES_METRIC_TOTAL__ || 10000);
  const event = window.__XIAOMA_HERMES_VIEW_RECORDED__ ? "status" : "view";
  fetch(`./api/metrics.php?event=${event}&t=${Date.now()}`, {
    cache: "no-store",
    headers: { Accept: "application/json" },
  })
    .then((response) => (response.ok ? response.json() : null))
    .then((data) => {
      if (data && data.ok) {
        renderInstallCount(data.total);
      }
    })
    .catch(() => {});
}

if (commandTarget) {
  let index = 0;
  let deleting = false;

  const typeNext = () => {
    commandTarget.textContent = commandText.slice(0, index);

    if (!deleting && index < commandText.length) {
      index += 1;
      window.setTimeout(typeNext, 74);
      return;
    }

    if (!deleting) {
      deleting = true;
      window.setTimeout(typeNext, 850);
      return;
    }

    if (index > 0) {
      index -= 1;
      window.setTimeout(typeNext, 24);
      return;
    }

    deleting = false;
    window.setTimeout(typeNext, 360);
  };

  window.setTimeout(typeNext, 280);
}
