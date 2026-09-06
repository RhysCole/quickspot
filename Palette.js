.pragma library

// How many blobs the lava background draws, and therefore how many colours it
// needs. The quantizer usually returns more; anything beyond this is unused.
var BLOB_COUNT = 4

// Ceiling on how bright a blob may get. The text on top is sized for contrast
// against the card, not against a blob that drifted underneath it, so a pale
// sleeve — or the near-white a monochrome one produces — could wash a word out
// as it passed. Capping luminance keeps the field dark enough to read over
// without draining the hue that makes it recognisable.
var MAX_BLOB_LUMINANCE = 0.34

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
  // Written fresh every time rather than reused when the file already exists:
  // a cache hit and a stale entry from an earlier track look identical from
  // here, and getting it wrong shows up as the previous album's colours.
  return ["sh", "-c",
          'mkdir -p "$(dirname "$2")" && curl -sfL --max-time 10 -o "$2" "$1"',
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

// What a sleeve that is essentially black or greyscale gets instead. Falling
// back to the theme there was wrong: a black cover would come up in whatever
// hue the theme happens to use, so a monochrome album looked green or yellow
// for no reason a person could see. Near-white reads as deliberate.
function monochromePalette() {
  return [Qt.rgba(1, 1, 1, 1),
          Qt.rgba(0.88, 0.89, 0.92, 1),
          Qt.rgba(0.72, 0.74, 0.80, 1)]
}

// Always returns exactly `count` colours: filters the quantizer's output, then
// cycles what survives. Nothing usable but something quantized means a
// monochrome sleeve, which is different from having no artwork at all — the
// first gets white, the second gets the theme.
function build(quantized, fallback, count) {
  var total = Math.max(1, Number(count) || BLOB_COUNT)
  var kept = []
  var source = quantized || []
  for (var i = 0; i < source.length; i++)
    if (usable(source[i])) kept.push(source[i])

  if (kept.length === 0)
    kept = source.length > 0 ? monochromePalette() : (fallback || []).slice()
  if (kept.length === 0) return []

  var out = []
  for (var j = 0; j < total; j++)
    out.push(capBrightness(kept[j % kept.length], MAX_BLOB_LUMINANCE))
  return out
}

// Darkens a colour until it sits under a luminance ceiling, holding hue and
// saturation so it still reads as the album's. A colour already below the
// ceiling is returned untouched.
function capBrightness(color, maxLuminance) {
  var ceiling = Number(maxLuminance)
  if (isNaN(ceiling)) ceiling = MAX_BLOB_LUMINANCE
  if (relativeLuminance(color) <= ceiling) return color

  var lightness = color.hslLightness
  var current = color
  for (var i = 0; i < 24 && lightness > 0; i++) {
    lightness = Math.max(0, lightness - 0.04)
    current = Qt.hsla(color.hslHue, color.hslSaturation, lightness, color.a)
    if (relativeLuminance(current) <= ceiling) return current
  }
  return current
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

  // Ordered by saturation, not by contrast. On a dark card the highest-contrast
  // swatch is whichever is palest, and a washed-out cream reads as "some light
  // colour" rather than as this album — the saturated one is what a person
  // recognises. Contrast is then fixed by lifting lightness, which the pale
  // candidate would not have needed but also would not have communicated.
  var candidates = []
  for (var i = 0; i < source.length; i++)
    if (usable(source[i])) candidates.push(source[i])
  // Same split as build(): a monochrome sleeve gets white text, and only a
  // sleeve we have no colours for at all falls through to the theme.
  if (candidates.length === 0)
    return source.length > 0 ? monochromePalette()[0] : fallback

  candidates.sort(function(a, b) { return b.hslSaturation - a.hslSaturation })

  for (var j = 0; j < candidates.length; j++) {
    var adjusted = ensureContrast(candidates[j], background, target, 16)
    if (contrastRatio(adjusted, background) >= target) return adjusted
  }
  // Nothing on the sleeve survives being made legible; the theme's own accent
  // beats shipping text that cannot be read.
  return fallback
}
