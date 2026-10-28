// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Hand the two entry points to the page. The closure is passed as a JavaScript
/// function, and the page stores it on `globalThis.moonjson`.
extern "js" fn expose(
  format : (String, Int32, Bool, Bool, Bool) -> String,
  notation : (String, String) -> String,
) -> Unit = "function(format, notation){ globalThis.moonjson = { format: format, notation: notation }; }"

///|
/// `format(text, indent, tabs, sort, ascii)` lays a document out, and
/// `notation(text, which)` writes it in one notation — both compiled from this
/// library, so the page shows the real output, not a copy of it.
fn main {
  expose(
    fn(text, indent, tabs, sort, ascii) {
      try {
        let value = @json.loads(text[:])
        let style = @pretty.Format::new(indent~, tabs~, sort~, ascii~)
        @pretty.format(value, style~)
      } catch {
        _ => "// not JSON"
      }
    },
    fn(text, which) {
      try {
        let value = @json.loads(text[:])
        match which {
          "json" => @json.dumps(value)
          "pretty" => @json.dumps(value, indent=2)
          "cbor" => @hex.encode(@cbor.dump(value)[:])
          "cbd" => @hex.encode(@cbd.dump(value)[:])
          "ubjson" => @hex.encode(@ubjson.dump(value)[:])
          "smile" => @hex.encode(@smile.dump(value)[:])
          "sqlite" => @hex.encode(@sqlite.dump(value)[:])
          "pg" => @hex.encode(@pg.dump(value)[:])
          _ => "// unknown notation"
        }
      } catch {
        _ => "// not JSON"
      }
    },
  )
}
