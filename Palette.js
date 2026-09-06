.pragma library

// How many blobs the lava background draws, and therefore how many colours it
// needs. The quantizer usually returns more; anything beyond this is unused.
var BLOB_COUNT = 4

// djb2. Only has to be stable and collision-resistant enough to name a cache
// file — artwork URLs already differ by album id.
function cacheKey(url) {
  var text = String(url || "")
  var hash = 5381
  for (var i = 0; i < text.length; i++)
    hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0
  return hash.toString(16)
}

function cachePath(cacheDir, url) {
  if (!url) return ""
  return String(cacheDir) + "/" + cacheKey(url)
}

// ColorQuantizer reads a local file, so the artwork is fetched first. `-f`
// makes curl fail on an HTTP error instead of writing the error body as if it
// were an image; `-s` keeps the shell's journal quiet.
function downloadCommand(url, path) {
  return ["sh", "-c",
          'mkdir -p "$(dirname "$2")" && [ -s "$2" ] || curl -sfL --max-time 10 -o "$2" "$1"',
          "sh", String(url), String(path)]
}

// Very dark and very washed-out colours make a background that either reads as
// a smudge or blows out the text on top of it, so they are dropped before the
// palette is padded back up to length.
function usable(color) {
  if (!color) return false
  var luminance = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
  if (luminance < 0.06 || luminance > 0.95) return false
  var max = Math.max(color.r, color.g, color.b)
  var min = Math.min(color.r, color.g, color.b)
  return (max - min) > 0.05
}

// Always returns exactly `count` colours: filters the quantizer's output, then
// cycles what survives. An album that quantizes to nothing usable (a pure
// greyscale sleeve) falls back to the theme entirely.
function build(quantized, fallback, count) {
  var total = Math.max(1, Number(count) || BLOB_COUNT)
  var kept = []
  var source = quantized || []
  for (var i = 0; i < source.length; i++)
    if (usable(source[i])) kept.push(source[i])

  if (kept.length === 0) kept = (fallback || []).slice()
  if (kept.length === 0) return []

  var out = []
  for (var j = 0; j < total; j++) out.push(kept[j % kept.length])
  return out
}

// --- readability -------------------------------------------------------

// WCAG relative luminance, so contrast is judged the way a person perceives it
// rather than by raw channel distance.
function relativeLuminance(color) {
  function channel(value) {
    return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
}

function contrastRatio(a, b) {
  var la = relativeLuminance(a)
  var lb = relativeLuminance(b)
  var high = Math.max(la, lb)
  var low = Math.min(la, lb)
  return (high + 0.05) / (low + 0.05)
}

// Pushes a colour away from the background in lightness until it is legible,
// keeping its hue so the result still reads as belonging to the album.
function ensureContrast(color, background, minRatio, steps) {
  var limit = Math.max(1, Number(steps) || 12)
  var lighten = relativeLuminance(color) >= relativeLuminance(background)
  var lightness = color.hslLightness
  var current = color

  for (var i = 0; i < limit; i++) {
    if (contrastRatio(current, background) >= minRatio) return current
    lightness = lighten ? Math.min(1, lightness + 0.06) : Math.max(0, lightness - 0.06)
    current = Qt.hsla(color.hslHue, color.hslSaturation, lightness, color.a)
  }
  return current
}

// The album colour used for text and controls: whichever candidate already
// stands out most against the card, then nudged until it is actually readable.
// Falls back to the theme when the album offers nothing to work with.
function readable(colors, background, fallback, minRatio) {
  var target = Number(minRatio) || 4.5
  var source = colors || []
  var best = null
  var bestRatio = 0

  for (var i = 0; i < source.length; i++) {
    var ratio = contrastRatio(source[i], background)
    if (ratio > bestRatio) { bestRatio = ratio; best = source[i] }
  }
  if (best === null) return fallback

  var adjusted = ensureContrast(best, background, target, 12)
  // A hue that cannot be made legible without turning into near-white or
  // near-black is worse than the theme's own accent.
  return contrastRatio(adjusted, background) >= target ? adjusted : fallback
}
