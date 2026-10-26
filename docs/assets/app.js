// moonjson site behaviour: the theme follows the system until a reader says
// otherwise, code blocks are highlighted and copyable, and the table of
// contents follows the scroll. No dependencies.
(function () {
  "use strict";

  var root = document.documentElement;

  // --- theme ---------------------------------------------------------------

  var stored = null;
  try {
    stored = localStorage.getItem("moonjson-theme");
  } catch (e) {
    stored = null;
  }
  var systemDark =
    window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  applyTheme(stored || (systemDark ? "dark" : "light"));

  function applyTheme(theme) {
    root.setAttribute("data-theme", theme);
    var button = document.querySelector("[data-theme-toggle]");
    if (button) {
      button.setAttribute(
        "aria-label",
        theme === "dark" ? "Switch to the light theme" : "Switch to the dark theme"
      );
    }
  }

  document.addEventListener("click", function (event) {
    var toggle = event.target.closest("[data-theme-toggle]");
    if (!toggle) {
      return;
    }
    var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    applyTheme(next);
    try {
      localStorage.setItem("moonjson-theme", next);
    } catch (e) {
      /* a reader who refuses cookies keeps the theme for this page */
    }
  });

  // --- syntax highlighting --------------------------------------------------

  var MOONBIT_KEYWORDS = [
    "let", "mut", "fn", "match", "if", "else", "for", "in", "while", "return",
    "raise", "guard", "try", "catch", "noraise", "test", "struct", "enum",
    "derive", "pub", "priv", "import", "type", "trait", "impl", "as", "is",
    "const", "true", "false"
  ];
  var MOONBIT_TYPES = [
    "Json", "String", "Int", "Int32", "Int64", "Bool", "Double", "Char", "Byte",
    "Array", "ArrayView", "Map", "StringView", "Bytes", "BytesView",
    "StringBuilder", "Unit", "Some", "None", "Ok", "Err"
  ];

  function span(cls, text) {
    var el = document.createElement("span");
    el.className = cls;
    el.textContent = text;
    return el;
  }

  // A combined pass over the text, longest and most specific first. Each
  // alternative keeps its own class so the order below is the only rule.
  function tokenize(text, lang) {
    var comments = ["(\\/\\/[^\\n]*)"];
    var keywords = [];
    var literals = ["true", "false", "null"];
    if (lang === "bash") {
      comments.push("(#[^\\n]*)");
    }
    if (lang === "moonbit") {
      keywords = MOONBIT_KEYWORDS.concat(["null"]);
    }
    if (lang === "json" || lang === "jsonc" || lang === "json5") {
      literals = [];
    }
    var word = keywords.concat(literals, MOONBIT_TYPES).map(escapeRegExp);
    var pattern = new RegExp(
      comments
        .concat([
          "(#\\|[^\\n]*)", // raw string opener
          "(\"(?:[^\"\\\\\\n]|\\\\.)*\")", // string
          "('(?:[^'\\\\\\n]|\\\\.)*')", // single-quoted string
          "\\b(\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?|0[xX][0-9a-fA-F]+)\\b", // number
          word.length ? "\\b(" + word.join("|") + ")\\b" : "()", // word
          "(@[A-Za-z_][A-Za-z0-9_]*)", // attribute or package
          "([{}()\\[\\];:,.<>=+\\-*/!?&|])" // punctuation
        ])
        .join("|"),
      "g"
    );
    var nodes = [];
    var last = 0;
    var m;
    while ((m = pattern.exec(text)) !== null) {
      if (m.index > last) {
        nodes.push(document.createTextNode(text.slice(last, m.index)));
      }
      var cls = null;
      if (m[1] || m[2]) cls = "tok-comment";
      else if (m[3]) cls = "tok-string";
      else if (m[4] || m[5]) cls = "tok-string";
      else if (m[6]) cls = "tok-number";
      else if (m[7]) {
        cls =
          literals.indexOf(m[7]) >= 0
            ? "tok-literal"
            : MOONBIT_TYPES.indexOf(m[7]) >= 0 && lang === "moonbit"
              ? "tok-attr"
              : "tok-keyword";
      } else if (m[8]) cls = "tok-attr";
      else if (m[9]) cls = "tok-punct";
      nodes.push(cls ? span(cls, m[0]) : document.createTextNode(m[0]));
      last = m.index + m[0].length;
    }
    if (last < text.length) {
      nodes.push(document.createTextNode(text.slice(last)));
    }
    return nodes;
  }

  function escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  function highlightBlock(pre) {
    var lang = pre.getAttribute("data-lang") || "moonbit";
    var text = pre.textContent;
    pre.textContent = "";
    var nodes = tokenize(text, lang);
    for (var i = 0; i < nodes.length; i++) {
      pre.appendChild(nodes[i]);
    }
  }

  var blocks = document.querySelectorAll("pre[data-lang]");
  for (var i = 0; i < blocks.length; i++) {
    highlightBlock(blocks[i]);
  }

  // --- copy buttons ----------------------------------------------------------

  function flash(button, text) {
    var original = button.textContent;
    button.textContent = text;
    window.setTimeout(function () {
      button.textContent = original;
    }, 1600);
  }

  function copyText(text, button) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(
        function () {
          flash(button, "copied");
        },
        function () {
          flash(button, "press ⌘C");
        }
      );
    } else {
      flash(button, "press ⌘C");
    }
  }

  var copies = document.querySelectorAll("[data-copy]");
  for (var j = 0; j < copies.length; j++) {
    copies[j].addEventListener("click", function () {
      var target = document.querySelector(this.getAttribute("data-copy"));
      if (target) {
        copyText(target.textContent, this);
      }
    });
  }

  // --- table of contents -------------------------------------------------------

  var tocLinks = document.querySelectorAll(".docs-toc a[href^='#']");
  if (tocLinks.length && window.IntersectionObserver) {
    var byId = {};
    var sections = [];
    for (var k = 0; k < tocLinks.length; k++) {
      var id = tocLinks[k].getAttribute("href").slice(1);
      var section = document.getElementById(id);
      if (section) {
        byId[id] = tocLinks[k];
        sections.push(section);
      }
    }
    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            for (var id in byId) {
              byId[id].classList.remove("active");
            }
            var link = byId[entry.target.id];
            if (link) {
              link.classList.add("active");
            }
          }
        });
      },
      { rootMargin: "-80px 0px -70% 0px" }
    );
    for (var s = 0; s < sections.length; s++) {
      observer.observe(sections[s]);
    }
  }
})();
