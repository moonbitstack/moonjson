// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One member of an object, by name.
fn at(doc : Json, key : String) -> Json? {
  if doc is Object(members) {
    members.get(key)
  } else {
    None
  }
}

///|
/// The shape a service configuration is written in, which is what this reader
/// exists for.
test "a configuration file reads into the tree" {
  let src =
    #|name: greeter
    #|host: 0.0.0.0
    #|port: 12000
    #|timeout_ms: 2000
    #|debug: false
    #|log_level: info
  let got = @yaml.loads(src[:])
  assert_eq(at(got, "name"), Some(Json::string("greeter")))
  assert_eq(at(got, "port"), Some(Json::number(12000)))
  assert_eq(at(got, "debug"), Some(Json::boolean(false)))
}

///|
/// Nesting is by indentation, and a key with nothing after the colon opens the
/// block under it.
test "nesting is by indentation" {
  let src =
    #|service:
    #|  name: greeter
    #|  listen:
    #|    host: 0.0.0.0
    #|    port: 12000
    #|replicas: 3
  let got = @yaml.loads(src[:])
  let service = at(got, "service").unwrap()
  assert_eq(at(service, "name"), Some(Json::string("greeter")))
  let listen = at(service, "listen").unwrap()
  assert_eq(at(listen, "port"), Some(Json::number(12000)))
  assert_eq(at(got, "replicas"), Some(Json::number(3)))
}

///|
/// A sequence, including the `- key: value` form that carries a mapping on the
/// same line as its dash.
test "sequences, plain and carrying a mapping" {
  let src =
    #|tags:
    #|  - alpha
    #|  - beta
    #|ports:
    #|  - name: http
    #|    port: 12000
    #|  - name: metrics
    #|    port: 12001
  let got = @yaml.loads(src[:])
  let tags = at(got, "tags").unwrap()
  assert_eq(tags, Json::array([Json::string("alpha"), Json::string("beta")]))
  let ports = at(got, "ports").unwrap()
  match ports {
    Array(items) => {
      assert_eq(items.length(), 2)
      assert_eq(at(items[0], "name"), Some(Json::string("http")))
      assert_eq(at(items[1], "port"), Some(Json::number(12001)))
    }
    _ => fail("ports did not read as a sequence")
  }
}

///|
/// What a scalar denotes, and what it does not.
///
/// `1.0` is a number and `"1.0"` is a string; that difference is the reason a
/// version is quoted in every manifest that means it as text.
test "a scalar is what it looks like" {
  let src =
    #|whole: 8080
    #|fraction: 1.5
    #|negative: -3
    #|yes: true
    #|no: false
    #|nothing: null
    #|tilde: ~
    #|empty:
    #|quoted: "1.0"
    #|bare: 1.0
    #|text: hello world
    #|hashed: a#b
    #|commented: value # a comment
  let got = @yaml.loads(src[:])
  assert_eq(at(got, "whole"), Some(Json::number(8080)))
  assert_eq(at(got, "fraction"), Some(Json::number(1.5)))
  assert_eq(at(got, "negative"), Some(Json::number(-3)))
  assert_eq(at(got, "yes"), Some(Json::boolean(true)))
  assert_eq(at(got, "no"), Some(Json::boolean(false)))
  assert_eq(at(got, "nothing"), Some(Json::null()))
  assert_eq(at(got, "tilde"), Some(Json::null()))
  assert_eq(at(got, "empty"), Some(Json::null()))
  assert_eq(at(got, "quoted"), Some(Json::string("1.0")))
  assert_eq(at(got, "bare"), Some(Json::number(1.0)))
  assert_eq(at(got, "text"), Some(Json::string("hello world")))
  // A `#` glued to a word is part of it; one after a space starts a comment.
  assert_eq(at(got, "hashed"), Some(Json::string("a#b")))
  assert_eq(at(got, "commented"), Some(Json::string("value")))
}

///|
/// An error names the line in the file, not the line among the ones that
/// survived tokenising — a message a person cannot find in their file is half a
/// message.
test "an error says where it is" {
  let src =
    #|name: greeter
    #|
    #|# a comment
    #|this line is not an entry
  try @yaml.loads(src[:]) |> ignore catch {
    e => {
      let at = e.at()
      assert_eq(at.line, 4)
      assert_eq(at.column, 1)
    }
  } noraise {
    _ => fail("a line that is neither a mapping entry nor an item was accepted")
  }
}

///|
/// A key given twice is decided by the same setting the JSON dialects use, so
/// one answer covers every format here.
test "a repeated key follows the flavor" {
  let src =
    #|port: 1
    #|port: 2
  assert_eq(at(@yaml.loads(src[:]), "port"), Some(Json::number(2)))
  let first = { ..@moonjson.strict, duplicates: First, }
  assert_eq(
    at(@yaml.loads(src[:], flavor=first), "port"),
    Some(Json::number(1)),
  )
  let reject = { ..@moonjson.strict, duplicates: Reject, }
  try @yaml.loads(src[:], flavor=reject) |> ignore catch {
    e => assert_true(e is @moonjson.Repeated(_))
  } noraise {
    _ => fail("a repeated key passed under Reject")
  }
}

