#!/usr/bin/env python3
"""Write `docs/api.html` from the packages' interfaces and their doc comments.

The interface of a MoonBit package is `pkg.generated.mbti`, which `moon info`
writes from the source; the prose is the `///` block above each declaration.
This script joins the two: every public value, type, field, variant and method,
grouped by package and sorted by name, each with the sentence its author wrote
about it.

It refuses to write a page with a hole in it. A public item without a doc
comment is a bug in the source, not something to render as an empty paragraph,
so the script names the item and exits non-zero. CI runs it and compares the
result with what is committed, which is what keeps the page honest:

    python scripts/gen_api.py
    git diff --exit-code docs/api.html
"""

import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The order is the order the guide reads in: the tree and its reader first, the
# dialects, then the three ways of changing a document, then the encodings.
PACKAGES = [
    ("moonjson", "src"),
    ("json", "src/json"),
    ("jsonc", "src/jsonc"),
    ("json5", "src/json5"),
    ("lines", "src/lines"),
    ("pointer", "src/pointer"),
    ("patch", "src/patch"),
    ("merge", "src/merge"),
    ("path", "src/path"),
    ("jcs", "src/jcs"),
    ("cbor", "src/cbor"),
    ("msgpack", "src/msgpack"),
    ("bson", "src/bson"),
    ("ubjson", "src/ubjson"),
    ("smile", "src/smile"),
    ("bjson", "src/bjson"),
    ("krson", "src/krson"),
    ("cbd", "src/cbd"),
    ("sqlite", "src/jsonb/sqlite"),
    ("pg", "src/jsonb/pg"),
    ("superjson", "src/superjson"),
    ("ntv", "src/ntv"),
    ("rjson", "src/rjson"),
    ("json11", "src/json11"),
    ("jsonz", "src/jsonz"),
    ("zson", "src/zson"),
    ("zjson", "src/zjson"),
    ("cson", "src/cson"),
    ("hjson", "src/hjson"),
    ("sink", "src/sink"),
    ("source", "src/source"),
    ("pretty", "src/pretty"),
]

# Methods that a `derive` writes. They are part of the interface and not part of
# what an author wrote, so the page names them once under the type rather than
# pretending to explain `not_equal` three times.
DERIVED = {"equal", "not_equal", "to_repr", "to_string"}


class Failure(Exception):
    pass


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def strip_marker(lines):
    """A doc block, without the `///|` marker that opens one."""
    out = []
    for line in lines:
        text = line[3:].lstrip()
        if text in ("|", ""):
            out.append("")
        else:
            out.append(text)
    while out and out[0] == "":
        out.pop(0)
    while out and out[-1] == "":
        out.pop()
    return out


def parse_interface(path):
    """The public items of a package, in the order the interface file has them.

    A type owns its fields or variants, and the methods called on it.
    """
    items = []
    current = None
    for raw in read(path).splitlines():
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        match = re.match(r"pub\s*(?:\(all\)\s*)?(suberror|enum|struct) (\w+)", line)
        if match:
            kind = {"suberror": "error", "enum": "enum", "struct": "struct"}[
                match.group(1)
            ]
            current = {
                "kind": kind,
                "name": match.group(2),
                "sig": line.rstrip(" {"),
                "members": [],
                "methods": [],
            }
            items.append(current)
            continue
        if line.startswith("}"):
            current = None
            continue
        if current is not None and (current["kind"] in ("enum", "error")):
            match = re.match(r"([A-Z]\w*)(.*)", line)
            if match:
                current["members"].append(
                    {"name": match.group(1), "sig": line.rstrip(","), "kind": "variant"}
                )
                continue
        if current is not None and current["kind"] == "struct":
            match = re.match(r"(\w+)\s*:\s*(.+)", line)
            if match:
                current["members"].append(
                    {
                        "name": match.group(1),
                        "sig": "%s : %s" % (match.group(1), match.group(2)),
                        "kind": "field",
                    }
                )
                continue
        match = re.match(r"pub (fn|let) (\w+)(::\w+)?(.*)", line)
        if match:
            what, name, method, rest = match.groups()
            entry = {
                "kind": what,
                "name": method[2:] if method else name,
                "sig": line,
                "members": [],
                "methods": [],
            }
            if method:
                owner = name
                for item in items:
                    if item["name"] == owner and "members" in item:
                        item["methods"].append(entry)
                        break
            else:
                items.append(entry)
            continue
    return items


