// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One operation in a patch document, as RFC 6902 §4 names the six.
pub(all) enum Operation {
  /// Put `value` where `path` leads (RFC 6902 §4.1).
  ///
  /// An object member that is not there is created, one that is there is
  /// replaced, and an array element is inserted — the elements at or above the
  /// index shift one place to the right — with `-` appending at the end. The
  /// root is a target too: an `add` to the empty pointer makes the value the
  /// whole document.
  Add(path~ : String, value~ : Json)
  /// Take away what `path` leads to (RFC 6902 §4.2).
  ///
  /// It has to be there: taking away what was never there is a request nobody
  /// can have meant. The root cannot be taken away — the empty pointer names
  /// the whole document, and there would be nothing left to answer with.
  Remove(path~ : String)
  /// Replace the value at `path` (RFC 6902 §4.3).
  ///
  /// The target has to be there already; this is `add` without the creating.
  Replace(path~ : String, value~ : Json)
  /// Take the value at `from` away and put it at `path` (RFC 6902 §4.4).
  ///
  /// `from` must not be a parent of `path`: a location cannot be moved into
  /// one of its own children.
  Move(path~ : String, from~ : String)
  /// Copy the value at `from` to `path` (RFC 6902 §4.5).
  Copy(path~ : String, from~ : String)
  /// Require the value at `path` to equal `value` (RFC 6902 §4.6).
  ///
  /// Equality is the tree's: a number equals the same number written another
  /// way, because the tree holds a number as a number and not as text.
  Test(path~ : String, value~ : Json)
} derive(Eq, Debug)

///|
pub extend Operation with Eq::{equal, not_equal}

///|
pub extend Operation with Debug::{to_repr}

///|
/// Why a patch could not be read, or could not be applied.
///
/// A pointer that failed is named in full, because a `move` and a `copy` each
/// carry two and an error that did not say which one would be half an error.
pub(all) suberror Failure {
  /// The document is not JSON at all: the scanner refused it, and says where.
  Unreadable(@moonjson.Malformed)
  /// The document is JSON but not a patch: not an array of operations.
  Document(why~ : String)
  /// The operation at `at` is not an operation object — no `op` member, an
  /// `op` that is not one of the six, or a member the operation requires
  /// missing or of the wrong type. `at` is its position in the array.
  Operation(at~ : Int32, why~ : String)
  /// The pointer is not one (RFC 6901 §3): it does not start with a slash, or
  /// a `~` is followed by anything but `0` or `1`.
  Syntax(path~ : String, at~ : Int32)
  /// What the pointer names is not there: a name no member has, or an index no
  /// array reaches.
  Missing(path~ : String, token~ : String)
  /// The pointer walked into something that is neither an object nor an array.
  NotContainer(path~ : String, token~ : String)
  /// An array index that is not one — not decimal digits without a leading
  /// zero — or `-` where it does not mean append.
  BadIndex(path~ : String, token~ : String)
  /// A test that did not hold.
  TestFailed(path~ : String)
  /// A move into one of the moved value's own children (RFC 6902 §4.4).
  IntoChild(from~ : String, path~ : String)
  /// The pointer names the root, which has no parent to take it from.
  Root(path~ : String)
} derive(Eq, Debug)

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub extend Failure with Debug::{to_repr}

