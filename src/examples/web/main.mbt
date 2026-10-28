// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Hand the entry points to the page. The closures are passed as JavaScript
/// functions, and the page stores them on `globalThis.moonjson`.
extern "js" fn expose(
  format : (String, Int32, Bool, Bool, Bool, String) -> String,
  notation : (String, String, String) -> String,
  dialects : () -> String,
) -> Unit = "function(format, notation, dialects){ globalThis.moonjson = { format: format, notation: notation, dialects: dialects }; }"

///|
/// The reader a dialect names. Every one of them is this library's own reader,
/// so a document is read the way the corresponding package reads it and a
/// refusal is the one that package would give.
fn read(text : StringView, dialect : String) -> Json raise @moonjson.Refused {
  match dialect {
    "jsonc" => @jsonc.loads(text)
    "json5" => @json5.loads(text)
    "hjson" => @hjson.loads(text)
    "cson" => @cson.loads(text)
    _ => @json.loads(text)
  }
}

///|
/// An answer the page can read: `{"ok": true, "text": "…"}` or
/// `{"ok": false, "text": "line 3, column 8: …"}`. The failure sentence is
/// `Refused::message`, printed by the library, not written by the page.
fn reply(ok : Bool, text : String) -> String {
  let members : Map[String, Json] = Map([])
  members["ok"] = Json::boolean(ok)
  members["text"] = Json::string(text)
  @json.dumps(Json::object(members))
}

///|
/// The readers the page offers, in the order it offers them.
fn dialect_list() -> String {
  reply(true, "json,jsonc,json5,hjson,cson")
}

///|
/// `format(text, indent, tabs, sort, ascii, dialect)` lays a document out, and
/// `notation(text, which, dialect)` writes it in one notation — both compiled
/// from this library, so the page shows the real output, not a copy of it.
fn main {
  expose(
    fn(text, indent, tabs, sort, ascii, dialect) {
      try {
        let value = read(text[:], dialect)
        let style = @pretty.Format::new(indent~, tabs~, sort~, ascii~)
        reply(true, @pretty.format(value, style~))
      } catch {
        error => reply(false, error.message())
      }
    },
    fn(text, which, dialect) {
      try {
        let value = read(text[:], dialect)
        let written = match which {
          "json" => @json.dumps(value)
          "pretty" => @json.dumps(value, indent=2)
          "cbor" => @hex.encode(@cbor.dump(value)[:])
          "cbd" => @hex.encode(@cbd.dump(value)[:])
          "ubjson" => @hex.encode(@ubjson.dump(value)[:])
          "smile" => @hex.encode(@smile.dump(value)[:])
          "sqlite" => @hex.encode(@sqlite.dump(value)[:])
          "pg" => @hex.encode(@pg.dump(value)[:])
          "ndjson" =>
            match value {
              Array(items) => @lines.dumps_all(items)
              _ => @lines.dumps_all([value])
            }
          _ => ""
        }
        if written == "" {
          reply(false, "no such notation: " + which)
        } else {
          reply(true, written)
        }
      } catch {
        error => reply(false, error.message())
      }
    },
    fn() { dialect_list() },
  )
}
