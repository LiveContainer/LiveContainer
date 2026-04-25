(function () {
  const BLOCKED_PROTOCOLS = new Set(["http:", "https:", "about:", "javascript:", "data:", "blob:"]);
  const ATTRIBUTE_CANDIDATES = [
    "schema",
    "data-schema",
    "deeplink",
    "deep-link",
    "deep_link",
    "data-deeplink",
    "data-deep-link",
    "data-url",
    "data-open-url",
    "data-href",
    "url",
    "href",
    "action"
  ];
  const MAX_ANCESTOR_DEPTH = 8;
  const runtimeAPI = typeof browser !== "undefined" ? browser : typeof chrome !== "undefined" ? chrome : null;
  const PAGE_LAUNCH_EVENT = "__LC_LAUNCH_REQUEST__";

  function expandCandidates(rawValue) {
    const values = new Set();

    if (typeof rawValue !== "string") {
      return [];
    }

    const trimmed = rawValue.trim();
    if (!trimmed) {
      return [];
    }

    values.add(trimmed);

    try {
      const decoded = decodeURIComponent(trimmed);
      if (decoded) {
        values.add(decoded);
      }
    } catch (_) {}

    try {
      const decoded = atob(trimmed);
      if (decoded) {
        values.add(decoded);
      }

      try {
        const twiceDecoded = decodeURIComponent(decoded);
        if (twiceDecoded) {
          values.add(twiceDecoded);
        }
      } catch (_) {}
    } catch (_) {}

    return [...values];
  }

  function extractExternalScheme(rawValue) {
    for (const candidate of expandCandidates(rawValue)) {
      try {
        const url = new URL(candidate, window.location.href);
        if (url.protocol && !BLOCKED_PROTOCOLS.has(url.protocol.toLowerCase())) {
          return url.href;
        }
      } catch (_) {}
    }

    return null;
  }

  function extractExternalSchemeFromElement(element) {
    if (!(element instanceof Element)) {
      return null;
    }

    for (const attribute of ATTRIBUTE_CANDIDATES) {
      const extracted = extractExternalScheme(element.getAttribute(attribute));
      if (extracted) {
        return extracted;
      }
    }

    return null;
  }

  function extractExternalSchemeFromTree(element) {
    let current = element;
    let depth = 0;

    while (current && depth < MAX_ANCESTOR_DEPTH) {
      const directMatch = extractExternalSchemeFromElement(current);
      if (directMatch) {
        return directMatch;
      }

      current = current.parentElement;
      depth += 1;
    }

    return null;
  }

  function requestLaunch(url) {
    if (!runtimeAPI?.runtime?.sendMessage || !url) {
      return;
    }

    runtimeAPI.runtime
      .sendMessage({
        command: "launchResolved",
        url
      })
      .catch(() => {});
  }

  function installPageLevelHooks() {
    const script = document.createElement("script");
    script.textContent = `
      (() => {
        const blockedProtocols = new Set(["http:", "https:", "about:", "javascript:", "data:", "blob:"]);
        const pageLaunchEvent = ${JSON.stringify(PAGE_LAUNCH_EVENT)};

        function expandCandidates(rawValue) {
          const values = new Set();

          if (typeof rawValue !== "string") {
            return [];
          }

          const trimmed = rawValue.trim();
          if (!trimmed) {
            return [];
          }

          values.add(trimmed);

          try {
            const decoded = decodeURIComponent(trimmed);
            if (decoded) {
              values.add(decoded);
            }
          } catch (_) {}

          try {
            const decoded = atob(trimmed);
            if (decoded) {
              values.add(decoded);
            }

            try {
              const twiceDecoded = decodeURIComponent(decoded);
              if (twiceDecoded) {
                values.add(twiceDecoded);
              }
            } catch (_) {}
          } catch (_) {}

          return [...values];
        }

        function extractExternalScheme(rawValue) {
          for (const candidate of expandCandidates(rawValue)) {
            try {
              const url = new URL(candidate, window.location.href);
              if (url.protocol && !blockedProtocols.has(url.protocol.toLowerCase())) {
                return url.href;
              }
            } catch (_) {}
          }

          return null;
        }

        function dispatchLaunchRequest(rawValue) {
          const extracted = extractExternalScheme(rawValue);
          if (!extracted) {
            return false;
          }

          window.dispatchEvent(new CustomEvent(pageLaunchEvent, {
            detail: { rawValue: extracted }
          }));
          return true;
        }

        const originalWindowOpen = window.open;
        window.open = function (url, ...args) {
          if (dispatchLaunchRequest(url)) {
            return null;
          }
          return originalWindowOpen.call(window, url, ...args);
        };

        const originalAssign = Location.prototype.assign;
        Location.prototype.assign = function (value) {
          if (dispatchLaunchRequest(value)) {
            return;
          }
          return originalAssign.call(this, value);
        };

        const originalReplace = Location.prototype.replace;
        Location.prototype.replace = function (value) {
          if (dispatchLaunchRequest(value)) {
            return;
          }
          return originalReplace.call(this, value);
        };

        const originalAnchorClick = HTMLAnchorElement.prototype.click;
        HTMLAnchorElement.prototype.click = function (...args) {
          const href = this.getAttribute("href");
          if (dispatchLaunchRequest(href)) {
            return;
          }
          return originalAnchorClick.apply(this, args);
        };

        const iframeSrcDescriptor = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, "src");
        if (iframeSrcDescriptor && typeof iframeSrcDescriptor.set === "function") {
          Object.defineProperty(HTMLIFrameElement.prototype, "src", {
            configurable: iframeSrcDescriptor.configurable,
            enumerable: iframeSrcDescriptor.enumerable,
            get: iframeSrcDescriptor.get,
            set(value) {
              if (dispatchLaunchRequest(value)) {
                return;
              }
              iframeSrcDescriptor.set.call(this, value);
            }
          });
        }

        const originalSetAttribute = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function (name, value) {
          const attrName = typeof name === "string" ? name.toLowerCase() : "";
          if (this instanceof HTMLIFrameElement && attrName === "src" && dispatchLaunchRequest(value)) {
            return;
          }
          return originalSetAttribute.call(this, name, value);
        };

        function redirectIframeIfNeeded(node) {
          if (!(node instanceof HTMLIFrameElement)) {
            return false;
          }
          return dispatchLaunchRequest(node.getAttribute("src") || node.src);
        }

        const originalAppendChild = Node.prototype.appendChild;
        Node.prototype.appendChild = function (node) {
          if (redirectIframeIfNeeded(node)) {
            return node;
          }
          return originalAppendChild.call(this, node);
        };

        const originalInsertBefore = Node.prototype.insertBefore;
        Node.prototype.insertBefore = function (node, child) {
          if (redirectIframeIfNeeded(node)) {
            return node;
          }
          return originalInsertBefore.call(this, node, child);
        };
      })();
    `;

    (document.documentElement || document.head || document.body).appendChild(script);
    script.remove();
  }

  function attemptInitialHTTPSRedirect() {
    if (window.top !== window) {
      return;
    }

    if (window.location.protocol !== "https:") {
      return;
    }

    requestLaunch(window.location.href);
  }

  function init() {
    installPageLevelHooks();

    attemptInitialHTTPSRedirect();

    window.addEventListener(PAGE_LAUNCH_EVENT, (event) => {
      const extracted = extractExternalScheme(event?.detail?.rawValue);
      if (!extracted) {
        return;
      }
      requestLaunch(extracted);
    });

    document.addEventListener(
      "click",
      (event) => {
        if (event.defaultPrevented) {
          return;
        }

        const target = event.target instanceof Element ? event.target : null;
        if (!target) {
          return;
        }

        const extracted = extractExternalSchemeFromTree(target);
        if (!extracted) {
          return;
        }

        event.preventDefault();
        event.stopPropagation();
        requestLaunch(extracted);
      },
      true
    );
  }

  init();
})();
