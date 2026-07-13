import Foundation

enum RemoteAPIWebInterface {
    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>LiveContainer Remote API</title>
      <style>
        :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        body { margin: 0; background: #f2f2f7; color: #1c1c1e; }
        main { width: min(760px, calc(100% - 32px)); margin: 48px auto; }
        header { display: flex; align-items: center; justify-content: space-between; gap: 16px; margin-bottom: 24px; }
        h1, h2, p { margin-top: 0; }
        h1 { font-size: 28px; margin-bottom: 4px; }
        h2 { font-size: 20px; }
        .row > h2 { margin-bottom: 0; }
        .muted { color: #6e6e73; }
        .card { background: white; border-radius: 14px; padding: 20px; margin-bottom: 16px; box-shadow: 0 1px 3px #00000012; }
        .row { display: flex; align-items: center; gap: 12px; }
        .grow { flex: 1; min-width: 0; }
        input[type=password], input[type=url] { box-sizing: border-box; width: 100%; }
        input[type=password], input[type=url] { border: 1px solid #c7c7cc; border-radius: 9px; padding: 11px 12px; font: inherit; background: transparent; }
        button, .button { appearance: none; border: 0; border-radius: 9px; padding: 10px 14px; background: #007aff; color: white; font: inherit; font-weight: 600; cursor: pointer; text-decoration: none; display: inline-block; }
        button.secondary, .button.secondary { background: #e5e5ea; color: #1c1c1e; }
        button.danger { background: #ff3b30; }
        button:disabled { opacity: .5; cursor: default; }
        .app { min-width: 0; display: flex; align-items: center; gap: 14px; background: white; border-radius: 16px; padding: 16px; box-shadow: 0 1px 3px #00000012; }
        .apps-section { margin-bottom: 16px; }
        .apps-header { margin-bottom: 12px; padding: 0 4px; }
        #apps { display: grid; grid-template-columns: minmax(0, 1fr); gap: 12px; }
        .app-icon { flex: 0 0 58px; width: 58px; height: 58px; border-radius: 13px; overflow: hidden; display: grid; place-items: center; background: #d1d1d6; color: #6e6e73; font-size: 22px; font-weight: 700; }
        .app-icon > * { grid-area: 1 / 1; }
        .app-icon img { width: 100%; height: 100%; object-fit: cover; }
        .app-name { font-weight: 650; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .app-meta { font-size: 13px; margin-top: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .app-count { margin: 14px 0 0; text-align: center; }
        .actions { display: flex; gap: 8px; flex-wrap: wrap; justify-content: flex-end; }
        .actions input { display: none; }
        .header-actions { flex-wrap: nowrap; }
        .add-button { width: 38px; height: 38px; padding: 0; font-size: 25px; font-weight: 400; line-height: 1; }
        progress { width: 100%; height: 10px; }
        dialog { box-sizing: border-box; width: min(420px, calc(100% - 48px)); border: 0; border-radius: 14px; padding: 20px; background: white; color: inherit; box-shadow: 0 20px 60px #0006; }
        dialog::backdrop { background: #0008; }
        .dialog-actions { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 8px; margin-top: 20px; }
        .install-options { display: grid; gap: 10px; margin-top: 20px; }
        .install-options button { width: 100%; text-align: left; }
        #message { border-radius: 9px; padding: 10px 12px; margin-bottom: 16px; background: #e5e5ea; }
        #message.error { background: #ffebe9; color: #b42318; }
        [hidden] { display: none !important; }
        @media (prefers-color-scheme: dark) {
          body { background: #000; color: #f2f2f7; }
          .card { background: #1c1c1e; box-shadow: none; }
          .muted { color: #98989d; }
          .app { background: #1c1c1e; box-shadow: none; }
          button.secondary, .button.secondary, #message { background: #38383a; color: #f2f2f7; }
          input[type=password], input[type=url] { border-color: #48484a; }
          dialog { background: #1c1c1e; }
        }
        @media (max-width: 600px) { main { margin: 24px auto; } }
        @media (max-width: 360px) { .app { display: grid; grid-template-columns: 52px minmax(0, 1fr); } .app-icon { width: 52px; height: 52px; } .actions { grid-column: 1 / -1; } .actions button { width: 100%; } }
      </style>
    </head>
    <body>
      <main>
        <header>
          <div><h1>LiveContainer</h1><div class="muted">Remote app management</div></div>
          <div class="actions header-actions">
            <button id="add-app" class="secondary add-button" aria-label="Install app" hidden>+</button>
            <button id="logout" class="secondary" hidden>Log out</button>
          </div>
        </header>
        <div id="message" hidden></div>

        <section id="login" class="card">
          <h2>Connect</h2>
          <p class="muted">Enter the authentication token shown in LiveContainer Settings.</p>
          <form id="login-form" class="row">
            <input id="token" class="grow" type="password" autocomplete="current-password" placeholder="Authentication token" required autofocus>
            <button type="submit">Log in</button>
          </form>
        </section>

        <div id="dashboard" hidden>
          <section id="job" class="card" hidden>
            <div class="row"><strong id="job-status" class="grow">Queued</strong><span id="job-percent">0%</span></div>
            <progress id="job-progress" max="100" value="0"></progress>
          </section>
          <section class="apps-section">
            <div class="row apps-header"><h2 class="grow">Installed apps</h2><button id="refresh" class="secondary">Refresh</button></div>
            <div id="apps"><p class="muted">Loading…</p></div>
            <p id="app-count" class="app-count muted" hidden></p>
          </section>
        </div>
        <input id="install-file" type="file" accept=".ipa,.tipa" hidden>
        <dialog id="install-dialog">
          <h2>Install an app</h2>
          <div class="install-options">
            <button id="choose-ipa">Install IPA File</button>
            <button id="choose-url" class="secondary">Install from URL</button>
            <button id="cancel-install" class="secondary">Cancel</button>
          </div>
        </dialog>
        <dialog id="url-dialog">
          <h2>Install from URL</h2>
          <form id="url-form">
            <input id="install-url" type="url" inputmode="url" placeholder="https://example.com/app.ipa" required>
            <div class="dialog-actions">
              <button id="cancel-url" type="button" class="secondary">Cancel</button>
              <button type="submit">Install</button>
            </div>
          </form>
        </dialog>
        <dialog id="conflict-dialog">
          <h2>App already installed</h2>
          <p id="conflict-message" class="muted"></p>
          <form method="dialog" class="dialog-actions">
            <button class="secondary" value="cancel">Cancel</button>
            <button class="secondary" value="copy">Install Another Copy</button>
            <button value="replace">Update Existing</button>
          </form>
        </dialog>
      </main>
      <script>
        const login = document.querySelector('#login');
        const dashboard = document.querySelector('#dashboard');
        const logout = document.querySelector('#logout');
        const addApp = document.querySelector('#add-app');
        const message = document.querySelector('#message');
        let token = sessionStorage.getItem('livecontainer-token') || '';

        function showMessage(text, error = false) {
          message.textContent = text;
          message.className = error ? 'error' : '';
          message.hidden = !text;
        }

        async function api(path, options = {}) {
          options.headers = {...(options.headers || {}), Authorization: `Bearer ${token}`};
          const response = await fetch(`/api/v1${path}`, options);
          const body = await response.json().catch(() => ({}));
          if (!response.ok) throw new Error(body.error || `Request failed (${response.status})`);
          return body;
        }

        function setAuthenticated(value) {
          login.hidden = value;
          dashboard.hidden = !value;
          logout.hidden = !value;
          addApp.hidden = !value;
        }

        function escapeHTML(value) {
          return String(value).replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
        }

        async function authenticate(candidate) {
          token = candidate;
          await api('/status');
          sessionStorage.setItem('livecontainer-token', token);
          setAuthenticated(true);
          showMessage('');
          await loadApps();
        }

        async function loadApps() {
          const container = document.querySelector('#apps');
          document.querySelector('#app-count').hidden = true;
          container.innerHTML = '<p class="muted">Loading…</p>';
          try {
            const apps = await api('/apps');
            const count = document.querySelector('#app-count');
            count.textContent = `${apps.length} ${apps.length === 1 ? 'App' : 'Apps'} in total`;
            count.hidden = false;
            if (!apps.length) {
              container.innerHTML = '<p class="muted">No apps installed.</p>';
              return;
            }
            container.innerHTML = apps.map(app => `
              <div class="app">
                <div class="app-icon"><span>${escapeHTML(app.name.trim().charAt(0).toUpperCase() || '?')}</span><img data-icon="${escapeHTML(app.bundleID)}" alt=""></div>
                <div class="grow">
                  <div class="app-name">${escapeHTML(app.name)}</div>
                  <div class="app-meta muted" title="${escapeHTML(app.bundleID)}">${escapeHTML(app.version)} (${escapeHTML(app.build)}) · ${escapeHTML(app.bundleID)}${app.locked ? ' · Locked' : ''}</div>
                </div>
                <div class="actions">
                  <button class="danger" data-delete="${escapeHTML(app.bundleID)}">Uninstall</button>
                </div>
              </div>`).join('');
            await Promise.all([...container.querySelectorAll('[data-icon]')].map(loadIcon));
          } catch (error) {
            showMessage(error.message, true);
          }
        }

        async function loadIcon(image) {
          const response = await fetch(`/api/v1/apps/${encodeURIComponent(image.dataset.icon)}/icon`, {headers: {Authorization: `Bearer ${token}`}});
          if (!response.ok) return;
          image.src = URL.createObjectURL(await response.blob());
        }

        async function upload(file) {
          const form = new FormData();
          form.append('ipa', file);
          showMessage('Uploading…');
          const result = await api('/apps', {method: 'POST', body: form});
          showMessage('Installation started.');
          await watchJob(result.job);
        }

        async function installFromURL(url) {
          showMessage('Downloading…');
          const result = await api('/apps/url', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({url})
          });
          showMessage('Installation started.');
          await watchJob(result.job);
        }

        async function watchJob(id) {
          const panel = document.querySelector('#job');
          panel.hidden = false;
          while (true) {
            const job = await api(`/jobs/${encodeURIComponent(id)}`);
            document.querySelector('#job-status').textContent = job.status[0].toUpperCase() + job.status.slice(1);
            document.querySelector('#job-percent').textContent = `${job.progress}%`;
            document.querySelector('#job-progress').value = job.progress;
            if (job.status === 'conflict') {
              const action = await resolveConflict(job.conflict);
              await api(`/jobs/${encodeURIComponent(id)}/resolve`, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({action})
              });
              if (action === 'cancel') {
                showMessage('Installation cancelled.');
                panel.hidden = true;
                return;
              }
              continue;
            }
            if (job.status === 'complete') {
              showMessage('App installed successfully.');
              await loadApps();
              return;
            }
            if (job.status === 'failed') throw new Error(job.error || 'Installation failed.');
            await new Promise(resolve => setTimeout(resolve, 750));
          }
        }

        function resolveConflict(conflict) {
          const dialog = document.querySelector('#conflict-dialog');
          const names = conflict.apps.length ? ` (${conflict.apps.join(', ')})` : '';
          document.querySelector('#conflict-message').textContent = `${conflict.bundleID}${names} is already installed. Choose whether to update it or keep both copies.`;
          dialog.showModal();
          return new Promise(resolve => dialog.addEventListener('close', () => resolve(dialog.returnValue || 'cancel'), {once: true}));
        }

        document.querySelector('#login-form').addEventListener('submit', async event => {
          event.preventDefault();
          try { await authenticate(document.querySelector('#token').value.trim()); }
          catch (error) { showMessage(error.message, true); }
        });
        addApp.addEventListener('click', () => document.querySelector('#install-dialog').showModal());
        document.querySelector('#cancel-install').addEventListener('click', () => document.querySelector('#install-dialog').close());
        document.querySelector('#choose-ipa').addEventListener('click', () => {
          document.querySelector('#install-dialog').close();
          document.querySelector('#install-file').click();
        });
        document.querySelector('#choose-url').addEventListener('click', () => {
          document.querySelector('#install-dialog').close();
          document.querySelector('#url-dialog').showModal();
          document.querySelector('#install-url').focus();
        });
        document.querySelector('#install-file').addEventListener('change', async event => {
          const file = event.target.files[0];
          if (!file) return;
          try { await upload(file); event.target.value = ''; }
          catch (error) { showMessage(error.message, true); }
        });
        document.querySelector('#cancel-url').addEventListener('click', () => document.querySelector('#url-dialog').close());
        document.querySelector('#url-form').addEventListener('submit', async event => {
          event.preventDefault();
          const url = document.querySelector('#install-url').value.trim();
          document.querySelector('#url-dialog').close();
          try { await installFromURL(url); event.target.reset(); }
          catch (error) { showMessage(error.message, true); }
        });
        document.querySelector('#apps').addEventListener('click', async event => {
          const bundleID = event.target.dataset.delete;
          if (!bundleID || !confirm(`Uninstall ${bundleID}?`)) return;
          try { await api(`/apps/${encodeURIComponent(bundleID)}`, {method: 'DELETE'}); showMessage('App uninstalled.'); await loadApps(); }
          catch (error) { showMessage(error.message, true); }
        });
        document.querySelector('#refresh').addEventListener('click', loadApps);
        logout.addEventListener('click', () => { token = ''; sessionStorage.removeItem('livecontainer-token'); setAuthenticated(false); showMessage(''); });

        if (token) authenticate(token).catch(() => { sessionStorage.removeItem('livecontainer-token'); token = ''; setAuthenticated(false); });
      </script>
    </body>
    </html>
    """#
}
