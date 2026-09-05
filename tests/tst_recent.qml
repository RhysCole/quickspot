import QtQuick
import QtTest

import "../Recent.js" as Recent

TestCase {
  name: "Recent"

  function test_insertPutsNewestFirst() {
    var list = Recent.insert([], "one", 10)
    list = Recent.insert(list, "two", 10)
    compare(list.length, 2)
    compare(list[0], "two")
    compare(list[1], "one")
  }

  function test_insertMovesRepeatedQueryToFrontWithoutDuplicating() {
    var list = Recent.insert(Recent.insert(Recent.insert([], "a", 10), "b", 10), "a", 10)
    compare(list.length, 2)
    compare(list[0], "a")
    compare(list[1], "b")
  }

  function test_insertTrimsWhitespaceAndIgnoresEmpty() {
    compare(Recent.insert([], "  spaced  ", 10)[0], "spaced")
    compare(Recent.insert([], "   ", 10).length, 0)
    compare(Recent.insert([], "", 10).length, 0)
  }

  function test_insertRespectsCap() {
    var list = []
    for (var i = 0; i < 15; i++) list = Recent.insert(list, "q" + i, 10)
    compare(list.length, 10)
    compare(list[0], "q14")
    compare(list[9], "q5")
  }

  function test_insertRespectsCapAtBoundaryValues() {
    var listCap1 = Recent.insert(["a", "b", "c"], "x", 1)
    compare(listCap1.length, 1)
    compare(listCap1[0], "x")

    var listCap2 = Recent.insert(["a", "b", "c"], "x", 2)
    compare(listCap2.length, 2)
    compare(listCap2[0], "x")
    compare(listCap2[1], "a")
  }

  function test_insertTreatsDifferentCaseAsDifferentQueries() {
    var list = Recent.insert(Recent.insert([], "M83", 10), "m83", 10)
    compare(list.length, 2)
  }

  function test_sanitizeAcceptsWellFormedJson() {
    compare(Recent.sanitize(JSON.stringify(["a", "b"])).length, 2)
  }

  function test_sanitizeDropsNonStringsAndGarbage() {
    compare(Recent.sanitize(JSON.stringify(["a", 3, null, "b"])).length, 2)
    compare(Recent.sanitize("not json").length, 0)
    compare(Recent.sanitize("").length, 0)
    compare(Recent.sanitize(JSON.stringify({ not: "a list" })).length, 0)
  }

  function test_sanitizeEnforcesCap() {
    var many = []
    for (var i = 0; i < 40; i++) many.push("q" + i)
    compare(Recent.sanitize(JSON.stringify(many)).length, Recent.CAP)
  }

  function test_serializeRoundTrips() {
    compare(Recent.sanitize(Recent.serialize(["a", "b"])).length, 2)
  }
}
