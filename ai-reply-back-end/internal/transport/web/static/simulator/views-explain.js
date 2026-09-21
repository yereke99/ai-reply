/*
 * Түсіндіру экрандары: толық сценарий, архитектура және экрандар галереясы.
 */
(function () {
  "use strict";

  var SIM = window.SIM;
  var t = SIM.t;

  /* ------------------------------------------------- шағын экран үлгілері */
  SIM.register("sim-mini", {
    props: { variant: { type: String, default: "messenger" }, platform: { type: String, default: "ios" } },
    template: `
<div class="stage-scaler" style="transform:scale(.42);transform-origin:top center">
  <sim-device :platform="platform" :label="variant">

    <div v-if="variant === 'welcome'" class="app-scroll" style="display:flex;flex-direction:column;justify-content:center;text-align:center">
      <div class="mark" style="width:60px;height:60px;border-radius:18px;font-size:21px;margin:0 auto 18px">AI</div>
      <h2 class="app-title">{{ t('sim.step.welcome_title') }}</h2>
      <p class="app-lede">{{ t('sim.step.welcome_body') }}</p>
      <button class="app-btn">{{ t('sim.action.continue') }}</button>
    </div>

    <div v-else-if="variant === 'register'" class="app-scroll">
      <div class="app-title">{{ t('sim.step.register_title') }}</div>
      <p class="app-lede">{{ t('sim.step.register_body') }}</p>
      <div class="app-label">{{ t('sim.step.phone') }}</div>
      <div class="app-input">+7 707 000 00 00</div>
      <div class="otp-row"><span class="otp-box is-on">•</span><span class="otp-box is-on">•</span>
        <span class="otp-box">​</span><span class="otp-box">​</span></div>
      <button class="app-btn">{{ t('sim.action.verify') }}</button>
    </div>

    <div v-else-if="variant === 'setup'" class="app-scroll">
      <div class="app-title">{{ t('sim.step.setup_title') }}</div>
      <div class="ios-card"><div class="setup-steps">
        <div class="setup-step" v-for="(line, i) in [t('sim.setup.ios1'), t('sim.setup.ios2'), t('sim.setup.ios3')]" :key="i">
          <span class="n">{{ i + 1 }}</span><b>{{ line }}</b></div>
      </div></div>
      <button class="app-btn">{{ t('sim.action.enabled') }}</button>
    </div>

    <div v-else-if="variant === 'prefs'" class="app-scroll">
      <div class="app-title">{{ t('sim.step.prefs_title') }}</div>
      <div class="app-label">{{ t('sim.prefs.tone') }}</div>
      <div class="opt is-on"><span class="radio"></span><span><b>{{ t('sim.tone.professional') }}</b></span></div>
      <div class="opt"><span class="radio"></span><span><b>{{ t('sim.tone.friendly') }}</b></span></div>
      <div class="app-label">{{ t('sim.prefs.business') }}</div>
      <div class="app-input" style="min-height:74px">{{ t('sim.personalization.a_business') }}</div>
    </div>

    <div v-else-if="variant === 'messenger' || variant === 'copy' || variant === 'sent'" class="msgr">
      <div class="msgr-top"><span class="msgr-avatar">A</span>
        <span><b>{{ t('sim.demo.contact') }}</b><small>{{ t('sim.demo.contact_sub') }}</small></span></div>
      <div class="msgr-feed">
        <div class="msg msg-in" :class="{ 'is-selected': variant === 'copy' }">{{ t('sim.demo.incoming') }}
          <button class="msg-copy" v-if="variant === 'copy'">{{ t('sim.messenger.copied') }}</button></div>
        <div class="msg msg-out" v-if="variant === 'sent'">{{ t('sim.demo.reply') }}</div>
      </div>
      <div class="msgr-compose">
        <div class="msgr-field" :class="{ 'is-empty': variant !== 'sent' }">
          {{ variant === 'sent' ? '' : t('sim.messenger.placeholder') }}</div>
        <button class="msgr-send"><svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
          stroke-width="2.2" stroke-linecap="round"><path d="M4 12h15M13 6l6 6-6 6"/></svg></button>
      </div>
    </div>

    <div v-else class="msgr">
      <div class="msgr-feed" style="flex:none;max-height:210px">
        <div class="msg msg-in">{{ t('sim.demo.incoming') }}</div>
        <div class="msg msg-out" v-if="variant === 'insert'">{{ t('sim.demo.reply') }}</div>
      </div>
      <div style="flex:1"></div>
      <div class="kbd">
        <div class="kbd-bar"><span class="kbd-logo"><span class="mark">AI</span>AI Reply</span>
          <span class="kbd-chip is-on">{{ t('sim.template.client') }}</span>
          <span class="kbd-lang">RU</span></div>
        <div class="kbd-panel">
          <div class="kbd-quote"><b>{{ t('sim.kbd.copied') }}</b>{{ t('sim.demo.incoming') }}</div>
          <template v-if="variant === 'draft' || variant === 'edit' || variant === 'insert'">
            <div class="kbd-draft">{{ t('sim.demo.reply') }}</div>
            <div class="kbd-actions">
              <span class="app-btn app-btn-quiet" style="flex:1">{{ t('sim.kbd.regenerate') }}</span>
              <span class="app-btn" style="flex:1.4">{{ t('sim.kbd.insert') }}</span></div>
          </template>
          <template v-else>
            <div class="kbd-instruction">{{ t('sim.personalization.instruction') }}</div>
            <div class="kbd-actions"><span class="app-btn">{{ variant === 'generating'
              ? t('sim.kbd.generating') : t('sim.kbd.generate') }}</span></div>
            <div class="kbd-stage" v-if="variant === 'generating'" style="margin-top:9px">
              <span>{{ t('sim.kbd.phase_generating') }}</span>
              <span class="bar"><i style="width:66%"></i></span></div>
          </template>
        </div>
        <div class="keys">
          <div class="row" v-for="r in 3" :key="r"><span class="key" v-for="k in 10" :key="k"> </span></div>
        </div>
      </div>
    </div>

  </sim-device>
</div>`
  });

  /* ------------------------------------------------------ толық сценарий */
  var FLOW = [
    { id: "account", variant: "register", real: false },
    { id: "configure", variant: "prefs", real: true },
    { id: "keyboard_on", variant: "setup", real: false },
    { id: "incoming", variant: "messenger", real: false },
    { id: "copy", variant: "copy", real: false },
    { id: "open_kbd", variant: "instruction", real: false },
    { id: "instruction", variant: "instruction", real: false },
    { id: "request", variant: "generating", real: true },
    { id: "context", variant: "generating", real: true },
    { id: "openai", variant: "generating", real: true },
    { id: "return", variant: "draft", real: true },
    { id: "edit", variant: "edit", real: false },
    { id: "insert", variant: "insert", real: false },
    { id: "send", variant: "sent", real: false }
  ];

  SIM.register("view-workflow", {
    data: function () { return { active: 0 }; },
    computed: {
      flow: function () { return FLOW; },
      step: function () { return FLOW[this.active]; }
    },
    methods: {
      pick: function (index) { this.active = index; },
      prev: function () { this.active = Math.max(0, this.active - 1); },
      next: function () { this.active = Math.min(FLOW.length - 1, this.active + 1); }
    },
    template: `
<div class="content-wide">
  <div class="section-head">
    <h2>{{ t('sim.workflow.title') }}</h2>
    <p>{{ t('sim.workflow.lede') }}</p>
  </div>

  <div class="flow-grid">
    <div class="flow-list" role="tablist" :aria-label="t('sim.workflow.title')">
      <button v-for="(item, i) in flow" :key="item.id" class="flow-node" :class="{ 'is-on': i === active }"
              role="tab" :aria-selected="i === active" @click="pick(i)">
        <span class="idx">{{ String(i + 1).padStart(2, '0') }}</span>
        <span><b>{{ t('sim.wf.' + item.id + '_title') }}</b><small>{{ t('sim.wf.' + item.id + '_sub') }}</small></span>
      </button>
    </div>

    <div class="grid g2" style="align-items:start">
      <div class="stage" style="min-height:0;padding:22px 10px">
        <div style="height:372px;display:flex;justify-content:center">
          <sim-mini :variant="step.variant" :key="step.id"/>
        </div>
      </div>

      <div class="panel-stack">
        <div class="card">
          <div class="step-head"><span class="num">{{ active + 1 }}</span><b>{{ t('sim.wf.' + step.id + '_title') }}</b></div>
          <div class="step-body">
            <p style="margin:0 0 12px">{{ t('sim.wf.' + step.id + '_body') }}</p>
            <div class="kv-stack">
              <div><span>{{ t('sim.workflow.system') }}</span><b>{{ t('sim.wf.' + step.id + '_system') }}</b></div>
              <div><span>{{ t('sim.workflow.component') }}</span><b class="mono">{{ t('sim.wf.' + step.id + '_component') }}</b></div>
            </div>
            <div style="margin-top:12px">
              <span class="pill" :class="step.real ? 'pill-real' : ''">{{ step.real ? t('sim.badge.real_api') : t('sim.badge.ui_only') }}</span>
            </div>
          </div>
          <div class="step-nav">
            <button class="btn btn-sm" @click="prev" :disabled="active === 0">{{ t('sim.action.back') }}</button>
            <button class="btn btn-sm btn-brand" @click="next" :disabled="active === flow.length - 1">{{ t('sim.action.next') }}</button>
            <span class="count">{{ active + 1 }} / {{ flow.length }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>`
  });

  /* --------------------------------------------------------- архитектура */
  var NODES = ["ios", "android", "transport", "auth", "limits", "context", "gateway", "openai", "storage", "admin"];

  SIM.register("view-architecture", {
    data: function () { return { active: "gateway" }; },
    computed: {
      nodes: function () { return NODES; },
      health: function () { return SIM.state.health || {}; }
    },
    methods: { pick: function (id) { this.active = id; } },
    template: `
<div class="content-wide">
  <div class="section-head">
    <h2>{{ t('sim.arch.title') }}</h2>
    <p>{{ t('sim.arch.lede') }}</p>
  </div>

  <div class="grid g2" style="align-items:start">
    <div class="card card-pad-lg">
      <div class="arch">
        <div class="arch-pair">
          <button class="arch-node" :class="{ 'is-on': active === 'ios' }" @click="pick('ios')">
            <span class="top"><b>{{ t('sim.arch.ios') }}</b></span><small>{{ t('sim.arch.ios_sub') }}</small></button>
          <button class="arch-node" :class="{ 'is-on': active === 'android' }" @click="pick('android')">
            <span class="top"><b>{{ t('sim.arch.android') }}</b></span><small>{{ t('sim.arch.android_sub') }}</small></button>
        </div>
        <span class="arch-link"></span>
        <button class="arch-node" :class="{ 'is-on': active === 'transport' }" @click="pick('transport')">
          <span class="top"><b>{{ t('sim.arch.transport') }}</b></span><small>{{ t('sim.arch.transport_sub') }}</small></button>
        <span class="arch-link"></span>
        <button class="arch-node" :class="{ 'is-on': active === 'auth' }" @click="pick('auth')">
          <span class="top"><b>{{ t('sim.arch.auth') }}</b></span><small>{{ t('sim.arch.auth_sub') }}</small></button>
        <span class="arch-link"></span>
        <button class="arch-node" :class="{ 'is-on': active === 'limits' }" @click="pick('limits')">
          <span class="top"><b>{{ t('sim.arch.limits') }}</b></span><small>{{ t('sim.arch.limits_sub') }}</small></button>
        <span class="arch-link"></span>
        <button class="arch-node" :class="{ 'is-on': active === 'context' }" @click="pick('context')">
          <span class="top"><b>{{ t('sim.arch.context') }}</b></span><small>{{ t('sim.arch.context_sub') }}</small></button>
        <span class="arch-link"></span>
        <button class="arch-node" :class="{ 'is-on': active === 'gateway' }" @click="pick('gateway')">
          <span class="top"><b>{{ t('sim.arch.gateway') }}</b>
            <span class="pill pill-brand" style="margin-left:auto">{{ health.model }}</span></span>
          <small>{{ t('sim.arch.gateway_sub') }}</small></button>
        <span class="arch-link"></span>
        <button class="arch-node" :class="{ 'is-on': active === 'openai' }" @click="pick('openai')">
          <span class="top"><b>{{ t('sim.arch.openai') }}</b></span><small>{{ t('sim.arch.openai_sub') }}</small></button>
        <span class="arch-link"></span>
        <div class="arch-pair">
          <button class="arch-node" :class="{ 'is-on': active === 'storage' }" @click="pick('storage')">
            <span class="top"><b>{{ t('sim.arch.storage') }}</b></span><small>{{ t('sim.arch.storage_sub') }}</small></button>
          <button class="arch-node" :class="{ 'is-on': active === 'admin' }" @click="pick('admin')">
            <span class="top"><b>{{ t('sim.arch.admin') }}</b></span><small>{{ t('sim.arch.admin_sub') }}</small></button>
        </div>
      </div>
    </div>

    <div class="panel-stack">
      <div class="card">
        <div class="step-head"><b>{{ t('sim.arch.' + active) }}</b></div>
        <div class="step-body">
          <p style="margin:0 0 12px">{{ t('sim.arch.' + active + '_detail') }}</p>
          <div class="kv-stack">
            <div><span>{{ t('sim.arch.where') }}</span><b class="mono">{{ t('sim.arch.' + active + '_where') }}</b></div>
            <div><span>{{ t('sim.arch.never') }}</span><b>{{ t('sim.arch.' + active + '_never') }}</b></div>
          </div>
        </div>
      </div>
      <div class="card">
        <div class="step-head"><b>{{ t('sim.arch.privacy_title') }}</b></div>
        <div class="step-body"><p style="margin:0">{{ t('sim.arch.privacy_body') }}</p></div>
      </div>
    </div>
  </div>
</div>`
  });

  /* ------------------------------------------------------------ экрандар */
  var SHOTS = [
    { id: "account", variant: "register" },
    { id: "keyboard_on", variant: "setup" },
    { id: "configure", variant: "prefs" },
    { id: "incoming", variant: "copy" },
    { id: "instruction", variant: "instruction" },
    { id: "generating", variant: "generating" },
    { id: "draft", variant: "draft" },
    { id: "send", variant: "sent" }
  ];

  SIM.register("view-screens", {
    data: function () { return { platform: "ios" }; },
    computed: { shots: function () { return SHOTS; } },
    template: `
<div class="content-wide">
  <div class="section-head" style="display:flex;align-items:flex-end;gap:16px;flex-wrap:wrap">
    <div style="flex:1;min-width:260px">
      <h2>{{ t('sim.screens.title') }}</h2>
      <p>{{ t('sim.screens.lede') }}</p>
    </div>
    <div style="display:flex;gap:6px">
      <button class="btn btn-sm" :class="platform === 'ios' ? 'btn-brand' : ''" @click="platform = 'ios'">iOS</button>
      <button class="btn btn-sm" :class="platform === 'android' ? 'btn-brand' : ''" @click="platform = 'android'">Android</button>
    </div>
  </div>

  <div class="shots">
    <div class="shot" v-for="(shot, i) in shots" :key="shot.id">
      <div class="art"><div style="height:372px;display:flex;justify-content:center;overflow:hidden">
        <sim-mini :variant="shot.variant" :platform="platform" :key="platform + shot.id"/></div></div>
      <div class="cap"><b>{{ String(i + 1).padStart(2, '0') }} · {{ t('sim.wf.' + shot.id + '_title') }}</b>
        <small>{{ t('sim.wf.' + shot.id + '_sub') }}</small></div>
    </div>
  </div>
</div>`
  });
})();
