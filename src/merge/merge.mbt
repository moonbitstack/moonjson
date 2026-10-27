// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Apply a merge patch to a document, and answer the document that results.
///
/// A merge patch looks like the document it changes rather than like a list of
/// instructions: a member that is not there is added, one that is there is
/// replaced, and a member whose value is `null` is taken away — a `null` in
/// the patch is an instruction, while a `null` already in the target is data
/// and stays. A patch that is not an object replaces the whole document,
/// `null` itself among them, and a target that is not an object is ignored
/// and started again from an empty one.
///
/// It answers a new document rather than changing the one it was given, for
/// the same reason [`@pointer.set`] does: a tree is shared, and a value
/// reached through two pointers is one value.
///
/// ```moonbit nocheck
/// let cfg = @json.loads("{\"host\":\"localhost\",\"port\":8080,\"tls\":false}")
/// @merge.merge(cfg, @json.loads("{\"port\":9090,\"tls\":null}"))
/// // {"host":"localhost","port":9090}
/// ```
pub fn merge(target : Json, patch : Json) -> Json {
  match patch {
    Object(want) => {
      let out : Map[String, Json] = Map([])
      match target {
        Object(have) =>
          for name, held in have {
            out[name] = held
          }
        _ => ()
      }
      for name, value in want {
        if value is Null {
          out.remove(name)
        } else {
          out[name] = merge(out.get(name).unwrap_or(Json::null()), value)
        }
      }
      Json::object(out)
    }
    _ => patch
  }
}
