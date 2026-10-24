// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Apply a patch to a document, and answer the document that results.
///
/// The operations are applied in order, each to the result of the one before
/// it. A patch that fails partway applies nothing: the document it was given
/// is never changed, and the answer is the error rather than half a document —
/// RFC 6902 §5 says that if any operation is unsuccessful, application of the
/// entire patch document is not deemed successful.
///
/// It answers a new document rather than changing the one it was given, for
/// the same reason [`@pointer.set`] does: a tree is shared, and a value reached
/// through two pointers is one value.
pub fn apply(doc : Json, patch : ArrayView[Operation]) -> Json raise Failure {
  let mut out = doc
  for op in patch {
    out = step(out, op)
  }
  out
}

///|
/// One operation against one document.
fn step(doc : Json, op : Operation) -> Json raise Failure {
  match op {
    Add(path~, value~) => {
      let path_tokens = tokens_of(path)
      place(doc, path, path_tokens, value, insert=true)
    }
    Replace(path~, value~) => {
      let path_tokens = tokens_of(path)
      place(doc, path, path_tokens, value, insert=false)
    }
    Remove(path~) => {
      let path_tokens = tokens_of(path)
      extract(doc, path, path_tokens).0
    }
    Move(path~, from~) => {
      let from_tokens = tokens_of(from)
      let path_tokens = tokens_of(path)
      guard !is_prefix(from_tokens, path_tokens) else {
        raise IntoChild(from~, path~)
      }
      let (rest, moved) = extract(doc, from, from_tokens)
      if from_tokens == path_tokens {
        // A move to where the value already is changes nothing. Taking it away
        // and putting it back would move the member to the end of its object,
        // which is a change nobody asked for.
        return doc
      }
      place(rest, path, path_tokens, moved, insert=true)
    }
    Copy(path~, from~) => {
      let held = fetch(doc, from)
      let path_tokens = tokens_of(path)
      place(doc, path, path_tokens, held, insert=true)
    }
    Test(path~, value~) => {
      let held = fetch(doc, path)
      guard held == value else { raise TestFailed(path~) }
      doc
    }
  }
}

///|
/// Put a value where the pointer leads, rebuilding the path down to it and
/// leaving everything beside it the same value it was.
///
/// `insert` is the difference between `add` and `replace`: an `add` creates an
/// object member that is not there and inserts an array element, while a
/// `replace` requires the target to be there already. The pointer's error
/// handling is ignored for `add`, as RFC 6902 §4.1 says it must be — but the
/// object or the array the last step names still has to exist, so a pointer
/// that runs past the end of the document is a pointer to nowhere rather than
/// an invitation to invent the objects along the way.
fn place(
  doc : Json,
  path : String,
  tokens : ArrayView[String],
  value : Json,
  insert~ : Bool,
) -> Json raise Failure {
  if tokens.length() == 0 {
    // The root: the value becomes the entire content of the document.
    return value
  }
  match doc {
    Object(members) => {
      let token = tokens[0]
      let rest = tokens[1:]
      let next = if rest.length() == 0 {
        if !insert && members.get(token) is None {
          raise Missing(path~, token~)
        }
        value
      } else {
        match members.get(token) {
          Some(found) => place(found, path, rest, value, insert~)
          None => raise Missing(path~, token~)
        }
      }
      let out : Map[String, Json] = Map([])
      for name, held in members {
        out[name] = held
      }
      out[token] = next
      Json::object(out)
    }
    Array(items) => {
      let token = tokens[0]
      let rest = tokens[1:]
      if rest.length() == 0 {
        if token == "-" {
          // The one place RFC 6901 §4 gives that token a meaning, and only an
          // `add` may use it: `-` names a place that does not exist yet, so
          // there is nothing there to replace.
          guard insert else { raise BadIndex(path~, token~) }
          let out : Array[Json] = []
          for item in items {
            out.push(item)
          }
          out.push(value)
          return Json::array(out)
        }
        let index = index_of(token)
        guard index >= 0 else { raise BadIndex(path~, token~) }
        let out : Array[Json] = []
        if insert {
          // The index may equal the length, which appends; past that is a
          // pointer to nowhere.
          guard index <= items.length() else { raise Missing(path~, token~) }
          for at, item in items {
            if at == index {
              out.push(value)
            }
            out.push(item)
          }
          if index == items.length() {
            out.push(value)
          }
        } else {
          guard index < items.length() else { raise Missing(path~, token~) }
          for at, item in items {
            out.push(if at == index { value } else { item })
          }
        }
        return Json::array(out)
      }
      let index = index_of(token)
      guard index >= 0 else { raise BadIndex(path~, token~) }
      guard index < items.length() else { raise Missing(path~, token~) }
      let out : Array[Json] = []
      for at, item in items {
        if at == index {
          out.push(place(item, path, rest, value, insert~))
        } else {
          out.push(item)
        }
      }
      Json::array(out)
    }
    _ => raise NotContainer(path~, token=tokens[0])
  }
}

