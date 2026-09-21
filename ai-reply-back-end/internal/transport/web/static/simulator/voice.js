/*
 * Дауыспен нұсқау беру (Android).
 *
 * Нақты қосымшада тану ҚҰРЫЛҒЫНЫҢ ӨЗІНДЕ жүреді (Android SpeechRecognizer),
 * ал бэкендте транскрипция эндпоинті жоқ. Симулятор дәл сол архитектураны
 * қайталайды: алдымен браузердің өз танушысы, ол жоқ болса — сервер (әзірге
 * 501 қайтарады), ол да жоқ болса — қолданушыға шынын айтамыз.
 *
 * Күйлер нақты VoiceState-пен бірдей:
 * idle → permission → starting → listening → processing → done | failed
 */
(function () {
  "use strict";

  var SIM = window.SIM;
  var t = SIM.t;

  var LANG_TAGS = { kk: "kk-KZ", ru: "ru-RU", en: "en-US", uz: "uz-UZ" };

  function BrowserSource() {
    var Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    this.available = !!Recognition;
    this.Recognition = Recognition;
    this.instance = null;
  }
  BrowserSource.prototype.start = function (languageTag, handlers) {
    var recognition = new this.Recognition();
    this.instance = recognition;
    recognition.lang = languageTag;
    recognition.interimResults = true;
    recognition.continuous = false;
    recognition.maxAlternatives = 1;

    recognition.onresult = function (event) {
      var partial = "", finalText = "";
      for (var i = event.resultIndex; i < event.results.length; i++) {
        var chunk = event.results[i][0].transcript;
        if (event.results[i].isFinal) finalText += chunk; else partial += chunk;
      }
      if (finalText) handlers.onFinal(finalText.trim());
      else handlers.onPartial(partial.trim());
    };
    recognition.onerror = function (event) {
      var reason = event && event.error === "no-speech" ? "no_speech"
        : event && event.error === "not-allowed" ? "denied"
          : event && event.error === "network" ? "network" : "generic";
      handlers.onError(reason);
    };
    recognition.onend = function () { handlers.onEnd(); };
    recognition.start();
  };
  BrowserSource.prototype.stop = function () { if (this.instance) this.instance.stop(); };
  BrowserSource.prototype.cancel = function () { if (this.instance) this.instance.abort(); };

  // Сервер жағындағы тану — әлі жоқ. Интерфейс дайын тұр: бэкендте эндпоинт
  // пайда болған сәтте осы жерге жалғанады, UI өзгермейді.
  function ServerSource() { this.available = false; }
  ServerSource.prototype.start = function (_lang, handlers) {
    SIM.api("/transcribe", { method: "POST", body: {} }).then(function () {
      handlers.onError("generic");
    }, function () { handlers.onError("server_missing"); });
  };
  ServerSource.prototype.stop = function () {};
  ServerSource.prototype.cancel = function () {};

  SIM.voice = {
    source: function () {
      var browser = new BrowserSource();
      return browser.available ? browser : new ServerSource();
    },
    tag: function (locale) { return LANG_TAGS[locale] || "ru-RU"; },
    supported: function () { return !!(window.SpeechRecognition || window.webkitSpeechRecognition); }
  };

  /* ----------------------------------------------- Android рұқсат терезесі */
  SIM.register("sim-mic-dialog", {
    props: { open: Boolean },
    emits: ["allow", "once", "deny"],
    template:
      '<div class="md-scrim" v-if="open" role="dialog" aria-modal="true">' +
      '<div class="md-dialog">' +
      '<div class="mic-round"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor"' +
      ' stroke-width="2" stroke-linecap="round"><rect x="9" y="2.5" width="6" height="11" rx="3"/>' +
      '<path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg></div>' +
      '<h4>{{ t("sim.voice.permission_title") }}</h4>' +
      '<p>{{ t("sim.voice.permission_body") }}</p>' +
      '<button class="md-choice" @click="$emit(\'allow\')">{{ t("sim.voice.allow_while_using") }}</button>' +
      '<button class="md-choice" @click="$emit(\'once\')">{{ t("sim.voice.allow_once") }}</button>' +
      '<button class="md-choice is-deny" @click="$emit(\'deny\')">{{ t("sim.voice.deny") }}</button>' +
      '</div></div>'
  });

  SIM.register("sim-wave", {
    props: { active: Boolean },
    template:
      '<span class="wave" :class="{ \'is-idle\': !active }" aria-hidden="true">' +
      '<i v-for="n in 9" :key="n"></i></span>'
  });
})();
