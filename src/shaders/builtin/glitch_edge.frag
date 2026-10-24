// Edge: a digital shimmer along the broken edges: RGB-split copies of the screen smear into the
// rift, scanline blocks jump, and accent-coloured slivers flicker.

vec4 shade(vec2 uv) {
    float opened = smoothstep(2.0, 20.0, uGap);
    float d = riftDist(uv);
    float band = exp(-abs(d) / 11.0);
    if (opened <= 0.0 || band < 0.01)
        return vec4(0.0);

    vec2 px = toPx(uv);
    float t = floor(iTime * 24.0);
    float block = floor(px.y / 20.0);
    float jumping = step(0.74, hash12(vec2(block, t)));
    float jump = jumping * (hash12(vec2(block, t + 5.0)) - 0.5) * 30.0;
    vec2 o = vec2(3.5 + jump, 0.0);

    vec3 split = vec3(snapshot(toUv(px + o)).r, snapshot(uv).g, snapshot(toUv(px - o)).b);
    float scan = 0.8 + 0.2 * step(0.5, fract(px.y / 3.0));
    float a = band * 0.8 * opened;

    // Slivers: short accent bars that blink on the edges.
    float sliver = jumping * step(0.5, hash12(vec2(block, t + 9.0))) * exp(-abs(d) / 4.0);
    vec3 tint = accent() * (0.6 * exp(-abs(d) / 1.5) + 0.9 * sliver) * opened;
    return vec4(split * scan * a + tint, a);
}
