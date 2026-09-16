// Әкімші панелінің шағын скрипті: графиктер (таза SVG) және растау сұхбаттары.
(function () {
  "use strict";

  function el(tag, attrs) {
    var node = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (var key in attrs) { if (attrs[key] !== undefined) node.setAttribute(key, attrs[key]); }
    return node;
  }

  function niceMax(value) {
    if (value <= 0) return 1;
    var magnitude = Math.pow(10, Math.floor(Math.log10(value)));
    var scaled = value / magnitude;
    var step = scaled <= 1 ? 1 : scaled <= 2 ? 2 : scaled <= 5 ? 5 : 10;
    return step * magnitude;
  }

  function render(container) {
    var points;
    try { points = JSON.parse(container.dataset.points || "[]"); } catch (e) { points = []; }
    var kind = container.dataset.kind || "line";
    if (!points.length) {
      container.innerHTML = '<div class="chart-empty">' + (container.dataset.empty || "—") + "</div>";
      return;
    }

    var width = container.clientWidth || 520, height = 190;
    var padLeft = 38, padRight = 10, padTop = 12, padBottom = 24;
    var innerW = width - padLeft - padRight, innerH = height - padTop - padBottom;
    var max = niceMax(Math.max.apply(null, points.map(function (p) { return p.value; })));

    var svg = el("svg", { class: "chart", viewBox: "0 0 " + width + " " + height, preserveAspectRatio: "none" });

    [0, 0.5, 1].forEach(function (ratio) {
      var y = padTop + innerH * ratio;
      svg.appendChild(el("line", { class: "grid-line", x1: padLeft, y1: y, x2: width - padRight, y2: y }));
      var label = el("text", { class: "tick", x: 4, y: y + 3.5 });
      label.textContent = formatNumber(max * (1 - ratio));
      svg.appendChild(label);
    });

    var stepX = points.length > 1 ? innerW / (points.length - 1) : 0;

    if (kind === "bar") {
      var barWidth = Math.max(4, Math.min(28, innerW / points.length - 6));
      points.forEach(function (p, i) {
        var h = (p.value / max) * innerH;
        var x = padLeft + (points.length > 1 ? i * (innerW / points.length) : innerW / 2 - barWidth / 2)
              + (innerW / points.length - barWidth) / 2;
        var rect = el("rect", { class: "bar", x: x, y: padTop + innerH - h, width: barWidth, height: Math.max(h, 1), rx: 4 });
        rect.appendChild(title(p));
        svg.appendChild(rect);
      });
    } else {
      var coords = points.map(function (p, i) {
        return [padLeft + i * stepX, padTop + innerH - (p.value / max) * innerH];
      });
      var path = coords.map(function (c, i) { return (i ? "L" : "M") + c[0].toFixed(1) + " " + c[1].toFixed(1); }).join(" ");
      svg.appendChild(el("path", {
        class: "area",
        d: path + " L" + coords[coords.length - 1][0] + " " + (padTop + innerH) + " L" + coords[0][0] + " " + (padTop + innerH) + " Z"
      }));
      svg.appendChild(el("path", { class: "line", d: path }));
      coords.forEach(function (c, i) {
        if (points.length > 24 && i % Math.ceil(points.length / 24) !== 0) return;
        var dot = el("circle", { class: "dot", cx: c[0], cy: c[1], r: 3 });
        dot.appendChild(title(points[i]));
        svg.appendChild(dot);
      });
    }

    var labelStep = Math.ceil(points.length / 6);
    points.forEach(function (p, i) {
      if (i % labelStep !== 0 && i !== points.length - 1) return;
      var x = padLeft + (kind === "bar" ? i * (innerW / points.length) + innerW / points.length / 2 : i * stepX);
      var text = el("text", { class: "tick", x: x, y: height - 7, "text-anchor": "middle" });
      text.textContent = shortLabel(p.label);
      svg.appendChild(text);
    });

    svg.appendChild(el("line", { class: "axis", x1: padLeft, y1: padTop + innerH, x2: width - padRight, y2: padTop + innerH }));
    container.innerHTML = "";
    container.appendChild(svg);
  }

  function title(point) {
    var node = el("title", {});
    node.textContent = point.label + ": " + formatNumber(point.value);
    return node;
  }

  function formatNumber(value) {
    if (value >= 1000000) return (value / 1000000).toFixed(1) + "M";
    if (value >= 1000) return (value / 1000).toFixed(1) + "k";
    return Math.round(value * 100) / 100;
  }

  function shortLabel(label) {
    return /^\d{4}-\d{2}-\d{2}$/.test(label) ? label.slice(5) : label;
  }

  function init() {
    document.querySelectorAll("[data-chart]").forEach(render);

    document.querySelectorAll("form[data-confirm]").forEach(function (form) {
      form.addEventListener("submit", function (event) {
        if (!window.confirm(form.dataset.confirm)) event.preventDefault();
      });
    });

    var burger = document.querySelector(".burger");
    if (burger) {
      burger.addEventListener("click", function () {
        document.querySelector(".sidebar").classList.toggle("is-open");
      });
    }
  }

  document.addEventListener("DOMContentLoaded", init);
  window.addEventListener("resize", function () {
    clearTimeout(window.__chartTimer);
    window.__chartTimer = setTimeout(function () { document.querySelectorAll("[data-chart]").forEach(render); }, 150);
  });
})();
