/*
 * Телефон ішіндегі жеңіл мессенджер.
 *
 * Бұл — жалпы мессенджер, нақты қолданбаның көшірмесі емес: AI Reply
 * мессенджерді алмастырмайды, сондықтан демонстрацияда да ол жай ғана
 * «қолданушы отырған қосымша» болып қалады.
 */
(function () {
  "use strict";

  var SIM = window.SIM;
  var t = SIM.t;

  SIM.register("sim-messenger", {
    props: {
      platform: { type: String, default: "ios" },
      contact: { type: Object, default: function () { return {}; } },
      messages: { type: Array, default: function () { return []; } },
      draft: { type: String, default: "" },
      copiedId: { type: String, default: "" },
      typing: { type: Boolean, default: false }
    },
    emits: ["copy", "send", "focus"],
    watch: {
      messages: {
        deep: true,
        handler: function () { this.$nextTick(this.scrollDown); }
      },
      draft: function () { this.$nextTick(this.scrollDown); }
    },
    mounted: function () { this.$nextTick(this.scrollDown); },
    methods: {
      scrollDown: function () {
        var feed = this.$refs.feed;
        if (feed) feed.scrollTop = feed.scrollHeight;
      }
    },
    template:
      '<div class="msgr">' +
      '<div class="msgr-top">' +
      '<span class="msgr-avatar">{{ contact.initials || "C" }}</span>' +
      '<span><b>{{ contact.name }}</b><small>{{ contact.subtitle }}</small></span>' +
      '</div>' +

      '<div class="msgr-feed" ref="feed">' +
      '<div v-for="m in messages" :key="m.id" class="msg"' +
      ' :class="[m.side === \'in\' ? \'msg-in\' : \'msg-out\', { \'is-selected\': m.id === copiedId }]">' +
      '{{ m.text }}<span class="msg-time">{{ m.time }}</span>' +
      '<button v-if="m.side === \'in\' && m.copyable" class="msg-copy" @click="$emit(\'copy\', m)">' +
      '{{ m.id === copiedId ? t("sim.messenger.copied") : t("sim.messenger.copy") }}</button>' +
      '</div>' +
      '<div v-if="typing" class="msg msg-in" style="opacity:.6">…</div>' +
      '</div>' +

      '<div class="msgr-compose">' +
      '<div class="msgr-field" :class="{ \'is-empty\': !draft }" @click="$emit(\'focus\')"' +
      ' role="textbox" :aria-label="t(\'sim.messenger.field\')" tabindex="0" @keydown.enter.prevent="$emit(\'focus\')">' +
      '{{ draft || t("sim.messenger.placeholder") }}</div>' +
      '<button class="msgr-send" :disabled="!draft" @click="$emit(\'send\')" :aria-label="t(\'sim.messenger.send\')">' +
      '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2.2"' +
      ' stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h15M13 6l6 6-6 6"/></svg>' +
      '</button>' +
      '</div>' +
      '</div>'
  });
})();
