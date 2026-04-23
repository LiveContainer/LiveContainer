const runtimeAPI = typeof browser !== "undefined" ? browser : chrome;

runtimeAPI.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.command === "getLaunchMap") {
    runtimeAPI.runtime
      .sendNativeMessage("application.id", { command: "getLaunchMap" })
      .then((response) => sendResponse({ ok: true, launchMap: response?.launchMap || {} }))
      .catch(() => sendResponse({ ok: true, launchMap: {} }));
    return true;
  }

  return false;
});
