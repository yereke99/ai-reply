/*
 * Лендингтің интерактив бөлігі (Vue 3). Негізгі мазмұн серверде рендерленеді —
 * бұл скрипт тек демо анимациясы мен санауыштарды қосады.
 */
(function () {
  "use strict";

  var Vue = window.Vue;
  var node = document.getElementById("landing-data");
  if (!Vue || !node) return;
  var data = JSON.parse(node.textContent);

  /* Пернетақта демосы: хабарлама → нұсқау → жауап, әріптеп теріледі. */
  var Demo = {
    data: function () {
      return { scenes: data.scenes, index: 0, incoming: "", instruction: "", reply: "", stage: 0, timer: null };
    },
    mounted: function () { this.play(); },
    unmounted: function () { clearTimeout(this.timer); },
    methods: {
      wait: function (ms) {
        var self = this;
        return new Promise(function (resolve) { self.timer = setTimeout(resolve, ms); });
      },
      type: async function (field, text, speed) {
        this[field] = "";
        for (var i = 0; i < text.length; i++) {
          this[field] += text[i];
          if (i % 2 === 0) await this.wait(speed);
        }
      },
      play: async function () {
        var scene = this.scenes[this.index];
        this.stage = 0; this.incoming = ""; this.instruction = ""; this.reply = "";
        await this.wait(400);
        this.stage = 1;
        await this.type("incoming", scene.incoming, 14);
        await this.wait(650);
        this.stage = 2;
        await this.type("instruction", scene.instruction, 16);
        await this.wait(500);
        this.stage = 3;   // «ойлану» күйі
        await this.wait(900);
        this.stage = 4;
        await this.type("reply", scene.reply, 12);
        await this.wait(2600);
        this.index = (this.index + 1) % this.scenes.length;
        this.play();
      },
      pick: function (i) { clearTimeout(this.timer); this.index = i; this.play(); }
    },
    template: `
      <div class="phone">
        <div class="phone-screen">
          <div class="chat-row" :class="{ 'is-on': stage >= 1 }">
            <div class="chat-label">{{ scenes[index].labelIncoming }}</div>
            <div class="bubble bubble-in">{{ incoming }}<span class="caret" v-if="stage === 1"></span></div>
          </div>
          <div class="chat-row" :class="{ 'is-on': stage >= 2 }">
            <div class="chat-label">{{ scenes[index].labelInstruction }}</div>
            <div class="bubble bubble-instruction">{{ instruction }}<span class="caret" v-if="stage === 2"></span></div>
          </div>
          <div class="chat-row" :class="{ 'is-on': stage >= 3 }">
            <div class="chat-label">{{ scenes[index].labelReply }}</div>
            <div class="bubble bubble-out" v-if="stage === 3"><span class="typing"><i></i><i></i><i></i></span></div>
            <div class="bubble bubble-out" v-else-if="stage >= 4">{{ reply }}</div>
          </div>
          <div class="kbd-hint">
            <span>AI Reply</span>
            <span class="kbd-keys"><i v-for="n in 5" :key="n"></i></span>
          </div>
        </div>
        <div class="phone-dots">
          <button v-for="(s, i) in scenes" :key="i" :class="{ 'is-active': i === index }"
                  @click="pick(i)" :aria-label="'demo ' + (i + 1)"></button>
        </div>
      </div>`
  };

  /* Санауыштар: көрінген сәтте нөлден нақты мәнге дейін өседі. */
  var Counter = {
    props: { value: { type: Number, default: 0 }, suffix: { type: String, default: "" } },
    data: function () { return { shown: 0 }; },
    mounted: function () {
      var self = this;
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          observer.disconnect();
          var start = performance.now(), duration = 1100;
          function step(now) {
            var progress = Math.min((now - start) / duration, 1);
            self.shown = Math.round(self.value * (1 - Math.pow(1 - progress, 3)));
            if (progress < 1) requestAnimationFrame(step);
          }
          requestAnimationFrame(step);
        });
      }, { threshold: 0.4 });
      observer.observe(this.$el);
    },
    template: `<span class="counter">{{ shown }}{{ suffix }}</span>`
  };

  Vue.createApp({ components: { Demo: Demo } }).mount("#hero-demo");
  Vue.createApp({ components: { Counter: Counter } }).mount("#stats-strip");

  /* Скролл кезінде секцияларды жұмсақ көрсету. */
  var reveal = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) { entry.target.classList.add("is-visible"); reveal.unobserve(entry.target); }
    });
  }, { threshold: 0.12 });
  document.querySelectorAll(".reveal").forEach(function (node) { reveal.observe(node); });

  /* Мобильді мәзір. */
  var toggle = document.querySelector(".nav-toggle");
  if (toggle) {
    toggle.addEventListener("click", function () {
      document.querySelector(".site-header").classList.toggle("is-open");
    });
    document.querySelectorAll(".nav a").forEach(function (link) {
      link.addEventListener("click", function () {
        document.querySelector(".site-header").classList.remove("is-open");
      });
    });
  }
})();
