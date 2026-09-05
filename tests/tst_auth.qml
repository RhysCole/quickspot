import QtQuick
import QtTest

import "../Auth.js" as Auth

TestCase {
  name: "Auth"

  function test_parsePkceOutputAcceptsWellFormedLine() {
    var verifier = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"
    var challenge = "GFEDCBA9876543210zyxwvutsrqponmlkjihgfedcba"
    var raw = verifier + " " + challenge + " state-token"
    var result = Auth.parsePkceOutput(raw)
    verify(result.ok)
    compare(result.verifier, verifier)
    compare(result.challenge, challenge)
    compare(result.state, "state-token")
  }

  function test_parsePkceOutputRejectsShortVerifier() {
    var result = Auth.parsePkceOutput("tooshort challenge state")
    verify(!result.ok)
    verify(result.error.length > 0)
  }

  function test_parsePkceOutputRejectsMissingFields() {
    verify(!Auth.parsePkceOutput("only-one-field").ok)
    verify(!Auth.parsePkceOutput("").ok)
  }

  function test_normalizedPortClampsOutOfRange() {
    compare(Auth.normalizedPort(8788), 8788)
    compare(Auth.normalizedPort(80), Auth.DEFAULT_PORT)
    compare(Auth.normalizedPort(70000), Auth.DEFAULT_PORT)
    compare(Auth.normalizedPort("not a number"), Auth.DEFAULT_PORT)
  }

  function test_authorizeUrlEncodesEveryParameter() {
    var url = Auth.authorizeUrl("client 1", "http://127.0.0.1:8788/callback", "chal+lenge", "st/ate")
    verify(url.indexOf("https://accounts.spotify.com/authorize?") === 0)
    verify(url.indexOf("client_id=client%201") !== -1)
    verify(url.indexOf("redirect_uri=http%3A%2F%2F127.0.0.1%3A8788%2Fcallback") !== -1)
    verify(url.indexOf("code_challenge=chal%2Blenge") !== -1)
    verify(url.indexOf("code_challenge_method=S256") !== -1)
    verify(url.indexOf("state=st%2Fate") !== -1)
    verify(url.indexOf("response_type=code") !== -1)
    verify(url.indexOf("user-modify-playback-state") !== -1)
  }

  function test_parseCallbackRequestLineExtractsCodeAndState() {
    var result = Auth.parseCallbackRequestLine(
      "GET /callback?code=abc%2Bdef&state=xyz HTTP/1.1")
    verify(result.ok)
    compare(result.code, "abc+def")
    compare(result.state, "xyz")
  }

  function test_parseCallbackRequestLineReportsSpotifyDenial() {
    var result = Auth.parseCallbackRequestLine(
      "GET /callback?error=access_denied&state=xyz HTTP/1.1")
    verify(!result.ok)
    compare(result.error, "access_denied")
  }

  function test_parseCallbackRequestLineIgnoresUnrelatedLines() {
    verify(!Auth.parseCallbackRequestLine("Host: 127.0.0.1:8788").ok)
    verify(!Auth.parseCallbackRequestLine("").ok)
  }

  function test_parseTokenResponseComputesAbsoluteExpiry() {
    var body = JSON.stringify({
      access_token: "at-1",
      refresh_token: "rt-1",
      expires_in: 3600
    })
    var result = Auth.parseTokenResponse(body, 1000000)
    verify(result.ok)
    compare(result.accessToken, "at-1")
    compare(result.refreshToken, "rt-1")
    compare(result.expiresAt, 1000000 + 3600 * 1000)
  }

  function test_parseTokenResponseKeepsEmptyRefreshTokenWhenAbsent() {
    var body = JSON.stringify({ access_token: "at-2", expires_in: 60 })
    var result = Auth.parseTokenResponse(body, 0)
    verify(result.ok)
    compare(result.refreshToken, "")
  }

  function test_parseTokenResponseRejectsErrorPayload() {
    var body = JSON.stringify({ error: "invalid_grant" })
    var result = Auth.parseTokenResponse(body, 0)
    verify(!result.ok)
    compare(result.error, "invalid_grant")
  }

  function test_parseTokenResponseRejectsGarbage() {
    verify(!Auth.parseTokenResponse("<html>nope</html>", 0).ok)
  }
}
