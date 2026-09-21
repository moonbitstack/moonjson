// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Put `value` where `pointer` leads, and answer the document that results.
///
/// The semantics are RFC 6902's `add` and `replace` taken together: a member or
/// an element that is already there is replaced, one that is not is created, and
/// `-` as an array index appends — which is the one place RFC 6901 §4 says that
/// token means something, and the reason [`get`] refuses it.
///
/// It answers a new document rather than changing the one it was given. A tree
/// is shared: a value reached through two pointers is one value, and editing it
/// in place would change both. Only the path from the root to the edit is
/// rebuilt; everything else is the same value it was.
///
/// ```moonbit nocheck
/// let cfg = @pointer.set(cfg, "/spec/replicas", Json::number(5))
/// ```
pub fn set(doc : Json, pointer : StringView, value : Json) -> Json raise Bad {
  place(doc, tokens(pointer)[:], value)
}

///|
/// Take away whatever `pointer` leads to, and answer the document that results.
///
/// RFC 6902's `remove`: the member or the element must be there, because taking
/// away what was never there is a request nobody can have meant. The root cannot
/// be removed — an empty pointer names the whole document, and there would be
/// nothing left to answer with.
pub fn remove(doc : Json, pointer : StringView) -> Json raise Bad {
  let path = tokens(pointer)
  guard path.length() > 0 else { raise Bad::Syntax(at=0) }
  drop(doc, path[:])
}

///|
/// Rebuild the path down to the edit, leaving everything beside it untouched.
fn place(here : Json, path : ArrayView[String], value : Json) -> Json raise Bad {
  if path.length() == 0 {
    return value
  }
  let token = path[0]
  let rest = path[1:]
  match here {
    Object(members) => {
      let out : Map[String, Json] = Map([])
      for name, held in members {
        out[name] = held
      }
      let next = match members.get(token) {
        Some(found) => place(found, rest, value)
        None =>
          if rest.length() == 0 {
            value
          } else {
            // A pointer that runs past the end of the document is a pointer to
            // nowhere; inventing the objects along the way would make a typo
            // succeed.
            raise Missing(token~)
          }
      }
      out[token] = next
      Json::object(out)
    }
    Array(items) => {
      let out : Array[Json] = []
      for item in items {
        out.push(item)
      }
      if token == "-" {
        guard rest.length() == 0 else { raise Missing(token~) }
        out.push(value)
        return Json::array(out)
      }
      let index = index_of(token)
      guard index >= 0 && index < items.length() else { raise Missing(token~) }
      out[index] = place(items[index], rest, value)
      Json::array(out)
    }
    _ => raise NotContainer(token~)
  }
}

///|
/// The same rebuild, taking the last step away instead of replacing it.
fn drop(here : Json, path : ArrayView[String]) -> Json raise Bad {
  let token = path[0]
  let rest = path[1:]
  match here {
    Object(members) => {
      guard members.get(token) is Some(found) else { raise Missing(token~) }
      let out : Map[String, Json] = Map([])
      for name, held in members {
        if name != token {
          out[name] = held
        }
      }
      if rest.length() > 0 {
        out[token] = drop(found, rest)
      }
      Json::object(out)
    }
    Array(items) => {
      let index = index_of(token)
      guard index >= 0 && index < items.length() else { raise Missing(token~) }
      let out : Array[Json] = []
      for i, item in items {
        if i != index {
          out.push(item)
        } else if rest.length() > 0 {
          out.push(drop(item, rest))
        }
      }
      Json::array(out)
    }
    _ => raise NotContainer(token~)
  }
}
