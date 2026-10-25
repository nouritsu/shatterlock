// The two halves of the frozen screen pushed apart; transparent inside the rift so the background
// slot shows through. Also draws the hairline crack while it spreads and a dark bevel along the
// broken edges.

// One half's surface at its own (closed-screen) position q.
vec3 surface(vec2 q) {
    // Past the screen's edge (uncovered as the halves part) the picture is mirrored back in and
    // kept in shadow; the crack field has no hairlines out there.
    bool inside = onScreen(q);
    vec4 c = inside ? crackAt(q) : vec4(crackSide(q), 0.0, 0.0, 0.0);
    vec3 col = obscuredSnapshot(mirrorPx(q), abs(c.r));
    if (!inside)
        col *= 0.6;

    float diag = length(iResolution);
    float opened = clamp(uGap / 24.0, 0.0, 1.0);

    // Bevel: the broken edge falls away into the rift.
    float bevel = 1.0 - smoothstep(0.0, 9.0, abs(c.r));
    col *= 1.0 - 0.55 * bevel * opened;

    // The hairline is a crack in the picture's glass: under the lock blur it goes with the picture.
    float clear = 1.0 - obscureAmount(abs(c.r));

    // The main hairline while spreading / sealing, with a bright tip at the spreading front.
    float line = (1.0 - smoothstep(0.45, 1.6, abs(c.r))) * step(c.g, uSpread) * uLine * clear;
    col = mix(col, vec3(0.02), 0.85 * line);
    float tip = exp(-abs(c.g - uSpread) * diag / 14.0) * (1.0 - smoothstep(0.0, 4.0, abs(c.r)));
    col += accent() * 1.2 * tip * uLine * clear * step(uSpread, 0.999);
    return col;
}

vec4 shade(vec2 uv) {
    vec2 px = toPx(uv);
    vec2 qa = px - uOffA;
    vec2 qb = px - uOffB;

    // Coverage of each half, antialiased over a pixel; complementary while closed, so the closed
    // screen reproduces the snapshot exactly.
    float onA = clamp(0.5 - crackSide(qa), 0.0, 1.0);
    float onB = clamp(0.5 + crackSide(qb), 0.0, 1.0);

    vec3 col = vec3(0.0);
    if (onA > 0.0)
        col += surface(qa) * onA;
    if (onB > 0.0)
        col += surface(qb) * onB;
    float a = min(onA + onB, 1.0);

    // A custom shader failed to build: a thin red line down the middle of the rift says so.
    if (uWarn > 0.0 && uGap > 4.0) {
        float fromMiddle = abs(riftUV(uv).y) * uGap * 0.5;
        float warn = exp(-fromMiddle / 0.9) * (1.0 - a);
        col += vec3(1.0, 0.18, 0.2) * warn;
        a += warn;
    }
    return vec4(col, a);
}
