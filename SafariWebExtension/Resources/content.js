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

  function resolveURL(rawValue) {
    try {
      return new URL(rawValue, window.location.href).href;
    } catch (_) {
      return null;
    }
  }

  function extractExternalScheme(rawValue) {
    for (const candidate of expandCandidates(rawValue)) {
      const resolved = resolveURL(candidate);
      if (!resolved) {
        continue;
      }

      try {
        const protocol = new URL(resolved).protocol.toLowerCase();
        if (!BLOCKED_PROTOCOLS.has(protocol)) {
          return resolved;
        }
      } catch (_) {}
    }

    return null;
  }

  function encodeBase64(value) {
    return btoa(unescape(encodeURIComponent(value)));
  }

  function buildOpenURL(rawValue) {
    return `livecontainer://open-url?url=${encodeURIComponent(encodeBase64(rawValue))}`;
  }

  function buildDirectLaunchURL(extracted, bundleName) {
    const query = new URLSearchParams();
    query.set("bundle-name", bundleName);
    query.set("open-url", encodeBase64(extracted));
    return `livecontainer://livecontainer-launch?${query.toString()}`;
  }

  function resolveLaunchTarget(rawValue, launchMap) {
    const extracted = extractExternalScheme(rawValue);
    if (!extracted) {
      return null;
    }

    let scheme = null;
    try {
      scheme = new URL(extracted).protocol.replace(/:$/, "").toLowerCase();
    } catch (_) {
      return { type: "open", extracted, url: buildOpenURL(extracted) };
    }

    const bundleName = launchMap?.[scheme];
    if (!bundleName) {
      return { type: "open", extracted, url: buildOpenURL(extracted) };
    }

    return {
      type: "direct",
      extracted,
      bundleName,
      url: buildDirectLaunchURL(extracted, bundleName)
    };
  }

  async function redirectToLiveContainer(rawValue, launchMap) {
    const target = resolveLaunchTarget(rawValue, launchMap);
    if (!target) {
      return false;
    }

    window.location.href = target.url;
    return true;
  }

  function extractFromElement(element) {
    if (!(element instanceof Element)) {
      return null;
    }

    for (const attribute of ATTRIBUTE_CANDIDATES) {
      const value = element.getAttribute(attribute);
      const extracted = extractExternalScheme(value);
      if (extracted) {
        return extracted;
      }
    }

    return null;
  }

  function extractFromElementTree(element) {
    let current = element;
    let depth = 0;

    while (current && depth < MAX_ANCESTOR_DEPTH) {
      const directMatch = extractFromElement(current);
      if (directMatch) {
        return directMatch;
      }

      current = current.parentElement;
      depth += 1;
    }

    return null;
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
              const resolved = new URL(candidate, window.location.href).href;
              const protocol = new URL(resolved).protocol.toLowerCase();
              if (!blockedProtocols.has(protocol)) {
                return resolved;
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
                return value;
              }
              return iframeSrcDescriptor.set.call(this, value);
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

  async function loadLaunchMap() {
    if (!runtimeAPI?.runtime?.sendMessage) {
      return {};
    }

    try {
      const response = await runtimeAPI.runtime.sendMessage({ command: "getLaunchMap" });
      return response?.launchMap || {};
    } catch (_) {
      return {};
    }
  }

  async function init() {
    const launchMapPromise = loadLaunchMap();
    installPageLevelHooks();

    window.addEventListener(PAGE_LAUNCH_EVENT, (event) => {
      const rawValue = event?.detail?.rawValue;
      if (!rawValue) {
        return;
      }
      void launchMapPromise.then((launchMap) => redirectToLiveContainer(rawValue, launchMap));
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

        const extracted = extractFromElementTree(target);
        if (!extracted) {
          return;
        }

        event.preventDefault();
        event.stopPropagation();
        void launchMapPromise.then((launchMap) => redirectToLiveContainer(extracted, launchMap));
      },
      true
    );
  }

  void init();
})();
