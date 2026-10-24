// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where something went wrong in a document that arrived as text.
///
/// The offset is in UTF-16 code units from the start, which is what a
/// [`StringView`] indexes by; line and column are one-based, because that is
/// how every editor counts and an error a person cannot find in their file is
/// half an error.
pub(all) struct At {
  at : Int32
  line : Int32
  column : Int32
} derive(Eq, Debug)

///|
pub extend At with Eq::{equal, not_equal}

///|
pub extend At with Debug::{to_repr}

///|
/// Why a document was refused, and where.
///
/// One error type for the whole family — reading text, reading bytes, walking
/// a pointer, applying a patch, writing a value a format cannot carry — so that
/// a caller has one thing to catch and one place to look. A variant that has a
/// position carries the [`At`] it was found at; a variant about a pointer or a
/// patch names the pointer itself, because a `move` and a `copy` each carry two
/// and an error that did not say which one would be half an error.
pub(all) suberror Refused {
  // Reading text.
  /// A character that cannot start or continue what is being read.
  Unexpected(At, Char)
  /// The document ends inside a value.
  Truncated(At)
  /// An escape sequence that is not one, or a lone half of a surrogate pair.
  BadEscape(At)
  /// A number the grammar does not admit — a leading zero, a bare minus, an
  /// exponent with no digits.
  BadNumber(At)
  /// A second value after the first one ended.
  Trailing(At)
  /// Nesting past the depth limit. Without this, a document of ten thousand
  /// open brackets would take the stack down with it.
  TooDeep(At)
  /// Bytes that are not UTF-8, when reading a document that arrived as bytes.
  BadUtf8(At)
  /// A member name that appears twice, when the dialect refuses that.
  Repeated(At, String)
  // Writing.
  /// A value the format has no way to write: a number that is not finite into
  /// JSON, a byte string into a text dialect, a key that is not a string into
  /// one whose objects have only string keys.
  Unwritable(why~ : String)
  // Pointers (RFC 6901).
  /// The pointer is not one: it does not start with a slash, or a `~` is
  /// followed by anything but `0` or `1`. `at` is the offset within `path`.
  Syntax(path~ : String, at~ : Int32)
  /// What the pointer names is not there: a name no member has, or an index no
  /// array reaches.
  Missing(path~ : String, token~ : String)
  /// The pointer walked into something that is neither an object nor an array.
  NotContainer(path~ : String, token~ : String)
  /// An array index that is not one — not decimal digits without a leading
  /// zero — or `-` where it does not mean append.
  BadIndex(path~ : String, token~ : String)
  // Patches (RFC 6902).
  /// The document is JSON but not a patch: not an array of operations.
  Document(why~ : String)
  /// The operation at `at` is not one: no `op` member, an `op` that is not one
  /// of the six, or a member it requires missing or of the wrong type.
  Operation(at~ : Int32, why~ : String)
  /// A `test` that did not hold.
  TestFailed(path~ : String)
  /// A move into one of the moved value's own children (RFC 6902 §4.4).
  IntoChild(from~ : String, path~ : String)
  /// The operation names the root, which has no parent to take it from.
  Root(path~ : String)
} derive(Eq, Debug)

///|
pub extend Refused with Eq::{equal, not_equal}

///|
pub extend Refused with Debug::{to_repr}

///|
/// Where the failure happened, when it happened in text.
///
/// `None` is not a failure to say: a pointer or a patch that was refused has a
/// path rather than a line, and a line number invented for it would be worse
/// than no line number at all.
pub fn Refused::at(self : Refused) -> At? {
  match self {
    Unexpected(spot, _) => Some(spot)
    Truncated(spot)
    | BadEscape(spot)
    | BadNumber(spot)
    | Trailing(spot)
    | TooDeep(spot)
    | BadUtf8(spot) => Some(spot)
    Repeated(spot, _) => Some(spot)
    Unwritable(_)
    | Syntax(..)
    | Missing(..)
    | NotContainer(..)
    | BadIndex(..)
    | Document(..)
    | Operation(..)
    | TestFailed(..)
    | IntoChild(..)
    | Root(..) => None
  }
}