///|
/// Take away what the pointer leads to, answering the document that remains
/// and the value that was taken. This is RFC 6902's `remove`, and the first
/// half of `move`.
fn extract(
  doc : Json,
  path : String,
  tokens : ArrayView[String],
) -> (Json, Json) raise Failure {
  if tokens.length() == 0 {
    // The root names the whole document; there would be nothing to answer
    // with.
    raise Root(path~)
  }
  match doc {
    Object(members) => {
      let token = tokens[0]
      let rest = tokens[1:]
      guard members.get(token) is Some(found) else {
        raise Missing(path~, token~)
      }
      let out : Map[String, Json] = Map([])
      if rest.length() == 0 {
        for name, held in members {
          if name != token {
            out[name] = held
          }
        }
        (Json::object(out), found)
      } else {
        for name, held in members {
          out[name] = held
        }
        let (kept, value) = extract(found, path, rest)
        out[token] = kept
        (Json::object(out), value)
      }
    }
    Array(items) => {
      let token = tokens[0]
      let rest = tokens[1:]
      let index = index_of(token)
      guard index >= 0 else { raise BadIndex(path~, token~) }
      guard index < items.length() else { raise Missing(path~, token~) }
      let out : Array[Json] = []
      let mut value = Json::null()
      for at, item in items {
        if at != index {
          out.push(item)
        } else if rest.length() == 0 {
          value = item
        } else {
          let (kept, held) = extract(item, path, rest)
          out.push(kept)
          value = held
        }
      }
      (Json::array(out), value)
    }
    _ => raise NotContainer(path~, token=tokens[0])
  }
}

///|
/// Read what a pointer leads to, as `test` and the `from` of a `copy` need it.
/// `-` is refused here even though RFC 6901 §4 names it: it means one past the
/// last element, which exists only for an `add`.
fn fetch(doc : Json, path : String) -> Json raise Failure {
  @pointer.get(doc, path[:]) catch {
    e => raise blame(path, e)
  }
}

///|
/// Split a pointer into the names it walks through, naming the pointer if it
/// is not one.
fn tokens_of(path : String) -> Array[String] raise Failure {
  @pointer.tokens(path[:]) catch {
    e => raise blame(path, e)
  }
}

///|
/// A pointer failure, named by the pointer that caused it.
fn blame(path : String, e : @pointer.Bad) -> Failure {
  match e {
    @pointer.Bad::Syntax(at~) => Failure::Syntax(path~, at~)
    @pointer.Bad::Missing(token~) => Failure::Missing(path~, token~)
    @pointer.Bad::NotContainer(token~) => Failure::NotContainer(path~, token~)
  }
}

///|
/// Whether `from` names a parent of `path` — the one move RFC 6902 §4.4
/// forbids. Equal is not a proper prefix: a move to where the value already is
/// is allowed and changes nothing.
fn is_prefix(from : Array[String], path : Array[String]) -> Bool {
  if from.length() >= path.length() {
    return false
  }
  for at in 0..<from.length() {
    if from[at] != path[at] {
      return false
    }
  }
  true
}

///|
/// An array index as RFC 6901 §4 writes one: decimal digits, and no leading
/// zero unless the index is zero itself. `-` is not an index — it is the
/// append marker, and only an `add` may use it.
fn index_of(token : String) -> Int32 {
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
