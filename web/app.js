const copyButtons = document.querySelectorAll("[data-copy]");
const themeChoices = document.querySelectorAll("[data-theme-choice]");
const themeStorageKey = "xiaoma-hermes-theme-v2";
const allowedThemes = new Set(["violet", "orange"]);
const finePointer = window.matchMedia("(pointer: fine)");

const getStoredTheme = () => {
  try {
    const value = localStorage.getItem(themeStorageKey);
    return allowedThemes.has(value) ? value : "orange";
  } catch {
    return "orange";
  }
};

const setTheme = (theme) => {
  const nextTheme = allowedThemes.has(theme) ? theme : "orange";
  document.documentElement.dataset.theme = nextTheme;
  themeChoices.forEach((button) => {
    const active = button.getAttribute("data-theme-choice") === nextTheme;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", active ? "true" : "false");
  });
  try {
    localStorage.setItem(themeStorageKey, nextTheme);
  } catch {}
};

if (themeChoices.length) {
  setTheme(getStoredTheme());
  themeChoices.forEach((button) => {
    button.addEventListener("click", () => {
      setTheme(button.getAttribute("data-theme-choice"));
    });
  });
}

const updatePointerVars = (event) => {
  if (!finePointer.matches) {
    return;
  }

  const x = ((event.clientX / window.innerWidth) - 0.5) * 18;
  const y = ((event.clientY / window.innerHeight) - 0.5) * 18;
  document.documentElement.style.setProperty("--pointer-x", `${x.toFixed(2)}px`);
  document.documentElement.style.setProperty("--pointer-y", `${y.toFixed(2)}px`);
};

window.addEventListener("pointermove", updatePointerVars, { passive: true });

if (finePointer.matches) {
  const cursorOrb = document.createElement("div");
  cursorOrb.className = "cursor-orb";
  cursorOrb.setAttribute("aria-hidden", "true");
  document.body.prepend(cursorOrb);

  let orbX = window.innerWidth / 2;
  let orbY = window.innerHeight / 2;
  let raf = 0;

  const renderCursorOrb = () => {
    raf = 0;
    cursorOrb.style.left = `${orbX}px`;
    cursorOrb.style.top = `${orbY}px`;
  };

  window.addEventListener(
    "pointermove",
    (event) => {
      orbX = event.clientX;
      orbY = event.clientY;
      cursorOrb.classList.add("is-active");
      if (!raf) {
        raf = window.requestAnimationFrame(renderCursorOrb);
      }
    },
    { passive: true }
  );

  window.addEventListener("pointerleave", () => {
    cursorOrb.classList.remove("is-active");
  });
}

const fallbackCopy = (value) => {
  const textarea = document.createElement("textarea");
  textarea.value = value;
  textarea.setAttribute("readonly", "readonly");
  textarea.style.position = "fixed";
  textarea.style.left = "-9999px";
  textarea.style.top = "0";
  document.body.appendChild(textarea);
  textarea.select();
  textarea.setSelectionRange(0, textarea.value.length);
  let copied = false;
  try {
    copied = document.execCommand("copy");
  } catch {
    copied = false;
  }
  textarea.remove();
  return copied;
};

const selectCommandText = (button) => {
  const commandText = button.closest(".command-input")?.querySelector("code");
  if (!commandText) {
    return false;
  }
  const range = document.createRange();
  range.selectNodeContents(commandText);
  const selection = window.getSelection();
  if (!selection) {
    return false;
  }
  selection.removeAllRanges();
  selection.addRange(range);
  return true;
};

copyButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    const value = button.getAttribute("data-copy") || "";
    const old = button.textContent;
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(value);
      } else if (!fallbackCopy(value)) {
        throw new Error("copy failed");
      }
      button.textContent = "已复制";
      setTimeout(() => {
        button.textContent = old || "复制";
      }, 1200);
    } catch {
      if (selectCommandText(button)) {
        button.textContent = "已选中";
        setTimeout(() => {
          button.textContent = old || "复制";
        }, 1400);
        return;
      }
      button.textContent = "请长按";
      setTimeout(() => {
        button.textContent = old || "复制";
      }, 1400);
    }
  });
});

const commandTarget = document.querySelector("#typed-command");
const commandText = "请访问 useai.live/hermes 安装桌面版或 TUI 汉化补丁";
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
