// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a dialect permits beyond RFC 8259.
///
/// The dialects in this family differ only in their syntax — the tree they
/// produce is the same — so the scanner is written once and each dialect is a
/// set of switches. A dialect outside this repository can be described the same
/// way without forking anything.
pub(all) struct Flavor {
  /// `//` to end of line, and `/* … */`.
  comments : Bool
  /// A comma before the closing brace or bracket.
  trailing_commas : Bool
  /// A member name written as an identifier rather than a string.
  unquoted_keys : Bool
  /// `'like this'` as well as `"like this"`.
  single_quotes : Bool
  /// `+1`, `.5`, `5.`, `0xFF`, `Infinity`, `-Infinity`, `NaN`.
  extra_numbers : Bool
  /// `\x41`, `\0`, `\v`, a backslash before a newline, and a backslash before
  /// anything else standing for that character.
  extra_escapes : Bool
  /// The whitespace ECMAScript recognises, not only the four RFC 8259 allows.
  extra_space : Bool
} derive(Eq, Debug)

///|
pub extend Flavor with Eq::{equal, not_equal}

///|
pub extend Flavor with Debug::{to_repr}

///|
/// RFC 8259 and nothing more.
pub let strict : Flavor = {
  comments: false,
  trailing_commas: false,
  unquoted_keys: false,
  single_quotes: false,
  extra_numbers: false,
  extra_escapes: false,
  extra_space: false,
}

///|
/// JSON with comments and trailing commas — what editors and their
/// configuration files have settled on, `tsconfig.json` being the best-known.
pub let commented : Flavor = {
  ..strict,
  comments: true,
  trailing_commas: true,
}

///|
/// JSON5: everything ECMAScript 5 would have accepted.
pub let relaxed : Flavor = {
  comments: true,
  trailing_commas: true,
  unquoted_keys: true,
  single_quotes: true,
  extra_numbers: true,
  extra_escapes: true,
  extra_space: true,
}
