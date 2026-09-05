.pragma library

var CAP = 10

function insert(list, query, cap) {
  var limit = parseInt(cap, 10)
  if (isNaN(limit) || limit < 1) limit = CAP

  var trimmed = String(query || "").trim()
  if (trimmed.length === 0) return (list || []).slice(0, limit)

  var out = [trimmed]
  var source = list || []
  for (var i = 0; i < source.length; i++) {
    if (source[i] === trimmed) continue
    out.push(source[i])
    if (out.length === limit) break
  }
  return out
}

function sanitize(rawText) {
  var parsed
  try {
    parsed = JSON.parse(String(rawText || ""))
  } catch (e) {
    return []
  }
  if (!Array.isArray(parsed)) return []

  var out = []
  for (var i = 0; i < parsed.length && out.length < CAP; i++)
    if (typeof parsed[i] === "string" && parsed[i].length > 0) out.push(parsed[i])
  return out
}

function serialize(list) {
  return JSON.stringify((list || []).slice(0, CAP))
}
