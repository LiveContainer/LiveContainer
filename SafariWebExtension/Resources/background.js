const runtimeAPI = typeof browser !== "undefined" ? browser : chrome;

runtimeAPI.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.command === "launchResolved") {
    runtimeAPI.runtime
      .sendNativeMessage("application.id", { command: "launchResolved", url: message.url })
      .then((response) => sendResponse({ ok: response?.ok === true }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }

  return false;
});
