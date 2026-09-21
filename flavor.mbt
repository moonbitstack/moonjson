// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a repeated member name means.
///
/// Every mainstream implementation keeps the last one — JavaScript, Python, Go
/// and serde all do — so that is the default. The other two are here because a
/// document with two `"id"` members is usually a mistake, and a reader that
/// wants to hear about it should not have to write its own parser.
pub(all) enum Duplicates {
  /// The last one wins. What everybody does.
  Last
  /// The first one wins.
  First
  /// A repeated name is an error.
  Reject
} derive(Eq, Debug)

///|
pub extend Duplicates with Eq::{equal, not_equal}

///|
pub extend Duplicates with Debug::{to_repr}

///|
/// How to read a document: what syntax to accept, and what to do at the edges.
///
/// The dialects in this family differ only in their syntax — the tree they
/// produce is the same — so the scanner is written once and each dialect is a
/// set of switches. A dialect outside this repository can be described the same
/// way without forking anything.
///
/// The last three fields are not syntax but policy. They are here rather than
/// as arguments because they are set once for a deployment and because this
/// family has sixteen entry points: a policy added here costs one line, and a
/// policy added to every signature costs sixteen.
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
  /// How deep the nesting may go before the document is refused.
  ///
  /// Five hundred is past anything written for a reader and far short of what
  /// exhausts a stack on any backend. The mainstream disagrees on the number —
  /// Jackson refuses past 1000, serde_json past 128 — but not on having one,
  /// because a document of a hundred thousand open brackets is a denial of
  /// service rather than a document.
  depth : Int
  /// Whether a lone half of a surrogate pair is a character.
  ///
  /// Implementations disagree: JavaScript keeps it, Go replaces it, serde_json
  /// refuses it, and JSONTestSuite files these cases as implementation-defined.
  /// The default refuses, because a lone half cannot be written back out and
  /// every value that could replace it is a guess about what the writer meant.
  surrogates : Bool
  /// What a repeated member name means.
  duplicates : Duplicates
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
  depth: 500,
  surrogates: false,
  duplicates: Last,
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
  depth: 500,
  surrogates: false,
  duplicates: Last,
}

///|
/// Build a dialect by naming the parts that differ from strict JSON.
///
/// The same thing can be written `{ ..@moonjson.strict, depth: 100 }`; this
/// form exists because a named argument reads better when several parts differ.
pub fn Flavor::new(
  comments? : Bool = strict.comments,
  trailing_commas? : Bool = strict.trailing_commas,
  unquoted_keys? : Bool = strict.unquoted_keys,
  single_quotes? : Bool = strict.single_quotes,
  extra_numbers? : Bool = strict.extra_numbers,
  extra_escapes? : Bool = strict.extra_escapes,
  extra_space? : Bool = strict.extra_space,
  depth? : Int = strict.depth,
  surrogates? : Bool = strict.surrogates,
  duplicates? : Duplicates = strict.duplicates,
) -> Flavor {
  {
    comments,
    trailing_commas,
    unquoted_keys,
    single_quotes,
    extra_numbers,
    extra_escapes,
    extra_space,
    depth,
    surrogates,
    duplicates,
  }
}
