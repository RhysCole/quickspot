import QtQuick
import QtTest

import "../Api.js" as Api

TestCase {
  name: "Api"

  function test_searchUrlEncodesQueryAndLimitsType() {
    var url = Api.searchUrl("m83 midnight & city", 10)
    verify(url.indexOf("https://api.spotify.com/v1/search?") === 0)
    verify(url.indexOf("type=track%2Calbum%2Cplaylist") !== -1
           || url.indexOf("type=track,album,playlist") !== -1)
    verify(url.indexOf("limit=10") !== -1)
    verify(url.indexOf("q=m83%20midnight%20%26%20city") !== -1)
  }

  function test_queueListUrlIsTheReadEndpoint() {
    compare(Api.queueListUrl(), "https://api.spotify.com/v1/me/player/queue")
  }

  function test_playerUrl() {
    compare(Api.playerUrl(), "https://api.spotify.com/v1/me/player")
  }

  function test_transportUrlAppendsDeviceOnlyWhenKnown() {
    compare(Api.transportUrl("next", "", ""), "https://api.spotify.com/v1/me/player/next")
    compare(Api.transportUrl("pause", "dev 1", ""),
            "https://api.spotify.com/v1/me/player/pause?device_id=dev%201")
  }

  function test_seekUrlRoundsAndClampsPosition() {
    compare(Api.seekUrl(1234.6, ""), "https://api.spotify.com/v1/me/player/seek?position_ms=1235")
    compare(Api.seekUrl(-10, ""), "https://api.spotify.com/v1/me/player/seek?position_ms=0")
    compare(Api.seekUrl(5000, "dev-1"),
            "https://api.spotify.com/v1/me/player/seek?position_ms=5000&device_id=dev-1")
  }

  function test_searchUrlClampsLimit() {
    verify(Api.searchUrl("x", 0).indexOf("limit=1") !== -1)
    verify(Api.searchUrl("x", 999).indexOf("limit=10") !== -1)
    // 11 is the first value the live API rejects with 400 "Invalid limit".
    verify(Api.searchUrl("x", 11).indexOf("limit=10") !== -1)
  }

  function test_playUrlOmitsDeviceWhenUnknown() {
    compare(Api.playUrl(""), "https://api.spotify.com/v1/me/player/play")
    compare(Api.playUrl("dev1"), "https://api.spotify.com/v1/me/player/play?device_id=dev1")
  }

  function test_queueUrlEncodesUri() {
    var url = Api.queueUrl("spotify:track:abc", "dev1")
    verify(url.indexOf("uri=spotify%3Atrack%3Aabc") !== -1)
    verify(url.indexOf("device_id=dev1") !== -1)
  }

  function test_playTrackBodyUsesUrisArray() {
    var body = JSON.parse(Api.playTrackBody("spotify:track:abc"))
    compare(body.uris.length, 1)
    compare(body.uris[0], "spotify:track:abc")
  }

  function test_playContextBodyOmitsTheOffsetWhenThereIsNone() {
    var whole = JSON.parse(Api.playContextBody("spotify:playlist:p1", ""))
    compare(whole.context_uri, "spotify:playlist:p1")
    verify(whole.offset === undefined)
  }

  function test_playContextBodyUsesContextAndOffset() {
    var body = JSON.parse(Api.playContextBody("spotify:album:xyz", "spotify:track:abc"))
    compare(body.context_uri, "spotify:album:xyz")
    compare(body.offset.uri, "spotify:track:abc")
  }

  function test_classifyErrorMapsStatuses() {
    compare(Api.classifyError(401, "").kind, "unauthorized")
    compare(Api.classifyError(403, "").kind, "forbidden")
    compare(Api.classifyError(404, "").kind, "noDevice")
    compare(Api.classifyError(429, "").kind, "rateLimited")
    compare(Api.classifyError(0, "").kind, "network")
    compare(Api.classifyError(500, "").kind, "unknown")
  }

  function test_classifyErrorForbiddenMentionsPremium() {
    verify(Api.classifyError(403, "").message.toLowerCase().indexOf("premium") !== -1)
  }

  function test_classifyErrorPrefersSpotifyMessage() {
    var body = JSON.stringify({ error: { status: 500, message: "Service unavailable" } })
    compare(Api.classifyError(500, body).message, "Service unavailable")
  }

  function test_retryAfterMsParsesSecondsAndDefaults() {
    compare(Api.retryAfterMs("3"), 3000)
    compare(Api.retryAfterMs(""), 1000)
    compare(Api.retryAfterMs("nonsense"), 1000)
  }

  function test_activeDeviceIdPicksActiveDevice() {
    var payload = JSON.stringify({ devices: [
      { id: "a", is_active: false },
      { id: "b", is_active: true }
    ]})
    compare(Api.activeDeviceId(payload), "b")
  }

  function test_activeDeviceIdReturnsEmptyWhenNoneActive() {
    compare(Api.activeDeviceId(JSON.stringify({ devices: [{ id: "a", is_active: false }] })), "")
    compare(Api.activeDeviceId(JSON.stringify({ devices: [] })), "")
    compare(Api.activeDeviceId("garbage"), "")
  }
}
