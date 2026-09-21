/*
 * Телефондағы толық сценарий: тіркелуден бастап жауапты жіберуге дейін.
 *
 * Бір компонент екі платформаға да қызмет етеді, бірақ қадамдар тізімі мен
 * баптау нұсқаулығы әр жүйеде өзінше — себебі шын өмірде де солай.
 *
 * Қай қадам НАҚТЫ бэкендке барады:
 *   preferences → POST /api/v1/simulator/account/profile  (нақты профиль)
 *   keyboard    → POST /api/v1/simulator/generate         (нақты квота + OpenAI)
 * Қалған қадамдар — интерфейс жүрісі; жанындағы панельде қайсысы нақты екені
 * ашық жазылып тұрады.
 */
(function () {
  "use strict";

  var SIM = window.SIM;
  var t = SIM.t;
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var TONES = ["professional", "friendly", "short", "formal", "natural"];
  var AUDIENCES = ["retail", "business", "leads", "support", "mixed"];
  var LANGS = ["kk", "ru", "en", "auto"];

  function steps(platform) {
    var list = ["welcome", "register", "verify", "setup", "preferences", "messenger", "keyboard"];
    if (platform === "android") list.push("voice");
    list.push("insert");
    return list;
  }

  SIM.register("sim-phone", {
    props: {
      platform: { type: String, default: "ios" },
      startAt: { type: String, default: "" }
    },
    emits: ["step"],
    data: function () {
      return {
        step: 0,
        phone: "+7 707 000 00 00",
        code: "",
        saving: false,
        prefs: { tone: "professional", audience: "retail", language: "auto", business: "" },
        prefsSaved: false,
        conversation: [],
        draft: "",
        copiedId: "",
        sent: false,
        micDialog: false,
        micGranted: false,
        kbd: {
          open: false, copied: "", instruction: "", stage: "idle", draft: "", draftInitial: "",
          phase: 0, error: "", template: "client", language: "ru", instructionMax: 400,
          voice: { state: "idle", error: "" }
        }
      };
    },
    computed: {
      state: function () { return SIM.state; },
      steps: function () { return steps(this.platform); },
      current: function () { return this.steps[this.step]; },
      isLast: function () { return this.step === this.steps.length - 1; },
      usage: function () {
        return (SIM.state.account && SIM.state.account.usage) || { used_today: 0, daily_limit: 0, remaining_today: 0 };
      },
      tones: function () { return TONES; },
      audiences: function () { return AUDIENCES; },
      languages: function () { return LANGS; },
      incoming: function () {
        return this.conversation.filter(function (m) { return m.side === "in"; })[0];
      }
    },
    created: function () {
      this.seed();
      this.kbd.language = SIM.state.locale === "kk" ? "kk" : (SIM.state.locale === "en" ? "en" : "ru");
      var limits = SIM.state.health && SIM.state.health.limits;
      if (limits && limits.instruction_chars) this.kbd.instructionMax = limits.instruction_chars;
      this.hydrateFromAccount();
      if (this.startAt) {
        var at = this.steps.indexOf(this.startAt);
        if (at >= 0) { this.step = at; this.kbd.open = true; }
      }
    },
    mounted: function () { this.announce(); },
    watch: {
      "state.locale": function () { this.seed(); }
    },
    methods: {
      /* ------------------------------------------------------- деректер */
      seed: function () {
        this.conversation = [{
          id: "m1", side: "in", copyable: true,
          text: t("sim.demo.incoming"),
          time: SIM.clock()
        }];
        this.kbd.copied = "";
        this.copiedId = "";
        this.draft = "";
        this.sent = false;
      },
      hydrateFromAccount: function () {
        var account = SIM.state.account;
        if (!account || !account.profile) return;
        if (account.profile.preferred_tone) this.prefs.tone = account.profile.preferred_tone;
        if (account.profile.business_summary) this.prefs.business = account.profile.business_summary;
        if (account.profile.role) this.prefs.audience = account.profile.role;
      },

      /* ------------------------------------------------------ навигация */
      announce: function () {
        this.$emit("step", {
          name: this.current, index: this.step,
          total: this.steps.length, steps: this.steps.slice()
        });
      },
      go: function (index) {
        if (index < 0 || index >= this.steps.length) return;
        this.step = index;
        this.announce();
        if (this.current === "keyboard" || this.current === "voice") this.kbd.open = true;
      },
      next: function () { this.go(this.step + 1); },
      back: function () { this.go(this.step - 1); },
      restart: function () {
        this.step = this.startAt ? Math.max(this.steps.indexOf(this.startAt), 0) : 0;
        this.kbd.stage = "idle";
        this.kbd.open = false;
        this.kbd.instruction = "";
        this.kbd.draft = "";
        this.kbd.error = "";
        this.kbd.voice = { state: "idle", error: "" };
        this.micGranted = false;
        this.seed();
        this.announce();
      },

      /* -------------------------------------------------------- профиль */
      savePreferences: function () {
        var self = this;
        this.saving = true;
        var locale = this.prefs.language === "auto" ? SIM.state.locale : this.prefs.language;
        SIM.api("/account/profile", {
          method: "POST",
          body: {
            preferred_tone: this.prefs.tone,
            role: this.prefs.audience,
            business_summary: this.prefs.business,
            business_offering: t("sim.prefs.audience_" + this.prefs.audience),
            description: t("sim.prefs.description_prefix") + " " + this.prefs.business,
            locale: locale,
            onboarding_completed: true
          }
        }).then(function (account) {
          SIM.state.account = account;
          self.prefsSaved = true;
          self.saving = false;
          SIM.toast("ok", t("sim.prefs.saved"));
          self.next();
        }, function (err) {
          self.saving = false;
          SIM.toast("error", err.message);
        });
      },

      /* ------------------------------------------------------ мессенджер */
      copyMessage: function (message) {
        this.copiedId = message.id;
        this.kbd.copied = message.text;
        this.kbd.open = true;
        SIM.toast("ok", t("sim.messenger.copied_toast"));
        if (this.current === "messenger") this.next();
      },
      focusField: function () { this.kbd.open = true; },

      /* -------------------------------------------------------- генерация */
      generate: function () {
        var self = this;
        if (!this.kbd.copied) { this.kbd.error = t("sim.kbd.nothing_copied"); return; }
        this.kbd.error = "";
        this.kbd.stage = "generating";
        this.kbd.phase = 0;

        // Фазалар жалған кідіріспен емес, нақты оқиғалармен жылжиды.
        this.$nextTick(function () { self.kbd.phase = 1; });
        var slow = setTimeout(function () {
          if (self.kbd.stage === "generating") self.kbd.phase = 2;
        }, 400);

        SIM.api("/generate", {
          method: "POST",
          body: {
            source_text: this.kbd.copied,
            instruction: this.kbd.instruction,
            language: this.kbd.language,
            template_id: this.kbd.template,
            platform: this.platform
          }
        }).then(function (payload) {
          clearTimeout(slow);
          self.kbd.phase = 3;
          self.kbd.draftInitial = payload.reply;
          self.kbd.draft = payload.reply;
          self.kbd.stage = "result";
          if (payload.usage && SIM.state.account) SIM.state.account.usage = payload.usage;
        }, function (err) {
          clearTimeout(slow);
          self.kbd.stage = "ready";
          self.kbd.phase = 0;
          self.kbd.error = err.message;
          if (err.code === "DAILY_LIMIT_REACHED" && err.details && SIM.state.account) {
            SIM.state.account.usage.used_today = err.details.used_today;
            SIM.state.account.usage.daily_limit = err.details.daily_limit;
            SIM.state.account.usage.remaining_today = 0;
          }
        });
      },
      regenerate: function () {
        this.kbd.stage = "ready";
        this.kbd.draft = "";
        this.generate();
      },
      clearDraft: function () {
        this.kbd.stage = "idle";
        this.kbd.draft = "";
        this.kbd.draftInitial = "";
        this.kbd.instruction = "";
        this.kbd.error = "";
      },

      /* ----------------------------------------------------------- қою */
      insert: function () {
        var self = this;
        var text = this.kbd.draft || this.kbd.draftInitial;
        if (!text) return;
        this.kbd.open = false;
        if (this.current !== "insert") this.go(this.steps.indexOf("insert"));
        if (reduceMotion) { this.draft = text; return; }
        this.draft = "";
        var i = 0;
        var tick = function () {
          i += Math.max(1, Math.round(text.length / 40));
          self.draft = text.slice(0, i);
          if (i < text.length) setTimeout(tick, 16);
          else self.draft = text;
        };
        setTimeout(tick, 120);
      },
      send: function () {
        if (!this.draft) return;
        this.conversation.push({ id: "m" + (this.conversation.length + 1), side: "out", text: this.draft, time: SIM.clock() });
        this.draft = "";
        this.sent = true;
        this.kbd.stage = "idle";
        this.kbd.draft = "";
        this.kbd.instruction = "";
        SIM.toast("ok", t("sim.messenger.sent"));
      },

      /* --------------------------------------------------------- дауыс */
      micPressed: function () {
        if (this.kbd.voice.state === "listening") { this.stopVoice(); return; }
        if (!this.micGranted) { this.micDialog = true; return; }
        this.startVoice();
      },
      grantMic: function (mode) {
        this.micDialog = false;
        if (mode === "deny") {
          this.kbd.voice = { state: "denied", error: t("sim.voice.denied_body") };
          return;
        }
        this.micGranted = true;
        this.startVoice();
      },
      startVoice: function () {
        var self = this;
        if (!SIM.voice.supported()) {
          this.kbd.voice = { state: "idle", error: t("sim.voice.browser_missing") };
          return;
        }
        this.kbd.voice = { state: "starting", error: "" };
        this._voice = SIM.voice.source();
        try {
          this._voice.start(SIM.voice.tag(this.kbd.language), {
            onPartial: function (text) {
              self.kbd.voice.state = "listening";
              if (text) self.kbd.instruction = text;
            },
            onFinal: function (text) {
              self.kbd.voice.state = "processing";
              self.kbd.instruction = text;
            },
            onError: function (reason) {
              self.kbd.voice = {
                state: "idle",
                error: reason === "denied" ? t("sim.voice.denied_body")
                  : reason === "no_speech" ? t("sim.voice.no_speech")
                    : reason === "server_missing" ? t("sim.voice.server_missing")
                      : t("sim.voice.failed")
              };
            },
            onEnd: function () {
              if (self.kbd.voice.state === "processing" || self.kbd.voice.state === "listening") {
                self.kbd.voice.state = self.kbd.instruction ? "done" : "idle";
              }
            }
          });
          setTimeout(function () {
            if (self.kbd.voice.state === "starting") self.kbd.voice.state = "listening";
          }, 200);
        } catch (e) {
          this.kbd.voice = { state: "idle", error: t("sim.voice.failed") };
        }
      },
      stopVoice: function () { if (this._voice) this._voice.stop(); },

      label: function (key) { return t(key); }
    },
    template: `
<div style="display:flex;flex-direction:column;height:100%">

  <!-- 1. Қош келдіңіз -->
  <template v-if="current === 'welcome'">
    <div class="app-scroll" style="display:flex;flex-direction:column;justify-content:center;text-align:center;padding:0 26px">
      <div class="mark" style="width:62px;height:62px;border-radius:19px;font-size:22px;margin:0 auto 20px">AI</div>
      <h2 class="app-title" style="font-size:27px">{{ t('sim.step.welcome_title') }}</h2>
      <p class="app-lede">{{ t('sim.step.welcome_body') }}</p>
      <button class="app-btn" @click="next">{{ t('sim.action.continue') }}</button>
    </div>
  </template>

  <!-- 2. Тіркелу -->
  <template v-else-if="current === 'register'">
    <div class="app-nav"><button class="back" @click="back" :aria-label="t('sim.action.back')">‹</button>{{ t('sim.step.register_title') }}</div>
    <div class="app-scroll">
      <p class="app-lede">{{ t('sim.step.register_body') }}</p>
      <div class="app-label">{{ t('sim.step.phone') }}</div>
      <input class="app-input" v-model="phone" inputmode="tel" :aria-label="t('sim.step.phone')">
      <button class="app-btn" style="margin-top:18px" @click="next">{{ t('sim.action.continue') }}</button>
      <p class="muted" style="font-size:12.5px;margin-top:14px">{{ t('sim.step.register_note') }}</p>
    </div>
  </template>

  <!-- 3. Растау -->
  <template v-else-if="current === 'verify'">
    <div class="app-nav"><button class="back" @click="back" :aria-label="t('sim.action.back')">‹</button>{{ t('sim.step.verify_title') }}</div>
    <div class="app-scroll">
      <p class="app-lede">{{ t('sim.step.verify_body') }} {{ phone }}</p>
      <div class="otp-row">
        <span class="otp-box" v-for="n in 4" :key="n" :class="{ 'is-on': code.length >= n }">{{ code[n-1] || '' }}</span>
      </div>
      <input class="app-input" v-model="code" maxlength="4" inputmode="numeric"
             :aria-label="t('sim.step.verify_title')" style="text-align:center;letter-spacing:.4em">
      <button class="app-btn" style="margin-top:18px" :disabled="code.length < 4" @click="next">{{ t('sim.action.verify') }}</button>
    </div>
  </template>

  <!-- 4. Пернетақтаны қосу -->
  <template v-else-if="current === 'setup'">
    <div class="app-nav"><button class="back" @click="back" :aria-label="t('sim.action.back')">‹</button>{{ t('sim.step.setup_title') }}</div>
    <div class="app-scroll">
      <p class="app-lede">{{ t('sim.step.setup_body') }}</p>
      <div :class="platform === 'ios' ? 'ios-card' : 'md-card'">
        <div class="setup-steps">
          <div class="setup-step" v-for="(line, i) in (platform === 'ios'
              ? [t('sim.setup.ios1'), t('sim.setup.ios2'), t('sim.setup.ios3')]
              : [t('sim.setup.and1'), t('sim.setup.and2'), t('sim.setup.and3')])" :key="i">
            <span class="n">{{ i + 1 }}</span><span><b>{{ line }}</b></span>
          </div>
        </div>
      </div>
      <div :class="platform === 'ios' ? 'ios-card' : 'md-card'">
        <b style="font-size:14.5px">{{ platform === 'ios' ? t('sim.setup.full_access') : t('sim.setup.and_notice_title') }}</b>
        <p style="margin:6px 0 0;color:#5b6577;font-size:13.5px">{{ platform === 'ios' ? t('sim.setup.full_access_why') : t('sim.setup.and_notice_body') }}</p>
      </div>
      <button class="app-btn" style="margin-top:6px" @click="next">{{ t('sim.action.enabled') }}</button>
    </div>
  </template>

  <!-- 5. Баптаулар -->
  <template v-else-if="current === 'preferences'">
    <div class="app-nav"><button class="back" @click="back" :aria-label="t('sim.action.back')">‹</button>{{ t('sim.step.prefs_title') }}</div>
    <div class="app-scroll">
      <div class="app-label">{{ t('sim.prefs.tone') }}</div>
      <button v-for="tone in tones" :key="tone" class="opt" :class="{ 'is-on': prefs.tone === tone }" @click="prefs.tone = tone">
        <span class="radio"></span><span><b>{{ t('sim.tone.' + tone) }}</b><small>{{ t('sim.tone.' + tone + '_hint') }}</small></span>
      </button>

      <div class="app-label">{{ t('sim.prefs.audience') }}</div>
      <button v-for="a in audiences" :key="a" class="opt" :class="{ 'is-on': prefs.audience === a }" @click="prefs.audience = a">
        <span class="radio"></span><span><b>{{ t('sim.prefs.audience_' + a) }}</b></span>
      </button>

      <div class="app-label">{{ t('sim.prefs.language') }}</div>
      <button v-for="l in languages" :key="l" class="opt" :class="{ 'is-on': prefs.language === l }" @click="prefs.language = l">
        <span class="radio"></span><span><b>{{ l === 'auto' ? t('sim.prefs.lang_auto') : t('sim.lang.' + l) }}</b></span>
      </button>

      <div class="app-label">{{ t('sim.prefs.business') }}</div>
      <textarea class="app-input" rows="4" v-model="prefs.business" maxlength="400"
                :placeholder="t('sim.prefs.business_hint')" :aria-label="t('sim.prefs.business')"></textarea>

      <button class="app-btn" style="margin:18px 0 6px" :disabled="saving" @click="savePreferences">
        {{ saving ? t('sim.action.saving') : t('sim.action.save') }}
      </button>
      <p class="muted" style="font-size:12.5px">{{ t('sim.prefs.note') }}</p>
    </div>
  </template>

  <!-- 6–8. Мессенджер + пернетақта -->
  <template v-else>
    <sim-messenger :platform="platform" :contact="{ name: t('sim.demo.contact'), subtitle: t('sim.demo.contact_sub'), initials: 'A' }"
                   :messages="conversation" :draft="draft" :copied-id="copiedId"
                   @copy="copyMessage" @focus="focusField" @send="send"/>
    <sim-keyboard :platform="platform" :model="kbd" :voice-enabled="platform === 'android'"
                  @generate="generate" @regenerate="regenerate" @insert="insert" @clear="clearDraft"
                  @mic="micPressed" @open="kbd.open = !kbd.open"/>
  </template>

  <sim-mic-dialog :open="micDialog" @allow="grantMic('always')" @once="grantMic('once')" @deny="grantMic('deny')"/>
</div>`
  });
})();
