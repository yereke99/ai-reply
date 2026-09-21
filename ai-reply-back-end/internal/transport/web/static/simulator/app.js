/*
 * Қабық: бүйір мәзір, жоғарғы жол, маршруттар, көрсетілім режимі және тур.
 */
(function () {
  "use strict";

  var SIM = window.SIM;
  var Vue = SIM.Vue;
  var state = SIM.state;
  var t = SIM.t;

  var ICONS = {
    overview: '<path d="M4 13h7V4H4zM13 20h7v-9h-7zM4 20h7v-4H4zM13 8h7V4h-7z"/>',
    ios: '<rect x="7" y="2.5" width="10" height="19" rx="2.6"/><path d="M11 18.6h2"/>',
    android: '<rect x="6" y="3" width="12" height="18" rx="2.2"/><path d="M10 19.4h4"/>',
    keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2.4"/><path d="M6 10h.01M9.5 10h.01M13 10h.01M16.5 10h.01M7.5 14h9"/>',
    personalization: '<circle cx="12" cy="8" r="3.4"/><path d="M5 20a7 7 0 0 1 14 0"/>',
    workflow: '<path d="M5 6h6M5 12h14M5 18h9"/><circle cx="18" cy="6" r="2"/><circle cx="16" cy="18" r="2"/>',
    architecture: '<rect x="8.5" y="2.5" width="7" height="5" rx="1.4"/><rect x="2.5" y="16.5" width="7" height="5" rx="1.4"/><rect x="14.5" y="16.5" width="7" height="5" rx="1.4"/><path d="M12 7.5v4.5M6 16.5v-2.2h12v2.2"/>',
    screens: '<rect x="3" y="4" width="7" height="16" rx="1.6"/><rect x="14" y="4" width="7" height="8" rx="1.6"/><rect x="14" y="15" width="7" height="5" rx="1.6"/>',
    admin: '<path d="M3 20h18M6 20V9M11 20V4M16 20v-7M21 20v-4"/>',
    pricing: '<path d="M3 12V5a2 2 0 0 1 2-2h7l9 9-9 9z"/><circle cx="7.5" cy="7.5" r="1.4"/>'
  };

  var TOUR = ["configure", "incoming", "open", "instruction", "generate", "insert", "limits", "pricing", "usage"];
  var TOUR_ROUTE = {
    configure: "/simulator/ios", incoming: "/simulator/ios", open: "/simulator/keyboard",
    instruction: "/simulator/keyboard", generate: "/simulator/keyboard", insert: "/simulator/keyboard",
    limits: "/simulator/pricing", pricing: "/simulator/pricing", usage: "/simulator/admin"
  };

  var App = {
    computed: {
      state: function () { return state; },
      groups: function () {
        var out = [];
        SIM.routes.forEach(function (route) {
          var group = out.filter(function (g) { return g.name === route.group; })[0];
          if (!group) { group = { name: route.group, items: [] }; out.push(group); }
          group.items.push(route);
        });
        return out;
      },
      title: function () {
        var route = SIM.routes.filter(function (r) { return r.name === state.route.name; })[0];
        return route ? t(route.key) : "AI Reply";
      },
      routeIndex: function () {
        for (var i = 0; i < SIM.routes.length; i++) {
          if (SIM.routes[i].name === state.route.name) return i;
        }
        return 0;
      },
      tourStep: function () { return TOUR[state.tour.step] || TOUR[0]; }
    },
    mounted: function () {
      var self = this;
      SIM.loadBootstrap().catch(function (err) { SIM.toast("error", err.message); });
      this._keys = function (event) {
        if (!state.presenting) return;
        if (event.key === "ArrowRight") self.slide(1);
        if (event.key === "ArrowLeft") self.slide(-1);
        if (event.key === "Escape") state.presenting = false;
      };
      window.addEventListener("keydown", this._keys);
    },
    unmounted: function () { window.removeEventListener("keydown", this._keys); },
    watch: {
      "state.presenting": function (on) {
        document.body.classList.toggle("is-presenting", !!on);
        window.dispatchEvent(new Event("resize"));
      }
    },
    methods: {
      icon: function (name) { return ICONS[name] || ICONS.overview; },
      go: function (path) { SIM.go(path); },
      isActive: function (name) { return state.route.name === name; },
      groupLabel: function (name) { return t("sim.group." + name); },
      setLocale: function (locale) { SIM.setLocale(locale); },
      toggleTheme: function () { SIM.toggleTheme(); },
      slide: function (delta) {
        var next = Math.min(Math.max(this.routeIndex + delta, 0), SIM.routes.length - 1);
        SIM.go(SIM.routes[next].path);
      },
      startTour: function () { state.tour = { active: true, step: 0 }; SIM.go(TOUR_ROUTE[TOUR[0]]); },
      tourNext: function () {
        if (state.tour.step >= TOUR.length - 1) { state.tour.active = false; return; }
        state.tour.step += 1;
        SIM.go(TOUR_ROUTE[TOUR[state.tour.step]]);
      },
      tourPrev: function () {
        if (state.tour.step === 0) return;
        state.tour.step -= 1;
        SIM.go(TOUR_ROUTE[TOUR[state.tour.step]]);
      },
      endTour: function () { state.tour.active = false; }
    },
    template: `
<div class="shell">
  <div class="scrim" v-if="state.sidebarOpen" @click="state.sidebarOpen = false"></div>

  <aside class="sidebar" :class="{ 'is-open': state.sidebarOpen }" :aria-label="t('sim.a11y.nav')">
    <div class="brand"><span class="mark">AI</span>
      <span class="brand-text"><b>AI Reply</b><span>{{ t('sim.title') }}</span></span></div>

    <template v-for="group in groups" :key="group.name">
      <div class="nav-group">{{ groupLabel(group.name) }}</div>
      <button v-for="route in group.items" :key="route.name" class="item"
              :class="{ 'is-active': isActive(route.name) }" @click="go(route.path)">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
             stroke-linecap="round" stroke-linejoin="round" v-html="icon(route.name)"></svg>
        {{ t(route.key) }}
      </button>
    </template>

    <div class="spacer"></div>
    <button class="item" @click="startTour">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
        <circle cx="12" cy="12" r="9"/><path d="M9.6 9.4a2.5 2.5 0 1 1 3.3 2.4c-.6.2-.9.7-.9 1.3v.4M12 16.6h.01"/></svg>
      {{ t('sim.tour.start') }}
    </button>
    <div class="side-status" v-if="state.health">
      <div class="row"><span>{{ t('sim.health.backend') }}</span>
        <b><span class="dot" :class="state.health.database ? 'is-ok' : 'is-bad'"></span></b></div>
      <div class="row"><span>{{ t('sim.health.model') }}</span><b class="mono">{{ state.health.model }}</b></div>
      <div class="row"><span>{{ t('sim.health.env') }}</span><b class="mono">{{ state.health.env }}</b></div>
    </div>
  </aside>

  <div class="main">
    <header class="topbar">
      <button class="burger" @click="state.sidebarOpen = !state.sidebarOpen" :aria-label="t('sim.a11y.nav')">☰</button>
      <h1>{{ title }}</h1>
      <div class="right">
        <div class="lang" role="group" :aria-label="t('sim.a11y.language')">
          <button v-for="l in state.locales" :key="l" :class="{ 'is-active': state.locale === l }"
                  @click="setLocale(l)">{{ l }}</button>
        </div>
        <button class="btn btn-icon" @click="toggleTheme" :aria-label="t('sim.a11y.theme')">
          <svg v-if="state.theme === 'light'" viewBox="0 0 24 24" width="16" height="16" fill="none"
               stroke="currentColor" stroke-width="1.8" stroke-linecap="round">
            <path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/></svg>
          <svg v-else viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
               stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/>
            <path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/></svg>
        </button>
        <button class="btn btn-sm present-toggle" @click="state.presenting = !state.presenting">
          {{ state.presenting ? t('sim.present.exit') : t('sim.present.start') }}</button>
        <span class="who muted" style="font-size:13px">{{ state.admin.email }}</span>
        <form method="post" action="/simulator/logout">
          <input type="hidden" name="csrf" :value="state.csrf">
          <button class="btn btn-sm" type="submit">{{ t('sim.action.logout') }}</button>
        </form>
      </div>
    </header>

    <main class="content" id="sim-content">
      <div v-if="!state.ready" class="card">{{ t('sim.common.loading') }}</div>
      <div v-else-if="state.bootError" class="card">
        <h3>{{ t('sim.error.boot_title') }}</h3>
        <p>{{ state.bootError }}</p>
      </div>
      <template v-else>
        <view-overview v-if="state.route.name === 'overview'"/>
        <sim-device-view v-else-if="state.route.name === 'ios'" platform="ios" key="ios"/>
        <sim-device-view v-else-if="state.route.name === 'android'" platform="android" key="android"/>
        <view-keyboard v-else-if="state.route.name === 'keyboard'"/>
        <view-personalization v-else-if="state.route.name === 'personalization'"/>
        <view-workflow v-else-if="state.route.name === 'workflow'"/>
        <view-architecture v-else-if="state.route.name === 'architecture'"/>
        <view-screens v-else-if="state.route.name === 'screens'"/>
        <view-admin v-else-if="state.route.name === 'admin'"/>
        <view-pricing v-else-if="state.route.name === 'pricing'"/>
      </template>
    </main>
  </div>

  <div class="present-bar" v-if="state.presenting">
    <button class="btn btn-sm" @click="slide(-1)" :disabled="routeIndex === 0">{{ t('sim.action.back') }}</button>
    <span class="count">{{ t('sim.present.step') }} {{ routeIndex + 1 }} / {{ state.route && 10 }}</span>
    <button class="btn btn-sm btn-brand" @click="slide(1)" :disabled="routeIndex === 9">{{ t('sim.action.next') }}</button>
    <button class="btn btn-sm btn-ghost" @click="state.presenting = false">{{ t('sim.present.exit') }}</button>
  </div>

  <div class="tour-card" v-if="state.tour.active" role="dialog" :aria-label="t('sim.tour.start')">
    <div class="n">{{ String(state.tour.step + 1).padStart(2, '0') }} / {{ 9 }}</div>
    <h4>{{ t('sim.tour.' + tourStep + '_title') }}</h4>
    <p>{{ t('sim.tour.' + tourStep + '_body') }}</p>
    <div style="display:flex;gap:7px">
      <button class="btn btn-sm" @click="tourPrev" :disabled="state.tour.step === 0">{{ t('sim.action.back') }}</button>
      <button class="btn btn-sm btn-brand" @click="tourNext">
        {{ state.tour.step === 8 ? t('sim.tour.finish') : t('sim.action.next') }}</button>
      <button class="btn btn-sm btn-ghost" style="margin-left:auto" @click="endTour">{{ t('sim.tour.skip') }}</button>
    </div>
  </div>

  <div class="toasts" aria-live="polite">
    <div v-for="item in state.toasts" :key="item.id" :class="'toast toast-' + item.kind">{{ item.message }}</div>
  </div>
</div>`
  };

  var app = Vue.createApp(App);
  Object.keys(SIM.components).forEach(function (name) {
    app.component(name, SIM.components[name]);
  });
  app.config.globalProperties.t = SIM.t;
  app.config.globalProperties.tf = SIM.tf;
  app.mount("#app");
  document.getElementById("app").classList.remove("app-loading");
})();
