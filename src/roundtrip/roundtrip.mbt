// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A tree that exercises every JSON kind — object, array, string, number,
/// boolean and null, nested — for the cross-format round-trip test.
pub fn sample() -> Json {
  Json::object(
    Map::from_array([
      ("name", Json::string("moonjson")),
      ("version", Json::number(0.4)),
      ("stable", Json::boolean(true)),
      ("tail", Json::null()),
      ("tags", Json::array([Json::string("json"), Json::string("moonbit")])),
      (
        "nested",
        Json::object(
          Map::from_array([
            ("port", Json::number(8080.0)),
            ("delta", Json::number(-7.0)),
            ("hosts", Json::array([Json::string("a"), Json::string("b")])),
          ]),
        ),
      ),
    ]),
  )
}