///|
/// The writer is the reason this package has two halves: a generator that joins
/// strings gets the quoting wrong the first time a value holds a colon.
test "what a generator would have got wrong" {
  let value = Json::object({
    "plain": Json::string("greeter"),
    "colon": Json::string("a: b"),
    "hash": Json::string("trailing # comment"),
    "looks-numeric": Json::string("1.0"),
    "looks-bool": Json::string("true"),
    "empty": Json::string(""),
    "spaced": Json::string(" padded "),
    "newline": Json::string("two\nlines"),
  })
  let text = @yaml.dumps(value, sort=true)
  // Everything that would read back as something else is quoted; the one that
  // would not, is not.
  assert_true(text.contains("plain: greeter"))
  assert_true(text.contains("colon: \"a: b\""))
  assert_true(
    text.contains("\"looks-numeric\": \"1.0\"") ||
    text.contains("looks-numeric: \"1.0\""),
  )
  assert_true(text.contains("empty: \"\""))
  assert_true(text.contains("\\n"))
  // And it reads back as what went in.
  assert_eq(@yaml.loads(text[:]), value)
}

///|
/// A document written and read again is the document that went in — the only
/// check that covers the writer and the reader at once.
test "a document round-trips" {
  let value = Json::object({
    "apiVersion": Json::string("apps/v1"),
    "kind": Json::string("Deployment"),
    "metadata": Json::object({ "name": Json::string("greeter") }),
    "spec": Json::object({
      "replicas": Json::number(3),
      "template": Json::object({
        "spec": Json::object({
          "containers": Json::array([
            Json::object({
              "name": Json::string("greeter"),
              "image": Json::string("greeter:latest"),
              "ports": Json::array([
                Json::object({ "containerPort": Json::number(12000) }),
              ]),
            }),
          ]),
        }),
      }),
    }),
  })
  assert_eq(@yaml.loads(@yaml.dumps(value)[:]), value)
  // Through bytes as well.
  assert_eq(@yaml.load(@yaml.dump(value)[:]), value)
}

///|
/// The two knobs, and nothing else — `indent` and `sort`, as `json.dumps` has
/// them.
test "the writer's two knobs" {
  let value = Json::object({
    "b": Json::number(2),
    "a": Json::object({ "y": Json::number(1) }),
  })
  // Insertion order by default, sorted when asked.
  assert_true(@yaml.dumps(value).has_prefix("b: 2"))
  assert_true(@yaml.dumps(value, sort=true).has_prefix("a:"))
  // The indent is the nesting width.
  assert_true(@yaml.dumps(value, sort=true).contains("\n  y: 1"))
  assert_true(@yaml.dumps(value, indent=4, sort=true).contains("\n    y: 1"))
  assert_eq(@yaml.indent, 2)
  // An empty collection has only the flow form to be written in.
  assert_eq(@yaml.dumps(Json::object({})), "{}\n")
  assert_eq(@yaml.dumps(Json::array([])), "[]\n")
}

///|
/// An empty document is an empty mapping, which is what every configuration
/// loader in use answers for a file with nothing in it.
test "an empty document" {
  assert_eq(@yaml.loads(""[:]), Json::object({}))
  assert_eq(@yaml.loads("# only a comment\n"[:]), Json::object({}))
  assert_eq(@yaml.loads("\n\n\n"[:]), Json::object({}))
}

///|
/// A stream of documents, which is how one file holds a Deployment and the
/// Service in front of it. The answer is an array, so the second document is
/// index one.
test "a stream of documents reads as an array" {
  let src =
    #|---
    #|kind: Deployment
    #|replicas: 3
    #|---
    #|kind: Service
    #|port: 12000
  let docs = @yaml.loads_all(src[:])
  assert_eq(docs.length(), 2)
  assert_eq(at(docs[0], "kind"), Some(Json::string("Deployment")))
  assert_eq(at(docs[1], "port"), Some(Json::number(12000)))
}

///|
/// A file with no separator in it is one document, which is why the common case
/// and the general one are the same reader.
test "a stream of one" {
  let src =
    #|kind: Service
    #|port: 12000
  let docs = @yaml.loads_all(src[:])
  assert_eq(docs.length(), 1)
  assert_eq(docs[0], @yaml.loads(src[:]))
  // Nothing at all is no documents, not one empty one.
  assert_eq(@yaml.loads_all(""[:]).length(), 0)
  // But a separator with nothing under it is a document, and an empty one.
  assert_eq(@yaml.loads_all("---\n"[:]), [Json::object({})])
}

///|
/// `...` closes a document, so what follows it is the next one.
test "a closing marker ends a document" {
  let src =
    #|kind: Deployment
    #|...
    #|---
    #|kind: Service
  let docs = @yaml.loads_all(src[:])
  assert_eq(docs.length(), 2)
  assert_eq(at(docs[0], "kind"), Some(Json::string("Deployment")))
  assert_eq(at(docs[1], "kind"), Some(Json::string("Service")))
}

///|
/// Written and read again, a stream is the stream that went in.
test "a stream round-trips" {
  let docs = [
    Json::object({
      "kind": Json::string("Deployment"),
      "replicas": Json::number(3),
    }),
    Json::object({
      "kind": Json::string("Service"),
      "port": Json::number(12000),
    }),
  ]
  let text = @yaml.dumps_all(docs[:])
  // Each document opens with its own separator, so appending one more is adding
  // lines at the end.
  assert_true(text.has_prefix("---\n"))
  assert_eq(@yaml.loads_all(text[:]), docs)
  assert_eq(@yaml.load_all(@yaml.dump_all(docs[:])[:]), docs)
}
