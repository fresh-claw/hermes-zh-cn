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
const commandText = "请访问 useai.live/hermes 安装汉化";

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
