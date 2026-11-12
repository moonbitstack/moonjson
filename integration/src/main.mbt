// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The interoperability bench, as a command:
///
///     interop encode <format> <cases.json> <answer.json>
///     interop decode <format> <cases.json> <answer.json>
///
/// A case file is a JSON array. For `encode` it holds the documents, and the
/// answer is one string each — the text a text format writes, hexadecimal for a
/// binary one. For `decode` it holds those strings, and the answer is the tree
/// each one reads as, written as JSON, or an object naming the refusal.
///
/// Nothing here decides whether the answer is right: the reference
/// implementation of the format does, on the other side of the files.
fn main {
  let args = @env.args()
  if args.length() != 5 {
    usage()
  }
  let command = args[1]
  let format = args[2]
  let answers : Array[Json] = []
  for item in read_cases(args[3]) {
    let answer = match command {
      "encode" => run_encode(format, item)
      "decode" => run_decode(format, item)
      _ => refused("unknown command \{command}")
    }
    answers.push(answer)
  }
  write_answer(args[4], Json::array(answers))
}

///|
fn usage() -> Unit {
  println("usage: interop encode|decode <format> <cases.json> <answer.json>")
  let _ : Unit = @env.exit(2)
}

///|
fn gave_up(why : String) -> Unit {
  println(why)
  let _ : Unit = @env.exit(2)
}

///|
fn read_cases(path : String) -> Array[Json] {
  let text = @fs.read_file_to_string(path) catch {
    _ => {
      gave_up("cannot read \{path}")
      ""
    }
  }
  let document = @json.loads(text[:]) catch {
    e => {
      gave_up("\{path} is not JSON: \{e.message()}")
      Json::null()
    }
  }
  match document {
    Array(items) => items
    _ => {
      gave_up("\{path} is not an array of cases")
      []
    }
  }
}

///|
fn write_answer(path : String, answer : Json) -> Unit {
  @fs.write_string_to_file(path, @json.dumps(answer, indent=2) + "\n") catch {
    _ => gave_up("cannot write \{path}")
  }
}

///|
fn run_encode(format : String, value : Json) -> Json {
  let text = encode(format, value) catch { e => return refused(e.message()) }
  Json::string(text)
}

///|
fn run_decode(format : String, item : Json) -> Json {
  let text = match item {
    String(text) => text
    _ => return refused("a decode case is a string")
  }
  let value = decode(format, text) catch { e => return refused(e.message()) }
  Json::string(@json.dumps(value, sort=true))
}

///|
fn encode(format : String, value : Json) -> String raise @moonjson.Refused {
  match format {
    "json" => @json.dumps(value, sort=true)
    "json5" => @json5.dumps(value, sort=true)
    "hjson" => @hjson.dumps(value, sort=true)
    "cbor" => @base16.encode(@cbor.dump(value)[:])
    "msgpack" => @base16.encode(@msgpack.dump(value)[:])
    "bson" => @base16.encode(@bson.dump(value)[:])
    _ => raise @moonjson.Bad(at=0, why="no such format: \{format}")
  }
}

///|
fn decode(format : String, text : String) -> Json raise @moonjson.Refused {
  match format {
    "json" => @json.loads(text[:])
    "json5" => @json5.loads(text[:])
    "hjson" => @hjson.loads(text[:])
    _ => {
      let bytes = @base16.decode(text[:]) catch {
        _ => raise @moonjson.Bad(at=0, why="a case of \{format} is hexadecimal")
      }
      match format {
        "cbor" => @cbor.load(bytes[:])
        "msgpack" => @msgpack.load(bytes[:])
        "bson" => @bson.load(bytes[:])
        _ => raise @moonjson.Bad(at=0, why="no such format: \{format}")
      }
    }
  }
}

///|
fn refused(why : String) -> Json {
  Json::object(Map::from_array([("error", Json::string(why))]))
}
