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

function splitStroke(points, center, radius) {
    var segments = []
    var current = []
    for (var i = 0; i < points.length; i++) {
        if (pointDistance(points[i], center) > radius) {
            current.push([Number(points[i][0]), Number(points[i][1])])
        } else if (current.length > 0) {
            if (current.length > 1)
                segments.push(current)
            current = []
        }
    }
    if (current.length > 1)
        segments.push(current)
    return segments
}

function hitTest(objects, point, tolerance) {
    for (var i = objects.length - 1; i >= 0; i--) {
        var object = objects[i]
        if (object.type === "text") {
            var height = Number(object.height) || 40
            if (point[0] >= object.x && point[0] <= object.x + object.width
                    && point[1] >= object.y && point[1] <= object.y + height)
                return object.id
        } else if (object.type === "stroke" && object.points && object.points.length) {
            var radius = Number(tolerance) + Number(object.width || 1) / 2
            if (object.points.length === 1 && pointDistance(point, object.points[0]) <= radius)
                return object.id
            for (var j = 1; j < object.points.length; j++) {
                if (segmentDistance(point, object.points[j - 1], object.points[j]) <= radius)
                    return object.id
            }
        }
    }
    return ""
}

if (typeof module !== "undefined")
    module.exports = {
        pointDistance: pointDistance,
        segmentDistance: segmentDistance,
        splitStroke: splitStroke,
        hitTest: hitTest
    }
