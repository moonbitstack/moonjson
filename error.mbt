// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where something went wrong.
///
/// The offset is in UTF-16 code units from the start, which is what a
/// [`StringView`] indexes by; line and column are one-based, because that is
/// how every editor counts and an error a person cannot find in their file is
/// half an error.
pub(all) struct At {
  at : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
pub extend At with Eq::{equal, not_equal}

///|
pub extend At with Debug::{to_repr}

///|
/// Why a document could not be read, and where.
pub(all) suberror Malformed {
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
} derive(Eq, Debug)

///|
pub extend Malformed with Eq::{equal, not_equal}

///|
pub extend Malformed with Debug::{to_repr}

///|
/// Where an error happened, as a person would say it.
pub fn Malformed::at(self : Malformed) -> At {
  match self {
    Unexpected(spot, _) => spot
    Truncated(spot)
    | BadEscape(spot)
    | BadNumber(spot)
    | Trailing(spot)
    | TooDeep(spot)
    | BadUtf8(spot) => spot
  }
}

///|
/// How deep the nesting may go.
///
/// Five hundred is past anything a document written for a reader contains and
/// far short of what exhausts a stack on any backend. JSONTestSuite's
/// hundred-thousand-bracket cases are meant to be refused, not survived.
pub let depth_limit : Int = 500
