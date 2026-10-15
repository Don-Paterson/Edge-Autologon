(() => {
  const host = location.hostname;

  // Set a field's value in a way that page scripts (React/Angular/ExtJS) notice.
  function fill(el, value) {
    el.focus();
    const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), "value").set;
    setter.call(el, value);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent("keyup", { bubbles: true }));
    el.blur();
  }

  const visible = el => el && el.offsetParent !== null;

  // ---------------------------------------------------------------------------
  // 1. Fill-only fields (AUTOFILL in config.js). Keeps watching the page,
  //    because wizards swap their pages in and out without reloading.
  // ---------------------------------------------------------------------------
  const rules = (typeof AUTOFILL === "undefined" ? [] : AUTOFILL)
    .filter(r => !r.hosts || r.hosts.includes(host));
  const done = new WeakSet();   // fill each field once, so you can still edit it

  const norm = t => (t || "").replace(/[:*\s]+$/, "").replace(/\s+/g, " ").trim().toLowerCase();

  function fieldsForLabel(text) {
    const want = norm(text);
    const out = [];
    for (const label of document.querySelectorAll("label")) {
      if (norm(label.textContent) !== want) continue;
      let el = label.htmlFor && document.getElementById(label.htmlFor);
      if (!el || el.tagName !== "INPUT") {
        // ExtJS: the input lives in the same form row as the label.
        const row = label.closest(".x-form-item, tr, div");
        el = row && row.querySelector("input:not([type='hidden']):not([type='checkbox']), textarea");
      }
      if (el) out.push(el);
    }
    return out;
  }

  function runAutofill() {
    for (const rule of rules) {
      const els = rule.selector ? [...document.querySelectorAll(rule.selector)] : fieldsForLabel(rule.label);
      for (const el of els) {
        if (done.has(el) || !visible(el) || el.disabled || el.readOnly) continue;
        done.add(el);
        if (!el.value) fill(el, rule.value);
      }
    }
  }

  if (rules.length) {
    let timer = null;
    runAutofill();
    new MutationObserver(() => {
      clearTimeout(timer);
      timer = setTimeout(runAutofill, 200);
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "class"] });
  }

  // ---------------------------------------------------------------------------
  // 2. Automatic login (SITES in config.js, type "form").
  // ---------------------------------------------------------------------------
  const site = findSite(location.href, "form");
  if (!site) return;

  // At most one attempt per tab every 30 seconds (prevents loops on wrong password).
  const KEY = "autologon-last-attempt";
  const last = Number(sessionStorage.getItem(KEY) || 0);
  if (Date.now() - last < 30000) return;

  // Find a visible button/link whose text is e.g. "Log In".
  function findButtonByText(text) {
    if (!text) return null;
    const want = text.trim().toLowerCase();
    const candidates = document.querySelectorAll(
      "button, input[type='button'], input[type='submit'], a, [role='button'], .x-btn, .x-btn-text");
    for (const el of candidates) {
      const label = (el.innerText || el.value || "").trim().toLowerCase();
      if (label === want && visible(el)) return el;
    }
    return null;
  }

  function pressEnter(el) {
    el.focus();
    for (const type of ["keydown", "keypress", "keyup"]) {
      el.dispatchEvent(new KeyboardEvent(type, {
        key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true }));
    }
  }

  function tryLogin() {
    const pass = document.querySelector(site.passSelector);
    if (!visible(pass)) return false;                          // not a visible login form
    const user = document.querySelector(site.userSelector);
    if (!user) return false;                                   // username box not drawn yet

    sessionStorage.setItem(KEY, String(Date.now()));
    fill(user, site.username);
    fill(pass, site.password);

    // Give the page a moment to enable its Log In button, then click it.
    setTimeout(() => {
      const btn = document.querySelector(site.submitSelector) || findButtonByText(site.submitText);
      if (btn) btn.click();
      else if (pass.form) pass.form.requestSubmit ? pass.form.requestSubmit() : pass.form.submit();
      else pressEnter(pass);
    }, 300);
    return true;
  }

  // Login forms are often drawn after page load, so watch for up to 10s.
  if (tryLogin()) return;
  const obs = new MutationObserver(() => { if (tryLogin()) obs.disconnect(); });
  obs.observe(document.documentElement, { childList: true, subtree: true });
  setTimeout(() => obs.disconnect(), 10000);
})();
