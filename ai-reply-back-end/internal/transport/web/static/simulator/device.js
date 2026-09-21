/*
 * Құрылғы макеттері.
 *
 * Мақсат — Apple не Google интерфейсін көшіру емес: мақсат — AI Reply-дің
 * заманауи телефонда қалай көрінетінін адал көрсету. Сондықтан жақтау, күй
 * жолағы және навигация өз қолымызбен салынған, ал экранның ішіндегінің бәрі —
 * біздің өз интерфейсіміз.
 */
(function () {
  "use strict";

  var SIM = window.SIM;
  var t = SIM.t;

  var SIZES = {
    ios: { w: 390, h: 844 },
    android: { w: 400, h: 866 }
  };

  /* -------------------------------------------------------- status bar */
  SIM.register("sim-statusbar", {
    props: { platform: { type: String, default: "ios" } },
    data: function () { return { now: SIM.clock() }; },
    mounted: function () {
      var self = this;
      this._timer = setInterval(function () { self.now = SIM.clock(); }, 20000);
    },
    unmounted: function () { clearInterval(this._timer); },
    template:
      '<div class="statusbar" aria-hidden="true">' +
      '<span>{{ now }}</span>' +
      '<span class="sb-right">' +
      '<svg viewBox="0 0 20 12" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1"/>' +
      '<rect x="4.5" y="6" width="3" height="6" rx="1"/><rect x="9" y="3" width="3" height="9" rx="1"/>' +
      '<rect x="13.5" y="0" width="3" height="12" rx="1" opacity=".35"/></svg>' +
      '<svg viewBox="0 0 16 12" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round">' +
      '<path d="M1 4.2a10 10 0 0 1 14 0"/><path d="M3.6 6.9a6.4 6.4 0 0 1 8.8 0"/><path d="M6.2 9.5a2.7 2.7 0 0 1 3.6 0"/></svg>' +
      '<svg viewBox="0 0 26 12" fill="none"><rect x="0.6" y="0.6" width="21" height="10.8" rx="3" stroke="currentColor" stroke-opacity=".45"/>' +
      '<rect x="2.2" y="2.2" width="16" height="7.6" rx="1.8" fill="currentColor"/>' +
      '<path d="M23.4 4.2v3.6a2 2 0 0 0 0-3.6z" fill="currentColor" fill-opacity=".45"/></svg>' +
      '</span></div>'
  });

  /* ----------------------------------------------------------- device */
  SIM.register("sim-device", {
    props: {
      platform: { type: String, default: "ios" },
      label: { type: String, default: "" }
    },
    computed: {
      size: function () { return SIZES[this.platform] || SIZES.ios; }
    },
    template:
      '<div class="device" :class="\'device-\' + platform" :style="{ width: size.w + \'px\', height: size.h + \'px\' }"' +
      ' role="group" :aria-label="label">' +
      '<div class="screen">' +
      '<div v-if="platform === \'ios\'" class="island"></div>' +
      '<div v-else class="punch"></div>' +
      '<sim-statusbar :platform="platform"/>' +
      '<div class="app-body"><slot/></div>' +
      '<div v-if="platform === \'ios\'" class="home-indicator"></div>' +
      '<div v-else class="nav-gesture"><i></i></div>' +
      '</div></div>'
  });

  /* ------------------------------------------------------------ stage */
  SIM.register("sim-stage", {
    mixins: [SIM.deviceScale],
    props: {
      platform: { type: String, default: "ios" },
      label: { type: String, default: "" },
      badge: { type: String, default: "" }
    },
    computed: {
      deviceWidth: function () { return (SIZES[this.platform] || SIZES.ios).w + 40; },
      deviceHeight: function () { return (SIZES[this.platform] || SIZES.ios).h + 20; },
      state: function () { return SIM.state; }
    },
    watch: {
      platform: function () { this.$nextTick(this.recalc); }
    },
    template:
      '<div class="stage">' +
      '<div class="stage-head">' +
      '<span class="pill">{{ platform === "ios" ? "iPhone" : "Android" }}</span>' +
      '<span class="pill" v-if="badge">{{ badge }}</span>' +
      '<span style="margin-left:auto"><slot name="tools"/></span>' +
      '</div>' +
      '<div ref="holder" style="width:100%;display:flex;justify-content:center"' +
      ' :style="{ height: holderHeight ? holderHeight + \'px\' : \'auto\' }">' +
      '<div class="stage-scaler" :style="{ transform: \'scale(\' + scale + \')\' }">' +
      '<sim-device :platform="platform" :label="label"><slot/></sim-device>' +
      '</div></div></div>'
  });

  /* ----------------------------------------------- iOS modal sheet */
  SIM.register("sim-sheet", {
    props: { open: Boolean },
    emits: ["close"],
    template:
      '<div class="ios-sheet" v-if="open" @click.self="$emit(\'close\')">' +
      '<div class="ios-sheet-body"><div class="ios-sheet-grab"></div><slot/></div></div>'
  });
})();
