/*
 * AI Reply — өнім симуляторының өзегі.
 *
 * Құрастыру қадамы жоқ: әкімші панелі сияқты, браузерде тікелей жұмыс істейтін
 * Vue 3. Бұл файлда күй, аударма, API клиенті және бәріне ортақ ұсақ
 * компоненттер ғана. Экрандар бөлек файлдарда.
 *
 * ҚАУІПСІЗДІК ЕСКЕРТПЕСІ: бұл жерде де, басқа симулятор файлында да ешқандай
 * құпия жоқ — OpenAI кілті тек сервер жағында, ал сессия HttpOnly cookie-де.
 * Инспектор тек ақ тізімдегі өрістерді көрсетеді (тақырыптар мен токендер
 * ешқашан жазылмайды).
 */
(function () {
  "use strict";

  var Vue = window.Vue;
  var boot = JSON.parse(document.getElementById("boot").textContent);

  var SIM = window.SIM = {
    Vue: Vue,
    boot: boot,
    components: {}
  };

  /* ------------------------------------------------------------- routes */
  var ROUTES = [
    { name: "overview", path: "/simulator", key: "sim.nav.overview", group: "product" },
    { name: "ios", path: "/simulator/ios", key: "sim.nav.ios", group: "product" },
    { name: "android", path: "/simulator/android", key: "sim.nav.android", group: "product" },
    { name: "keyboard", path: "/simulator/keyboard", key: "sim.nav.keyboard", group: "product" },
    { name: "personalization", path: "/simulator/personalization", key: "sim.nav.personalization", group: "product" },
    { name: "workflow", path: "/simulator/workflow", key: "sim.nav.workflow", group: "explain" },
    { name: "architecture", path: "/simulator/architecture", key: "sim.nav.architecture", group: "explain" },
    { name: "screens", path: "/simulator/screens", key: "sim.nav.screens", group: "explain" },
    { name: "admin", path: "/simulator/admin", key: "sim.nav.admin", group: "business" },
    { name: "pricing", path: "/simulator/pricing", key: "sim.nav.pricing", group: "business" }
  ];
  SIM.routes = ROUTES;

  function parseRoute(path) {
    var clean = String(path || "").replace(/\/+$/, "") || "/simulator";
    for (var i = 0; i < ROUTES.length; i++) {
      if (ROUTES[i].path === clean) return { name: ROUTES[i].name };
    }
    return { name: "overview" };
  }

  /* -------------------------------------------------------------- state */
  var storedTheme = null;
  try { storedTheme = localStorage.getItem("aireply.simulator.theme"); } catch (e) { storedTheme = null; }

  var state = Vue.reactive({
    locale: boot.locale,
    locales: boot.locales || ["kk", "ru", "en"],
    admin: boot.admin,
    csrf: boot.csrf,
    env: boot.env,
    accountLabel: (boot.account && boot.account.label) || "Product demo account",

    route: parseRoute(location.pathname),
    sidebarOpen: false,
    theme: storedTheme === "dark" ? "dark" : "light",
    presenting: false,
    inspectorOpen: false,

    account: null,
    plans: [],
    health: null,
    ready: false,
    bootError: "",

    inspector: [],
    toasts: [],

    tour: { active: false, step: 0 }
  });
  SIM.state = state;

  applyTheme();
  function applyTheme() {
    document.documentElement.setAttribute("data-theme", state.theme);
  }
  SIM.toggleTheme = function () {
    state.theme = state.theme === "dark" ? "light" : "dark";
    try { localStorage.setItem("aireply.simulator.theme", state.theme); } catch (e) { /* жеке режимде жоқ */ }
    applyTheme();
  };

  /* ------------------------------------------------------------- i18n */
  function t(key) {
    var bucket = boot.i18n[state.locale] || boot.i18n.en || {};
    var fallback = boot.i18n.en || {};
    return bucket[key] || fallback[key] || key;
  }
  function tf(key, params) {
    var out = t(key);
    Object.keys(params || {}).forEach(function (name) {
      out = out.split("{" + name + "}").join(String(params[name]));
    });
    return out;
  }
  SIM.t = t;
  SIM.tf = tf;

  SIM.setLocale = function (locale) {
    if (locale === state.locale) return;
    state.locale = locale;
    var url = new URL(location.href);
    url.searchParams.set("lang", locale);
    history.replaceState({}, "", url.pathname + url.search);
    SIM.api("/account", { method: "GET", silent: true }).catch(function () { /* аударма локалды */ });
    fetch("/api/v1/admin/locale", {
      method: "POST", credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": state.csrf },
      body: JSON.stringify({ locale: locale })
    }).catch(function () { /* тіл бәрібір ауысты */ });
  };

  /* ------------------------------------------------------------ router */
  SIM.go = function (path) {
    if (location.pathname !== path) history.pushState({}, "", path);
    state.route = parseRoute(path);
    state.sidebarOpen = false;
    window.scrollTo({ top: 0, behavior: state.presenting ? "auto" : "smooth" });
  };
  window.addEventListener("popstate", function () { state.route = parseRoute(location.pathname); });

  /* ------------------------------------------------------------ toasts */
  SIM.toast = function (kind, message) {
    var item = { id: Date.now() + Math.random(), kind: kind, message: message };
    state.toasts.push(item);
    setTimeout(function () {
      state.toasts = state.toasts.filter(function (x) { return x.id !== item.id; });
    }, 3600);
  };

  /* --------------------------------------------------------- inspector */
  var inspectorSeq = 0;

  // Тек ақ тізімдегі өрістер. Тақырыптар, токендер, cookie — ешқашан.
  var SAFE_REQUEST_FIELDS = [
    "language", "template_id", "platform", "preferred_tone", "plan_id",
    "business_offering", "daily_message_limit", "monthly_message_limit", "period_days", "price"
  ];

  function sanitizeRequest(body) {
    if (!body || typeof body !== "object") return undefined;
    var out = {};
    SAFE_REQUEST_FIELDS.forEach(function (field) {
      if (body[field] !== undefined && body[field] !== "") out[field] = body[field];
    });
    if (typeof body.source_text === "string") out.source_chars = body.source_text.length;
    if (typeof body.instruction === "string") {
      out.instruction_chars = body.instruction.length;
      // Нұсқау — қолданушының дәл осы демонстрацияда өзі жазғаны.
      out.instruction = body.instruction.length > 90 ? body.instruction.slice(0, 90) + "…" : body.instruction;
    }
    if (body.override) out.override = true;
    return Object.keys(out).length ? out : undefined;
  }

  function record(entry) {
    entry.id = ++inspectorSeq;
    state.inspector.unshift(entry);
    if (state.inspector.length > 12) state.inspector.pop();
  }
  SIM.clearInspector = function () { state.inspector = []; };

  /* ---------------------------------------------------------------- api */
  var BASE = "/api/v1/simulator";

  SIM.api = function (path, options) {
    options = options || {};
    var method = options.method || "GET";
    var started = performance.now();
    var init = {
      method: method,
      headers: { "Accept": "application/json" },
      credentials: "same-origin"
    };
    if (options.body !== undefined) {
      init.headers["Content-Type"] = "application/json";
      init.headers["X-CSRF-Token"] = state.csrf;
      init.body = JSON.stringify(options.body);
    }

    return fetch(BASE + path, init).then(function (response) {
      return response.json().catch(function () { return null; }).then(function (payload) {
        var ms = Math.round(performance.now() - started);
        if (!options.silent) {
          record({
            method: method,
            path: BASE + path,
            status: response.status,
            ok: response.ok,
            ms: ms,
            request: sanitizeRequest(options.body),
            trace: payload && payload.trace ? payload.trace : undefined,
            code: response.ok ? "" : (payload && payload.error ? payload.error.code : "ERROR")
          });
        }
        if (response.status === 401) {
          location.href = "/simulator/login";
          throw apiError("UNAUTHORIZED", t("sim.error.session"), null);
        }
        if (!response.ok) {
          var code = payload && payload.error ? payload.error.code : "ERROR";
          throw apiError(code, messageFor(code), payload && payload.error ? payload.error.details : null);
        }
        return payload;
      });
    }, function () {
      if (!options.silent) {
        record({ method: method, path: BASE + path, status: 0, ok: false,
          ms: Math.round(performance.now() - started), code: "NETWORK" });
      }
      throw apiError("NETWORK", t("sim.error.offline"), null);
    });
  };

  function apiError(code, message, details) {
    var err = new Error(message || code);
    err.code = code;
    err.details = details;
    return err;
  }
  SIM.apiError = apiError;

  // Қате коды → адам оқитын мәтін. Шикі stack trace ешқашан көрсетілмейді.
  function messageFor(code) {
    var map = {
      DAILY_LIMIT_REACHED: "sim.error.daily_limit",
      MONTHLY_LIMIT_REACHED: "sim.error.monthly_limit",
      RATE_LIMITED: "sim.error.rate",
      AI_TIMEOUT: "sim.error.timeout",
      AI_PROVIDER_UNAVAILABLE: "sim.error.provider",
      AI_EMPTY_RESPONSE: "sim.error.empty",
      INVALID_REQUEST: "sim.error.invalid",
      UNAUTHORIZED: "sim.error.session",
      CSRF_MISMATCH: "sim.error.session",
      SUBSCRIPTION_EXPIRED: "sim.error.subscription",
      TRANSCRIPTION_NOT_IMPLEMENTED: "sim.voice.server_missing",
      NETWORK: "sim.error.offline"
    };
    return t(map[code] || "sim.error.generic");
  }
  SIM.messageFor = messageFor;

  /* ------------------------------------------------------------- loader */
  SIM.loadBootstrap = function () {
    return SIM.api("/bootstrap", { silent: true }).then(function (payload) {
      state.account = payload.account;
      state.plans = payload.plans || [];
      state.health = payload.health;
      state.csrf = payload.csrf || state.csrf;
      state.ready = true;
      state.bootError = "";
      return payload;
    }, function (err) {
      state.bootError = err.message;
      state.ready = true;
      throw err;
    });
  };
  SIM.refreshAccount = function () {
    return SIM.api("/account", { silent: true }).then(function (account) {
      state.account = account;
      return account;
    });
  };

  /* ------------------------------------------------------------ helpers */
  SIM.nf = function (value) {
    if (value === null || value === undefined) return "—";
    try { return new Intl.NumberFormat(state.locale === "kk" ? "kk-KZ" : state.locale).format(value); }
    catch (e) { return String(value); }
  };
  SIM.money = function (minor, currency) {
    var major = Math.round(Number(minor || 0) / 100);
    return SIM.nf(major) + " " + (currency === "KZT" ? "₸" : (currency || ""));
  };
  SIM.planName = function (plan) {
    if (!plan) return "—";
    return (plan.name && (plan.name[state.locale] || plan.name.en)) || plan.code || "—";
  };
  SIM.clock = function () {
    var d = new Date();
    return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
  };
  SIM.register = function (name, definition) { SIM.components[name] = definition; };

  /* ------------------------------------------------ device scale mixin */
  // Құрылғы макеті кез келген экранға сыюы керек: ені де, биіктігі де.
  SIM.deviceScale = {
    data: function () { return { scale: 1, holderHeight: 0 }; },
    mounted: function () {
      this.recalc();
      this._onResize = this.recalc.bind(this);
      window.addEventListener("resize", this._onResize);
    },
    unmounted: function () { window.removeEventListener("resize", this._onResize); },
    methods: {
      recalc: function () {
        var holder = this.$refs.holder;
        if (!holder) return;
        var w = holder.clientWidth || this.deviceWidth;
        // Тақырып, бет тақырыбы және сахна жиегі — бәрі орын алады, сондықтан
        // құрылғы соларды шегергенде қалған биіктікке сыюы керек.
        var chrome = window.innerWidth <= 720 ? 300 : (SIM.state.presenting ? 170 : 230);
        var available = Math.max(window.innerHeight - chrome, 380);
        var scale = Math.min(w / this.deviceWidth, available / this.deviceHeight, 1);
        this.scale = Math.max(Math.round(scale * 1000) / 1000, 0.38);
        this.holderHeight = Math.round(this.deviceHeight * this.scale);
      }
    }
  };

  /* --------------------------------------------------- shared components */
  SIM.register("sim-meter", {
    props: { used: Number, limit: Number },
    computed: {
      pct: function () {
        if (!this.limit) return 0;
        return Math.min(100, Math.round((this.used / this.limit) * 100));
      },
      full: function () { return this.limit > 0 && this.used >= this.limit; }
    },
    template:
      '<div class="meter" :class="{ \'is-full\': full }" role="progressbar" :aria-valuenow="used"' +
      ' aria-valuemin="0" :aria-valuemax="limit"><i :style="{ width: pct + \'%\' }"></i></div>'
  });

  SIM.register("sim-stat", {
    props: { label: String, value: [String, Number], foot: String },
    template:
      '<div class="stat"><div class="label">{{ label }}</div>' +
      '<div class="value">{{ value }}</div>' +
      '<div class="foot" v-if="foot">{{ foot }}</div></div>'
  });

  SIM.register("sim-bars", {
    props: { points: { type: Array, default: function () { return []; } } },
    computed: {
      max: function () {
        return this.points.reduce(function (m, p) { return Math.max(m, p.value); }, 0) || 1;
      }
    },
    methods: { nf: SIM.nf },
    template:
      '<div class="bars"><div class="b" v-for="p in points" :key="p.label">' +
      '<span class="muted">{{ p.label }}</span>' +
      '<span class="track"><i :style="{ width: Math.round((p.value / max) * 100) + \'%\' }"></i></span>' +
      '<span class="num" style="text-align:right">{{ nf(p.value) }}</span></div></div>'
  });

  SIM.register("sim-spark", {
    props: { points: { type: Array, default: function () { return []; } } },
    computed: {
      geo: function () {
        var w = 300, h = 72, pad = 4;
        var values = this.points.map(function (p) { return p.value; });
        var max = Math.max.apply(null, values.concat([1]));
        var step = values.length > 1 ? (w - pad * 2) / (values.length - 1) : 0;
        var coords = values.map(function (v, i) {
          return [pad + i * step, h - pad - (v / max) * (h - pad * 2)];
        });
        var line = coords.map(function (c, i) {
          return (i ? "L" : "M") + c[0].toFixed(1) + " " + c[1].toFixed(1);
        }).join(" ");
        var area = coords.length ? line + " L" + coords[coords.length - 1][0].toFixed(1) +
          " " + h + " L" + coords[0][0].toFixed(1) + " " + h + " Z" : "";
        return { line: line, area: area };
      }
    },
    template:
      '<svg class="spark" viewBox="0 0 300 72" preserveAspectRatio="none" aria-hidden="true">' +
      '<path class="ar" :d="geo.area"/><path class="ln" :d="geo.line"/></svg>'
  });

  SIM.register("sim-inspector", {
    computed: {
      state: function () { return state; },
      entries: function () { return state.inspector; }
    },
    methods: {
      clear: function () { SIM.clearInspector(); },
      body: function (entry) {
        var out = { status: entry.status || "network error", duration_ms: entry.ms };
        if (entry.code) out.error_code = entry.code;
        if (entry.request) out.request = entry.request;
        if (entry.trace) out.response_trace = entry.trace;
        return JSON.stringify(out, null, 2);
      }
    },
    template:
      '<div class="inspector">' +
      '<h4><span>{{ t("sim.inspector.title") }}</span>' +
      '<button class="btn btn-sm btn-ghost" style="margin-left:auto;color:#7b87ad" @click="clear">{{ t("sim.inspector.clear") }}</button></h4>' +
      '<p v-if="!entries.length" class="inspector-note">{{ t("sim.inspector.empty") }}</p>' +
      '<div v-for="entry in entries" :key="entry.id" style="margin-bottom:10px">' +
      '<pre><span :class="entry.ok ? \'ok\' : \'str\'">{{ entry.method }} {{ entry.path }}</span>\n{{ body(entry) }}</pre>' +
      '</div>' +
      '<p class="inspector-note">{{ t("sim.inspector.note") }}</p>' +
      '</div>'
  });
})();
