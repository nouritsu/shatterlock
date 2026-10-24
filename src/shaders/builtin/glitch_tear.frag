// Opening: the tear glitches open: RGB channels split and scanline blocks jump around the crack,
// settling as the halves come to rest. Post-pass over the composited rift (uSource).

vec4 shade(vec2 uv) {
    float k = uPhase < 1.5 ? 0.5 : 1.0 - smoothstep(0.5, 1.0, uProgress);
    vec2 px = toPx(uv);
    float near = exp(-abs(riftDist(uv)) / 140.0);
    if (uPhase < 1.5)
        near = exp(-abs(crackAt(px).r) / 60.0) * step(crackAt(px).g, uSpread);

    float t = floor(iTime * 30.0);
    float block = floor(px.y / 18.0);
    float shift = step(0.72, hash12(vec2(block, t))) * (hash12(vec2(block, t + 1.0)) - 0.5) * 90.0;
    vec2 base = px + vec2(shift * k * near, 0.0);
    float split = 7.0 * k * near;

    vec4 g = texture(uSource, toUv(base));
    float r = texture(uSource, toUv(base + vec2(split, 0.0))).r;
    float b = texture(uSource, toUv(base - vec2(split, 0.0))).b;
    vec4 col = vec4(r, g.g, b, g.a);
    col.rgb *= 1.0 - 0.18 * k * near * step(0.5, fract(px.y / 3.0));
    return col;
}
