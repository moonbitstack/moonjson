// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a pointer did not lead anywhere.
pub(all) suberror Bad {
  /// A pointer that is not empty and does not start with a slash (RFC 6901 §3),
  /// or a `~` followed by anything but `0` or `1`.
  Syntax(at~ : Int)
  /// A name no object has, or an index no array reaches.
  Missing(token~ : String)
  /// A token used where the document holds neither an object nor an array — a
  /// pointer that walks into a number and keeps going.
  NotContainer(token~ : String)
} derive(Eq, Debug)

///|
pub extend Bad with Eq::{equal, not_equal}

///|
pub extend Bad with Debug::{to_repr}

///|
/// Split a pointer into the names it walks through, undoing the escapes.
///
/// The empty pointer names the whole document and yields no tokens; `"/"` names
/// the member whose name is empty and yields one.
pub fn tokens(pointer : StringView) -> Array[String] raise Bad {
  let out : Array[String] = []
  if pointer.length() == 0 {
    return out
  }
  if pointer.at(0).to_int() != 0x2F {
    raise Syntax(at=0)
  }
  let piece = StringBuilder()
  let mut i = 1
  while i <= pointer.length() {
    if i == pointer.length() || pointer.at(i).to_int() == 0x2F {
      out.push(piece.to_string())
      piece.reset()
    } else if pointer.at(i).to_int() == 0x7E {
      match
        (if i + 1 < pointer.length() { pointer.at(i + 1).to_int() } else { -1 }) {
        0x30 => piece.write_char('~')
        0x31 => piece.write_char('/')
        _ => raise Syntax(at=i)
      }
      i += 1
    } else {
      piece.write_view(pointer[i:i + 1])
    }
    i += 1
  }
  out
}

///|
/// Write a name so it can go into a pointer: `~` first, then `/`.
pub fn escape(token : StringView) -> String {
  let out = StringBuilder()
  for i in 0..<token.length() {
    match token.at(i).to_int() {
      0x7E => out.write_string("~0")
      0x2F => out.write_string("~1")
      _ => out.write_view(token[i:i + 1])
    }
  }
  out.to_string()
}

///|
/// Join names into a pointer, escaping each.
pub fn join(names : ArrayView[String]) -> String {
  let out = StringBuilder()
  for name in names {
    out.write_char('/')
    out.write_string(escape(name[:]))
  }
  out.to_string()
}

///|
/// Follow a pointer and return what is there.
///
/// `-` as an array index is refused here even though RFC 6901 §4 names it: it
/// means "one past the last element", which exists only for JSON Patch's `add`,
/// and returning something for it would be inventing a value.
pub fn get(doc : Json, pointer : StringView) -> Json raise Bad {
  let mut here = doc
  for token in tokens(pointer) {
    here = step(here, token)
  }
  here
}

///|
/// Whether a pointer leads anywhere. A malformed pointer is not an exception
/// here — it simply does not lead anywhere.
pub fn has(doc : Json, pointer : StringView) -> Bool {
  try {
    get(doc, pointer) |> ignore
    true
  } catch {
    _ => false
  }
}

///|
fn step(here : Json, token : String) -> Json raise Bad {
  match here {
    Object(members) =>
      match members.get(token) {
        Some(next) => next
        None => raise Missing(token~)
      }
    Array(items) => {
      let index = index_of(token)
      if index < 0 || index >= items.length() {
        raise Missing(token~)
      }
      items[index]
    }
    _ => raise NotContainer(token~)
  }
}

///|
/// An array index as RFC 6901 §4 writes one: decimal digits, and no leading
/// zero unless the index is zero itself.
fn index_of(token : String) -> Int {
  if token.length() == 0 {
    return -1
  }
  if token.length() > 1 && token.at(0).to_int() == 0x30 {
    return -1
  }
  let mut value = 0
  for i in 0..<token.length() {
    let c = token.at(i).to_int()
    if c < 0x30 || c > 0x39 {
      return -1
    }
    value = value * 10 + (c - 0x30)
    if value > 0x3FFFFFFF {
      return -1
    }
  }
  value
}