def parse_docs(directory):
    """What each declaration's `///` block says, by name.

    A field or a variant is named `Type.member`; everything else by its own
    name. Only the first doc block for a name counts, because a name declared
    twice is a mistake the interface file would already have shown.
    """
    docs = {}

    def remember(key, block):
        docs.setdefault(key, strip_marker(block) if block else [])

    for name in sorted(os.listdir(directory)):
        if not name.endswith(".mbt") or name.endswith("_test.mbt"):
            continue
        block = []
        owner = None
        for raw in read(os.path.join(directory, name)).splitlines():
            line = raw.strip()
            if line.startswith("///"):
                block.append(line)
                continue
            if not line:
                continue
            if owner is not None:
                # Inside a struct or enum: the members are the declarations.
                if line.startswith("}"):
                    owner = None
                else:
                    member = re.match(r"(\w+)\s*:|([A-Z]\w*)\s*(?:[\(,]|$)", line)
                    if member:
                        remember(
                            "%s.%s" % (owner, member.group(1) or member.group(2)),
                            block,
                        )
                block = []
                continue
            match = re.match(
                r"pub\s*(?:\(all\)\s*)?(suberror|enum|struct|fn|let)\s+(\w+(?:::\w+)?)",
                line,
            )
            if match:
                key = match.group(2)
                if key in ("equal", "not_equal", "to_repr", "to_string"):
                    block = []
                    continue
                remember(key, block)
                if match.group(1) in ("suberror", "enum", "struct"):
                    owner = key
                block = []
                continue
            block = []
    return docs


def package_summary(directory):
    """The sentence that says what a package is for.

    The first paragraph of the `//` comment on its `moon.pkg`, unless that
    paragraph is the specification's name and address — which is a reference,
    not a description — in which case the paragraph after it is.
    """
    paragraphs = []
    current = []
    for line in read(os.path.join(directory, "moon.pkg")).splitlines():
        if not line.startswith("//"):
            break
        text = line[2:].strip()
        if not text:
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        current.append(text)
    if current:
        paragraphs.append(" ".join(current))
    for paragraph in paragraphs:
        if "http://" not in paragraph and "https://" not in paragraph:
            return paragraph
    return paragraphs[0] if paragraphs else ""


def inline(text):
    """Escape, then put back the two marks the doc comments use."""
    out = html.escape(text, quote=False)
    out = re.sub(r"\[`([^`]+)`\]", r"<code>\1</code>", out)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    return out


def prose(lines):
    """A doc block as HTML: paragraphs, lists, tables and code fences.

    The dialect is small on purpose. A doc comment is read as prose by whoever
    opens the source, and a page that renders a different thing from what the
    source says would be worse than a plain one.
    """
    out = []
    block = []
    index = 0

    def flush():
        if not block:
            return
        joined = " ".join(block)
        out.append("<p>%s</p>" % inline(joined))
        block.clear()

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if stripped.startswith("```"):
            flush()
            language = stripped[3:].strip() or "mbt"
            index += 1
            code = []
            while index < len(lines) and not lines[index].strip().startswith("```"):
                code.append(lines[index])
                index += 1
            index += 1
            out.append(
                '<div class="code-card"><div class="bar"><span class="lang">%s</span>'
                '<span class="spacer"></span></div><pre>%s</pre></div>'
                % (html.escape(language), html.escape("\n".join(code)))
            )
            continue
        if not stripped:
            flush()
            index += 1
            continue
        if stripped.startswith("|"):
            flush()
            rows = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                rows.append(lines[index].strip())
                index += 1
            out.append(table(rows))
            continue
        if stripped.startswith("- "):
            flush()
            items = []
            while index < len(lines) and lines[index].strip().startswith("- "):
                items.append(lines[index].strip()[2:])
                index += 1
            out.append(
                "<ul>%s</ul>" % "".join("<li>%s</li>" % inline(item) for item in items)
            )
            continue
        block.append(stripped)
        index += 1
    flush()
    return "\n".join(out)


