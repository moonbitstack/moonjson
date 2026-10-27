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
/// Read a patch document: the array of operations it names.
///
/// The document itself is read as strict JSON — a patch is a protocol message
/// rather than a settings file — and the dialect can still be named for a
/// caller whose patches arrive from a JSONC source.
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.strict,
) -> Array[Operation] raise @moonjson.Refused {
  let tree = @moonjson.loads(input, flavor)
  operations(tree)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
pub fn load(
  input : BytesView,
  flavor~ : @moonjson.Flavor = @moonjson.strict,
  bom~ : Bool = true,
) -> Array[Operation] raise @moonjson.Refused {
  let tree = @moonjson.load(input, flavor, bom~)
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
fn operations(tree : Json) -> Array[Operation] raise @moonjson.Refused {
  match tree {
    Array(items) => {
      let out : Array[Operation] = []
      for at, item in items {
        out.push(operation(at, item))
      }
      out
    }
    _ =>
      raise @moonjson.Document(why="a patch document is an array of operations")
  }
}

///|
/// One element of that array, checked against the operation it names.
///
/// Members RFC 6902 §4 does not define for the operation are ignored, as it
/// says they must be — Appendix A.11 prints a patch carrying an extra `xyz`
/// and expects it applied. A required member that is missing is still an
/// error, which is what catches a misspelling.
fn operation(at : Int32, item : Json) -> Operation raise @moonjson.Refused {
  match item {
    Object(members) => {
      let op = match members.get("op") {
        Some(String(name)) => name
        Some(_) =>
          raise @moonjson.Operation(
            at~,
            why="the \"op\" member is not a string",
          )
        None =>
          raise @moonjson.Operation(
            at~,
            why="an operation has no \"op\" member",
          )
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
        _ =>
          raise @moonjson.Operation(at~, why="\"\{op}\" is not one of the six")
      }
    }
    _ => raise @moonjson.Operation(at~, why="an operation is an object")
  }
}

///|
/// A member an operation requires, whatever its value.
fn field(
  at : Int32,
  members : Map[String, Json],
  name : String,
) -> Json raise @moonjson.Refused {
  match members.get(name) {
    Some(value) => value
    None => raise @moonjson.Operation(at~, why="no \"\{name}\" member")
  }
}

///|
/// A member an operation requires to hold a pointer.
fn pointer_of(
  at : Int32,
  members : Map[String, Json],
  name : String,
) -> String raise @moonjson.Refused {
  match field(at, members, name) {
    String(text) => text
    _ =>
      raise @moonjson.Operation(
        at~,
        why="the \"\{name}\" member is not a string",
      )
  }
}
