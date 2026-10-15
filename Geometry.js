function pointDistance(a, b) {
    var dx = Number(a[0]) - Number(b[0])
    var dy = Number(a[1]) - Number(b[1])
    return Math.sqrt(dx * dx + dy * dy)
}

function segmentDistance(point, start, end) {
    var vx = Number(end[0]) - Number(start[0])
    var vy = Number(end[1]) - Number(start[1])
    var lengthSquared = vx * vx + vy * vy
    if (lengthSquared === 0)
        return pointDistance(point, start)
    var t = ((Number(point[0]) - Number(start[0])) * vx + (Number(point[1]) - Number(start[1])) * vy) / lengthSquared
    t = Math.max(0, Math.min(1, t))
    return pointDistance(point, [Number(start[0]) + t * vx, Number(start[1]) + t * vy])
}

function lerp(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]
}

// Parameter range [t0, t1] of segment a→b that lies inside the circle, or null.
function circleSpan(a, b, center, radius) {
    var dx = b[0] - a[0]
    var dy = b[1] - a[1]
    var fx = a[0] - center[0]
    var fy = a[1] - center[1]
    var qa = dx * dx + dy * dy
    var qc = fx * fx + fy * fy - radius * radius
    if (qa === 0)
        return qc < 0 ? [0, 1] : null
    var qb = 2 * (fx * dx + fy * dy)
    var discriminant = qb * qb - 4 * qa * qc
    if (discriminant <= 0)
        return null
    var root = Math.sqrt(discriminant)
    var t0 = (-qb - root) / (2 * qa)
    var t1 = (-qb + root) / (2 * qa)
    if (t1 <= 0 || t0 >= 1)
        return null
    return [Math.max(0, t0), Math.min(1, t1)]
}

function strokeLength(points) {
    var length = 0
    for (var i = 1; i < points.length; i++)
        length += pointDistance(points[i - 1], points[i])
    return length
}

// Cuts the circular eraser footprint out of a polyline. Cuts land exactly on the
// circle edge, so sparse or simplified strokes erase as precisely as dense ones.
function splitStroke(points, center, radius) {
    var segments = []
    var current = []

    function push(point) {
        var last = current[current.length - 1]
        if (!last || last[0] !== point[0] || last[1] !== point[1])
            current.push([point[0], point[1]])
    }
    function flush() {
        if (current.length > 1 && strokeLength(current) >= 0.75)
            segments.push(current)
        current = []
    }

    if (points.length === 1)
        return pointDistance(points[0], center) > radius ? [[[points[0][0], points[0][1]]]] : []

    for (var i = 0; i + 1 < points.length; i++) {
        var a = [Number(points[i][0]), Number(points[i][1])]
        var b = [Number(points[i + 1][0]), Number(points[i + 1][1])]
        var span = circleSpan(a, b, center, radius)
        if (!span) {
            push(a)
            continue
        }
        if (span[0] > 0) {
            push(a)
            push(lerp(a, b, span[0]))
        }
        flush()
        if (span[1] < 1)
            push(lerp(a, b, span[1]))
    }
    var last = points[points.length - 1]
    if (pointDistance(last, center) > radius)
        push([Number(last[0]), Number(last[1])])
    flush()
    return segments
}

function strokeTouches(points, center, radius) {
    if (!points || points.length === 0)
        return false
    if (points.length === 1)
        return pointDistance(points[0], center) <= radius
    for (var i = 1; i < points.length; i++) {
        if (segmentDistance(center, points[i - 1], points[i]) <= radius)
            return true
    }
    return false
}

function rectTouches(object, center, radius) {
    var height = Number(object.height) || 40
    var nearestX = Math.max(object.x, Math.min(center[0], object.x + object.width))
    var nearestY = Math.max(object.y, Math.min(center[1], object.y + height))
    return pointDistance(center, [nearestX, nearestY]) <= radius
}

function hitTest(objects, point, tolerance) {
    for (var i = objects.length - 1; i >= 0; i--) {
        var object = objects[i]
        if (object.type === "text") {
            if (rectTouches(object, point, 0))
                return object.id
        } else if (object.type === "stroke") {
            if (strokeTouches(object.points, point, Number(tolerance) + Number(object.width || 1) / 2))
                return object.id
        }
    }
    return ""
}

