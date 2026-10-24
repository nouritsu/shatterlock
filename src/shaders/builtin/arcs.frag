// Edge: electric arcs crackle across the gap between the broken edges.

vec4 shade(vec2 uv) {
    float opened = smoothstep(4.0, 30.0, uGap);
    if (opened <= 0.0)
        return vec4(0.0);

    float d = riftDist(uv);
    vec3 cool = mix(accent(), vec3(0.85, 0.92, 1.0), 0.55);

    // A thin, slightly flickering rim on both edges.
    float flicker = 0.75 + 0.25 * hash12(vec2(floor(iTime * 30.0), 3.0));
    vec3 col = cool * exp(-abs(d) / 1.2) * 0.8 * flicker;

    if (d > -3.0) {
        vec2 r = riftUV(uv);
        float x = r.x * length(iResolution); // px along the crack
        float inGap = smoothstep(-3.0, 2.0, d);
        const float cell = 150.0;
        float ci = floor(x / cell);
        for (int k = -1; k <= 1; k++) {
            float c = ci + float(k);
            // Each cell re-rolls its arc several times a second; only some cells fire at once.
            float slot = floor(iTime * 9.0 + hash12(vec2(c, 7.0)) * 10.0);
            float on = step(0.58, hash12(vec2(c, slot)));
            if (on <= 0.0)
                continue;
            float cx = (c + 0.2 + 0.6 * hash12(vec2(c, slot + 3.0))) * cell;
            // A jagged path across the gap: big kinks plus fine jitter.
            float wob = (noise2(vec2(r.y * 5.0 + slot * 1.3, c)) - 0.5) * 34.0
                      + (noise2(vec2(r.y * 19.0, slot * 1.7 + c)) - 0.5) * 9.0;
            float dx = abs(x - (cx + wob));
            float core = exp(-dx / 1.0);
            float halo = exp(-dx / 8.0) * 0.4;
            col += (vec3(0.95, 0.97, 1.0) * core + cool * halo) * inGap;
        }
    }
    return vec4(col * opened, 0.0); // additive
}
