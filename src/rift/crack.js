.pragma library

// Crack geometry. The main crack runs corner to corner and is a function v(u) over the straight
// diagonal (u along it, v along its normal), sampled at SAMPLES + 1 evenly spaced points. That keeps
// the gap measured along the normal exactly equal to the separation of the halves everywhere, and
// lets shaders find the side of any pixel in O(1).

var SAMPLES = 128;      // segments of the main crack (power of two for midpoint displacement)

function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
        a = (a + 0x6D2B79F5) | 0;
        var t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// opts: { width, height, corners: "bl-tr"|"tl-br", seed (number),
//         shape: "jagged" (default) | "wave", jaggedness 0..1, waveLength px, waveHeight px,
//         anchors: [t 0..1], anchorHalfLength px, anchorSlack px,
//         flats: [{ t, halfLength, slack }] }
//
// A wave is a smooth sine (its phase from the seed); it ignores the anchors, and its flats ease it
// back to the straight diagonal instead of clamping it, so it never kinks.
function generate(opts) {
    if (opts.shape === "wave")
        return wave(opts);
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

    // Flatten the crack within `slack` px of its height at t over `halfLength` px either side
    // (blending out over a few samples beyond), so whatever sits there fits inside the gap.
    function flatten(t, halfLength, slack) {
        var ua = t * length;
        var va = v[Math.round(ua / du)];
        var reach = halfLength + 3 * du;
        for (var j = 0; j <= n; j++) {
            var dist = Math.abs(j * du - ua);
            if (dist > reach)
                continue;
            var s = dist <= halfLength ? slack : slack + (dist - halfLength) * 0.8;
            v[j] = Math.max(va - s, Math.min(va + s, v[j]));
        }
    }

    // Under each button anchor, so the rotated button always fits, and any other flat stretches
    // asked for (the lock screen's user block).
    var anchors = opts.anchors || [];
    for (var a = 0; a < anchors.length; a++)
        flatten(anchors[a], opts.anchorHalfLength, opts.anchorSlack);
    var flats = opts.flats || [];
    for (var f = 0; f < flats.length; f++)
        flatten(flats[f].t, flats[f].halfLength, flats[f].slack);

    // Limit slopes to ~55° so no edge gets too thin, then pin both ends back to the corners.
    var maxRise = Math.tan(55 * Math.PI / 180) * du;
    for (var k = 1; k <= n; k++)
        v[k] = Math.max(v[k - 1] - maxRise, Math.min(v[k - 1] + maxRise, v[k]));
    for (var m = n - 1; m >= 0; m--)
        v[m] = Math.max(v[m + 1] - maxRise, Math.min(v[m + 1] + maxRise, v[m]));
    var drift0 = v[0], drift1 = v[n];
    for (var q = 0; q <= n; q++)
        v[q] -= drift0 + (drift1 - drift0) * q / n;

    return build(from, to, dir, normal, length, v, anchors);
}

function wave(opts) {
    var w = opts.width, h = opts.height;
    var from = opts.corners === "tl-br" ? { x: 0, y: 0 } : { x: 0, y: h };
    var to = opts.corners === "tl-br" ? { x: w, y: h } : { x: w, y: 0 };
    var length = Math.hypot(to.x - from.x, to.y - from.y);
    var dir = { x: (to.x - from.x) / length, y: (to.y - from.y) / length };
    var normal = { x: -dir.y, y: dir.x };

    var n = SAMPLES;
    var du = length / n;
    var phase = mulberry32(opts.seed)() * 2 * Math.PI;
    var waveLength = Math.max(40, opts.waveLength);
    var v = new Array(n + 1);
    for (var i = 0; i <= n; i++)
        v[i] = opts.waveHeight * Math.sin(2 * Math.PI * i * du / waveLength + phase);

    // Ease into each flat stretch over half a wavelength, and to nothing at both corners.
    var ease = waveLength / 2;
    function smooth(x) {
        x = Math.max(0, Math.min(1, x));
        return x * x * (3 - 2 * x);
    }
    var flats = opts.flats || [];
    for (var j = 0; j <= n; j++) {
        var u = j * du;
        var keep = smooth(Math.min(u, length - u) / ease);
        for (var f = 0; f < flats.length; f++)
            keep = Math.min(keep, smooth((Math.abs(u - flats[f].t * length) - flats[f].halfLength) / ease));
        v[j] *= keep;
    }

    return build(from, to, dir, normal, length, v, opts.anchors || []);
}

function build(from, to, dir, normal, length, v, anchors) {
    var n = SAMPLES;
    var du = length / n;

    function pointAt(t) {
        var u = Math.max(0, Math.min(1, t)) * length;
        var idx = Math.min(n - 1, Math.floor(u / du));
        var f = u / du - idx;
        var vv = v[idx] * (1 - f) + v[idx + 1] * f;
        return { x: from.x + dir.x * u + normal.x * vv, y: from.y + dir.y * u + normal.y * vv };
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