def table(rows):
    """A pipe table from a doc comment; the first row is the head."""
    def cells(row):
        return [cell.strip() for cell in row.strip("|").split("|")]

    head = cells(rows[0])
    body = [row for row in rows[1:] if not re.match(r"^\|[\s:|-]+\|$", row)]
    out = ['<div class="table-card"><table><thead><tr>']
    out.extend("<th>%s</th>" % inline(cell) for cell in head)
    out.append("</tr></thead><tbody>")
    for row in body:
        out.append("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(cell) for cell in cells(row)))
    out.append("</tbody></table></div>")
    return "".join(out)


def anchor(package, name):
    return "%s-%s" % (package, name.replace("::", "-").lower())


def signature(text):
    return '<code class="api-signature">%s</code>' % html.escape(text, quote=False)


def render_package(package, directory):
    interface = os.path.join(directory, "pkg.generated.mbti")
    if not os.path.exists(interface):
        raise Failure("%s has no pkg.generated.mbti" % directory)
    items = parse_interface(interface)
    docs = parse_docs(directory)
    missing = []

    values = [item for item in items if item["kind"] in ("fn", "let")]
    types = [item for item in items if item["kind"] in ("struct", "enum")]
    errors = [item for item in items if item["kind"] == "error"]

    chunks = []
    for item in sorted(values, key=lambda entry: entry["name"]):
        doc = docs.get(item["name"])
        if not doc:
            missing.append(item["name"])
            doc = []
        chunks.append(
            '<article class="api-item" id="%s">'
            '<h3>%s</h3>%s%s</article>'
            % (
                anchor(package, item["name"]),
                html.escape(item["name"]),
                signature(item["sig"]),
                prose(doc),
            )
        )

    for item in sorted(types + errors, key=lambda entry: entry["name"]):
        doc = docs.get(item["name"])
        if not doc:
            missing.append(item["name"])
            doc = []
        body = [signature(item["sig"]), prose(doc)]
        if item["members"]:
            label = "Fields" if item["kind"] == "struct" else "Variants"
            members = []
            for member in item["members"]:
                key = "%s.%s" % (item["name"], member["name"])
                member_doc = docs.get(key)
                if not member_doc:
                    missing.append(key)
                    member_doc = []
                members.append(
                    '<li><span class="api-member">%s</span>%s</li>'
                    % (signature(member["sig"]), prose(member_doc))
                )
            body.append(
                '<div class="api-members"><div class="api-label">%s</div>'
                "<ul>%s</ul></div>" % (label, "".join(members))
            )
        if item["methods"]:
            methods = []
            for method in sorted(item["methods"], key=lambda entry: entry["name"]):
                key = "%s::%s" % (item["name"], method["name"])
                method_doc = docs.get(key)
                if not method_doc and method["name"] in DERIVED:
                    method_doc = [
                        "Written by `derive(%s)`."
                        % ("Debug" if method["name"] == "to_repr" else "Eq")
                    ]
                if not method_doc:
                    missing.append(key)
                    method_doc = []
                methods.append(
                    '<li><span class="api-member">%s</span>%s</li>'
                    % (signature(method["sig"]), prose(method_doc))
                )
            body.append(
                '<div class="api-members"><div class="api-label">Methods</div>'
                "<ul>%s</ul></div>" % "".join(methods)
            )
        chunks.append(
            '<article class="api-item" id="%s"><h3>%s</h3>%s</article>'
            % (anchor(package, item["name"]), html.escape(item["name"]), "".join(body))
        )

    if not chunks:
        raise Failure("%s has no public items" % package)
    return {
        "name": package,
        "summary": package_summary(directory),
        "body": "".join(chunks),
        "missing": missing,
        "items": items,
    }


def page(packages):
    toc = "".join(
        '<a href="#%s">%s</a>' % (package["name"], html.escape(package["name"]))
        for package in packages
    )
    sections = []
    for package in packages:
        sections.append(
            '<section id="%s">'
            '<div class="section-head"><div class="kicker">package</div>'
            "<h2>%s</h2><p>%s</p></div>"
            '<div class="api-body">%s</div></section>'
            % (
                package["name"],
                html.escape(package["name"]),
                inline(package["summary"]),
                package["body"],
            )
        )
    return TEMPLATE.replace("{{TOC}}", toc).replace("{{SECTIONS}}", "".join(sections))


TEMPLATE = """<!DOCTYPE html>
<html lang="en-NZ">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>API — moonjson</title>
    <meta
      name="description"
      content="Every public package, type, value, field and method of moonjson, with the sentence its author wrote about it."
    />
    <link rel="stylesheet" href="assets/style.css?v=4" />
    <script type="module" src="assets/scrollbar.js"></script>
    <link
      rel="icon"
      href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='8' fill='%234f46e5'/%3E%3Ctext x='16' y='22' font-family='monospace' font-size='16' font-weight='bold' fill='white' text-anchor='middle'%3E%7B%7D%3C/text%3E%3C/svg%3E"
    />
    <script>
      (function () {
        try {
          var t = localStorage.getItem("moonjson-theme");
        } catch (e) {
          t = null;
        }
        if (!t) {
          t = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)")
            .matches
            ? "dark"
            : "light";
        }
        document.documentElement.setAttribute("data-theme", t);
      })();
    </script>
  </head>
  <body>
    <header class="site-header">
      <div class="inner">
        <a class="wordmark" href="index.html">
          <span class="glyph">{}</span>
          <span>moonjson</span>
        </a>
        <nav class="site-nav" aria-label="Main">
          <a href="index.html">Home</a>
          <a href="docs.html">Docs</a>
          <a href="api.html" aria-current="page">API</a>
          <a href="examples.html">Examples</a>
          <a href="showcase.html">Showcase</a>
        </nav>
        <div class="header-tools">
          <button class="icon-button" type="button" data-theme-toggle aria-label="Switch theme">
            <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
              <circle cx="12" cy="12" r="4" />
              <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
            </svg>
            <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
              <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
            </svg>
          </button>
          <a class="icon-button" href="https://github.com/moonbitstack/moonjson" aria-label="GitHub repository">
            <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path d="M12 .5a12 12 0 0 0-3.8 23.4c.6.1.8-.3.8-.6v-2c-3.3.7-4-1.6-4-1.6-.6-1.4-1.4-1.8-1.4-1.8-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.8-1.6-2.7-.3-5.5-1.3-5.5-6 0-1.2.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.1 0 4.7-2.8 5.7-5.5 6 .4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A12 12 0 0 0 12 .5z" />
            </svg>
          </a>
        </div>
      </div>
    </header>

    <main class="wrap">
      <div class="docs-layout" style="padding-top: 56px; padding-bottom: 24px">
        <aside class="docs-toc" aria-label="Table of contents">
          <div class="title">Packages</div>
          {{TOC}}
        </aside>

        <div class="docs-body">
          <div class="section-head">
            <div class="kicker">reference</div>
            <h2>Everything public</h2>
            <p>
              One section per package, in the order the guide reads them. Each
              item is the declaration the compiler sees and the sentence the
              source wrote about it.
            </p>
          </div>
          {{SECTIONS}}
        </div>
      </div>
    </main>

    <footer class="site-footer">
      <div class="inner">
        <span>moonjson — the JSON family for MoonBit. Apache-2.0.</span>
        <div class="links">
          <a href="docs.html">Docs</a>
          <a href="examples.html">Examples</a>
          <a href="api.html">API</a>
          <a href="https://github.com/moonbitstack/moonjson">GitHub</a>
        </div>
      </div>
    </footer>

    <script src="assets/app.js?v=3"></script>
  </body>
</html>
"""


def main(argv):
    packages = []
    missing = []
    for name, directory in PACKAGES:
        package = render_package(name, os.path.join(ROOT, directory))
        packages.append(package)
        missing.extend("%s: %s" % (name, item) for item in package["missing"])
    if missing:
        for item in missing:
            print("no doc comment for", item, file=sys.stderr)
        print("%d public items have no description" % len(missing), file=sys.stderr)
        return 1
    target = os.path.join(ROOT, "docs", "api.html")
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write(page(packages))
    print("api: %d packages, %d items" % (len(packages), sum(
        len(package["items"]) for package in packages)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
