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
  /// The offset in UTF-16 code units from the start of the document, which is
  /// what a [`StringView`] indexes by.
  at : Int32
  /// The line the offset is on, counting from one.
  line : Int32
  /// The column the offset is at, counting from one.
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
  // Binary formats, where there is no text and so no line to name: `at` is the
  // byte offset from the start of the document.
  /// The document ended inside a value.
  Short(at~ : Int32)
  /// Something after the value ended. A document is one value, and a reader
  /// that stops at the first turns a corrupt file into a plausible one.
  Extra(at~ : Int32)
  /// A byte that cannot be read this way: a reserved additional-information
  /// value, a length or an index that does not fit, a string that is not UTF-8,
  /// a nesting that went too deep.
  Bad(at~ : Int32, why~ : String)
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
    Short(_)
    | Extra(_)
    | Bad(..)
    | Unwritable(_)
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

///|
/// The failure as one sentence a person can read: what went wrong, and where.
///
/// A text dialect names the line and column, counting from one, because that is
/// how an editor counts; a binary format names the byte offset, because that is
/// all a file without lines has to offer. The sentence is lower case and carries
/// no full stop, so a caller can put it after its own word — `"refused: " +
/// error.message()` — without the punctuation fighting.
pub fn Refused::message(self : Refused) -> String {
  match self {
    Unexpected(spot, c) => spot_text(spot) + "unexpected " + char_text(c)
    Truncated(spot) => spot_text(spot) + "the document ends inside a value"
    BadEscape(spot) => spot_text(spot) + "not an escape sequence"
    BadNumber(spot) => spot_text(spot) + "not a number"
    Trailing(spot) =>
      spot_text(spot) +
      "a second value follows the first, and a document is one value"
    TooDeep(spot) => spot_text(spot) + "the nesting is too deep"
    BadUtf8(spot) => spot_text(spot) + "these bytes are not UTF-8"
    Repeated(spot, name) =>
      spot_text(spot) + "the member " + quoted(name) + " appears twice"
    Short(at~) =>
      "byte " + at.to_string() + ": the document ends inside a value"
    Extra(at~) => "byte " + at.to_string() + ": something follows the value"
    Bad(at~, why~) => "byte " + at.to_string() + ": " + why
    Unwritable(why~) => "this value cannot be written: " + why
    Syntax(path~, at~) =>
      "the pointer " +
      quoted(path) +
      " is not a pointer, at offset " +
      at.to_string()
    Missing(path~, token~) =>
      "the pointer " + quoted(path) + " names no " + quoted(token)
    NotContainer(path~, token~) =>
      quoted(token) +
      " is neither an object nor an array, on the way to " +
      quoted(path)
    BadIndex(path~, token~) =>
      quoted(token) + " is not an index, on the way to " + quoted(path)
    Document(why~) => "not a patch: " + why
    Operation(at~, why~) => "operation " + at.to_string() + ": " + why
    TestFailed(path~) => "the test at " + quoted(path) + " did not hold"
    IntoChild(from~, path~) =>
      "cannot move " + quoted(from) + " into its own child " + quoted(path)
    Root(path~) => quoted(path) + " is the root, and has no parent"
  }
}

///|
/// `line 3, column 8: ` — the prefix every textual message opens with.
fn spot_text(spot : At) -> String {
  "line " + spot.line.to_string() + ", column " + spot.column.to_string() + ": "
}

///|
/// A character as it would be written in a document, so a message can say
/// `unexpected ']'` rather than `unexpected U+005D`.
fn char_text(c : Char) -> String {
  let code = c.to_int()
  if code == 0x27 {
    "'\\''"
  } else if code == 0x5C {
    "'\\\\'"
  } else if code >= 0x20 && code < 0x7F {
    "'" + c.to_string() + "'"
  } else if code == 0x0A {
    "'\\n'"
  } else if code == 0x0D {
    "'\\r'"
  } else if code == 0x09 {
    "'\\t'"
  } else {
    let digits = "0123456789ABCDEF"
    let mut text = "U+"
    let mut shift = 12
    while shift >= 0 {
      text = text + digits[(code >> shift) & 0xF].unsafe_to_char().to_string()
      shift -= 4
    }
    text
  }
}

///|
/// A name or a path, in the quotes a document would give it, with the two
/// characters that would end those quotes escaped.
fn quoted(text : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  let view = text[:]
  for i = 0; i < view.length(); i = i + 1 {
    let code = view.at(i).to_int()
    if code == 0x22 || code == 0x5C {
      out.write_char('\\')
    }
    out.write_char(code.unsafe_to_char())
  }
  out.write_char('"')
  out.to_string()
}
