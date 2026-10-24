.pragma library

// Crack geometry. The main crack runs corner to corner and is a function v(u) over the straight
// diagonal (u along it, v along its normal), sampled at SAMPLES + 1 evenly spaced points. That keeps
// the gap measured along the normal exactly equal to the separation of the halves everywhere, and
// lets shaders find the side of any pixel in O(1).

var SAMPLES = 128;      // segments of the main crack (power of two for midpoint displacement)
var MAX_BRANCH_SEGMENTS = 12;

function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
        a = (a + 0x6D2B79F5) | 0;
        var t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// opts: { width, height, corners: "bl-tr"|"tl-br", seed (number), jaggedness 0..1, branches (bool),
//         anchors: [t 0..1], anchorHalfLength px, anchorSlack px }
function generate(opts) {
    var w = opts.width, h = opts.height;
    var from = opts.corners === "tl-br" ? { x: 0, y: 0 } : { x: 0, y: h };
    var to = opts.corners === "tl-br" ? { x: w, y: h } : { x: w, y: 0 };
    var length = Math.hypot(to.x - from.x, to.y - from.y);
    var dir = { x: (to.x - from.x) / length, y: (to.y - from.y) / length };
    var normal = { x: -dir.y, y: dir.x }; // points into half B

    var rand = mulberry32(opts.seed);
    var n = SAMPLES;
    var du = length / n;
    var v = new Array(n + 1).fill(0);

    // Midpoint displacement; roughness 0.7 keeps the fine scale visibly jagged.
    var amp = 0.05 * length * opts.jaggedness;
    for (var step = n; step > 1; step /= 2) {
        for (var i = step / 2; i < n; i += step)
            v[i] = (v[i - step / 2] + v[i + step / 2]) / 2 + (rand() * 2 - 1) * amp;
        amp *= 0.7;
    }

    // Flatten around each button anchor so the rotated button always fits inside the gap.
    var anchors = opts.anchors || [];
    for (var a = 0; a < anchors.length; a++) {
        var ua = anchors[a] * length;
        var ia = Math.round(ua / du);
        var va = v[ia];
        var reach = opts.anchorHalfLength + 3 * du; // blend over a few samples beyond the button
        for (var j = 0; j <= n; j++) {
            var dist = Math.abs(j * du - ua);
            if (dist > reach)
                continue;
            var slack = dist <= opts.anchorHalfLength ? opts.anchorSlack : opts.anchorSlack + (dist - opts.anchorHalfLength) * 0.8;
            v[j] = Math.max(va - slack, Math.min(va + slack, v[j]));
        }
    }

    // Limit slopes to ~55° so no edge gets too thin, then pin both ends back to the corners.
    var maxRise = Math.tan(55 * Math.PI / 180) * du;
    for (var k = 1; k <= n; k++)
        v[k] = Math.max(v[k - 1] - maxRise, Math.min(v[k - 1] + maxRise, v[k]));
    for (var m = n - 1; m >= 0; m--)
        v[m] = Math.max(v[m + 1] - maxRise, Math.min(v[m + 1] + maxRise, v[m]));
    var drift0 = v[0], drift1 = v[n];
    for (var q = 0; q <= n; q++)
        v[q] -= drift0 + (drift1 - drift0) * q / n;

    function pointAt(t) {
        var u = Math.max(0, Math.min(1, t)) * length;
        var idx = Math.min(n - 1, Math.floor(u / du));
        var f = u / du - idx;
        var vv = v[idx] * (1 - f) + v[idx + 1] * f;
        return { x: from.x + dir.x * u + normal.x * vv, y: from.y + dir.y * u + normal.y * vv };
    }

    // Hairline branches running off into either half; drawn on the halves and revealed when the
    // spreading crack passes their root.
    var branches = [];
    if (opts.branches) {
        var count = 4 + Math.floor(rand() * 3);
        for (var b = 0; b < count && branches.length < MAX_BRANCH_SEGMENTS - 1; b++) {
            var t0 = 0.06 + rand() * 0.88;
            var side = rand() < 0.5 ? -1 : 1;
            var p = pointAt(t0);
            var ang = (20 + rand() * 40) * Math.PI / 180;
            var along = rand() < 0.5 ? 1 : -1;
            var segs = 2 + Math.floor(rand() * 2);
            var len = 50 + rand() * 150;
            for (var s = 0; s < segs && branches.length < MAX_BRANCH_SEGMENTS; s++) {
                var segLen = len / segs * (0.7 + rand() * 0.6);
                var a2 = ang + (rand() * 2 - 1) * 0.5;
                var dx = (dir.x * Math.cos(a2) * along + normal.x * Math.sin(a2) * side) * segLen;
                var dy = (dir.y * Math.cos(a2) * along + normal.y * Math.sin(a2) * side) * segLen;
                var p2 = { x: p.x + dx, y: p.y + dy };
                branches.push({ x1: p.x, y1: p.y, x2: p2.x, y2: p2.y, reveal: Math.min(1, t0 + 0.02 * (s + 1)) });
                p = p2;
            }
        }
    }

    // How far (px, along the normal) a screen point is from the closed crack; the rift between
    // halves parted by `gap` covers |offset| < gap / 2.
    function offsetFrom(x, y) {
        var u = (x - from.x) * dir.x + (y - from.y) * dir.y;
        var vp = (x - from.x) * normal.x + (y - from.y) * normal.y;
        var fi = Math.max(0, Math.min(n - 0.0001, u / du));
        var idx = Math.floor(fi);
        var vc = v[idx] + (v[idx + 1] - v[idx]) * (fi - idx);
        return vp - vc;
    }

    return {
        from: from,
        to: to,
        dir: dir,
        normal: normal,
        length: length,
        angle: Math.atan2(dir.y, dir.x) * 180 / Math.PI,
        samples: v,
        branches: branches,
        anchorPoints: anchors.map(function (t) { return pointAt(t); }),
        pointAt: pointAt,
        offsetFrom: offsetFrom
    };
}

// Pack floats into Qt.matrix4x4 arguments (16 per matrix, unused slots filled with `pad`).
// In GLSL element k of the matrix is m[k % 4][k / 4].
function packMatrices(values, count, pad) {
    var out = [];
    for (var i = 0; i < count; i++) {
        var chunk = [];
        for (var k = 0; k < 16; k++) {
            var idx = i * 16 + k;
            chunk.push(idx < values.length ? values[idx] : pad);
        }
        out.push(chunk);
    }
    return out;
}

function branchFloats(branches) {
    var coords = [], reveal = [];
    for (var i = 0; i < MAX_BRANCH_SEGMENTS; i++) {
        var b = branches[i];
        if (b) {
            coords.push(b.x1, b.y1, b.x2, b.y2);
            reveal.push(b.reveal);
        } else {
            coords.push(-1e4, -1e4, -1e4, -1e4);
            reveal.push(2);
        }
    }
    return { coords: coords, reveal: reveal };
}