///|
/// Read a patch document: the array of operations it names.
///
/// The document itself is read as strict JSON — a patch is a protocol message
/// rather than a settings file — and the dialect can still be named for a
/// caller whose patches arrive from a JSONC source.
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.strict,
) -> Array[Operation] raise Failure {
  let tree = @moonjson.loads(input, flavor) catch { e => raise Unreadable(e) }
  operations(tree)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
pub fn load(
  input : BytesView,
  flavor~ : @moonjson.Flavor = @moonjson.strict,
  bom~ : Bool = true,
) -> Array[Operation] raise Failure {
  let tree = @moonjson.load(input, flavor, bom~) catch {
    e => raise Unreadable(e)
  }
  operations(tree)
}

///|
/// Write a patch document: the operations as the array of objects RFC 6902 §4
/// prints them, `op` first and `from` before `path` where a move or a copy has
/// both.
pub fn dumps(
  ops : ArrayView[Operation],
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> String {
  @moonjson.dumps(nodes(ops), indent~, ascii~, sort~)
}

///|
/// The same, as the UTF-8 bytes a body goes out as.
pub fn dump(
  ops : ArrayView[Operation],
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(nodes(ops), indent~, ascii~, sort~)
}

///|
/// The operations as one document: an array of operation objects.
fn nodes(ops : ArrayView[Operation]) -> Json {
  let items : Array[Json] = []
  for op in ops {
    items.push(node(op))
  }
  Json::array(items)
}

///|
/// One operation as the object RFC 6902 §4 writes it. Member order follows the
/// RFC's examples, so a document read and written again comes back unchanged.
fn node(op : Operation) -> Json {
  match op {
    Add(path~, value~) =>
      Json::object({ "op": "add", "path": path, "value": value })
    Remove(path~) => Json::object({ "op": "remove", "path": path })
    Replace(path~, value~) =>
      Json::object({ "op": "replace", "path": path, "value": value })
    Move(path~, from~) =>
      Json::object({ "op": "move", "from": from, "path": path })
    Copy(path~, from~) =>
      Json::object({ "op": "copy", "from": from, "path": path })
    Test(path~, value~) =>
      Json::object({ "op": "test", "path": path, "value": value })
  }
}

///|
/// The tree a patch document names: an array of operation objects.
fn operations(tree : Json) -> Array[Operation] raise Failure {
  match tree {
    Array(items) => {
      let out : Array[Operation] = []
      for at, item in items {
        out.push(operation(at, item))
      }
      out
    }
    _ => raise Document(why="a patch document is an array of operations")
  }
}

///|
/// One element of that array, checked against the operation it names.
///
/// Members RFC 6902 §4 does not define for the operation are ignored, as it
/// says they must be — Appendix A.11 prints a patch carrying an extra `xyz`
/// and expects it applied. A required member that is missing is still an
/// error, which is what catches a misspelling.
fn operation(at : Int32, item : Json) -> Operation raise Failure {
  match item {
    Object(members) => {
      let op = match members.get("op") {
        Some(String(name)) => name
        Some(_) => raise Operation(at~, why="the \"op\" member is not a string")
        None => raise Operation(at~, why="an operation has no \"op\" member")
      }
      match op {
        "add" =>
          Add(
            path=pointer_of(at, members, "path"),
            value=field(at, members, "value"),
          )
        "remove" => Remove(path=pointer_of(at, members, "path"))
        "replace" =>
          Replace(
            path=pointer_of(at, members, "path"),
            value=field(at, members, "value"),
          )
        "move" =>
          Move(
            path=pointer_of(at, members, "path"),
            from=pointer_of(at, members, "from"),
          )
        "copy" =>
          Copy(
            path=pointer_of(at, members, "path"),
            from=pointer_of(at, members, "from"),
          )
        "test" =>
          Test(
            path=pointer_of(at, members, "path"),
            value=field(at, members, "value"),
          )
        _ => raise Operation(at~, why="\"\{op}\" is not one of the six")
      }
    }
    _ => raise Operation(at~, why="an operation is an object")
  }
}

///|
/// A member an operation requires, whatever its value.
fn field(
  at : Int32,
  members : Map[String, Json],
  name : String,
) -> Json raise Failure {
  match members.get(name) {
    Some(value) => value
    None => raise Operation(at~, why="no \"\{name}\" member")
  }
}

///|
/// A member an operation requires to hold a pointer.
fn pointer_of(
  at : Int32,
  members : Map[String, Json],
  name : String,
) -> String raise Failure {
  match field(at, members, name) {
    String(text) => text
    _ => raise Operation(at~, why="the \"\{name}\" member is not a string")
  }
}