// Ramer–Douglas–Peucker: drops points that deviate less than `tolerance` from the line.
function simplifyStroke(points, tolerance) {
    if (points.length <= 2)
        return points.slice()
    var keep = new Array(points.length)
    keep[0] = keep[points.length - 1] = true
    var stack = [[0, points.length - 1]]
    while (stack.length) {
        var range = stack.pop()
        var farthest = -1
        var farthestDistance = tolerance
        for (var i = range[0] + 1; i < range[1]; i++) {
            var distance = segmentDistance(points[i], points[range[0]], points[range[1]])
            if (distance > farthestDistance) {
                farthest = i
                farthestDistance = distance
            }
        }
        if (farthest >= 0) {
            keep[farthest] = true
            stack.push([range[0], farthest], [farthest, range[1]])
        }
    }
    return points.filter(function(point, index) { return keep[index] })
}

// Points spaced evenly every `spacing` along the polyline, keeping both ends.
function resample(points, spacing) {
    var result = [[points[0][0], points[0][1]]]
    var carried = 0
    for (var i = 1; i < points.length; i++) {
        var a = points[i - 1]
        var b = points[i]
        var length = pointDistance(a, b)
        var t = spacing - carried
        while (t <= length) {
            result.push(lerp(a, b, t / length))
            t += spacing
        }
        carried = length - (t - spacing)
    }
    var last = points[points.length - 1]
    if (pointDistance(result[result.length - 1], last) > 0.01)
        result.push([last[0], last[1]])
    return result
}

// Indexes of sharp corners, judged over `reach` samples on either side so that pixel
// stair-steps and small wobbles do not count as corners.
function findCorners(points, reach, minAngle) {
    var angles = []
    for (var i = 0; i < points.length; i++) {
        if (i < reach || i + reach >= points.length) {
            angles.push(0)
            continue
        }
        var a = points[i - reach], p = points[i], b = points[i + reach]
        var inAngle = Math.atan2(p[1] - a[1], p[0] - a[0])
        var outAngle = Math.atan2(b[1] - p[1], b[0] - p[0])
        var turn = Math.abs(outAngle - inAngle)
        angles.push(turn > Math.PI ? 2 * Math.PI - turn : turn)
    }
    var corners = []
    for (var j = reach; j + reach < points.length; j++) {
        if (angles[j] < minAngle)
            continue
        var peak = true
        for (var k = Math.max(0, j - reach); k <= Math.min(points.length - 1, j + reach) && peak; k++)
            peak = angles[k] < angles[j] || (angles[k] === angles[j] && k >= j)
        if (peak)
            corners.push(j)
    }
    return corners
}

// Steadies mouse input: the path is resampled evenly and each point is averaged with its
// neighbours along the path (Gaussian, `sigma` long). Averaging never reaches across a sharp
// corner, and windows shrink symmetrically at the ends and corners, so corners stay crisp
// and the stroke still ends exactly under the pointer.
function smoothStroke(points, sigma) {
    if (points.length < 3 || strokeLength(points) < sigma)
        return points.slice()
    var spacing = 1
    var even = resample(points, spacing)
    var reach = Math.max(2, Math.round(2 * sigma / spacing))
    var anchors = [0].concat(findCorners(even, reach, 1.0), [even.length - 1])
    var radius = Math.ceil(3 * sigma / spacing)
    var weights = []
    for (var w = 0; w <= radius; w++)
        weights.push(Math.exp(-(w * w * spacing * spacing) / (2 * sigma * sigma)))

    var result = []
    for (var s = 0; s + 1 < anchors.length; s++) {
        var start = anchors[s], end = anchors[s + 1]
        for (var i = start; i < end || (i === end && s + 2 === anchors.length); i++) {
            var span = Math.min(radius, i - start, end - i)
            var x = 0, y = 0, total = 0
            for (var d = -span; d <= span; d++) {
                var weight = weights[Math.abs(d)]
                x += even[i + d][0] * weight
                y += even[i + d][1] * weight
                total += weight
            }
            result.push([x / total, y / total])
        }
    }
    return result
}

if (typeof module !== "undefined")
    module.exports = {
        smoothStroke: smoothStroke,
        pointDistance: pointDistance,
        segmentDistance: segmentDistance,
        splitStroke: splitStroke,
        strokeTouches: strokeTouches,
        rectTouches: rectTouches,
        hitTest: hitTest,
        simplifyStroke: simplifyStroke
    }
