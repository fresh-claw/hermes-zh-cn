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

  const typeNext = () => {
    commandTarget.textContent = commandText.slice(0, index);
    index += 1;

    if (index <= commandText.length) {
      window.setTimeout(typeNext, 90);
      return;
    }

    window.setTimeout(() => {
      index = 0;
      commandTarget.textContent = "";
      window.setTimeout(typeNext, 420);
    }, 2200);
  };

  window.setTimeout(typeNext, 420);
}
