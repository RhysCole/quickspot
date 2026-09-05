import QtQuick
import QtTest

TestCase {
  name: "Harness"

  function test_runnerExecutes() {
    compare(1 + 1, 2)
  }
}
