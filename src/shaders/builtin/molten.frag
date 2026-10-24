// Edge: the broken edges glow like lava, white-hot as they tear and cooling through orange to the
// accent colour, with embers dripping into the rift.

// 0 cool (accent) .. 0.5 orange .. 1 white-hot
vec3 heat(float t) {
    vec3 orange = vec3(1.0, 0.38, 0.06);
    vec3 white = vec3(1.0, 0.96, 0.82);
    return t < 0.5 ? mix(accent(), orange, t * 2.0) : mix(orange, white, (t - 0.5) * 2.0);
}

vec4 shade(vec2 uv) {
    float opened = smoothstep(2.0, 24.0, uGap);
    if (opened <= 0.0)
        return vec4(0.0);

    float d = riftDist(uv);
    vec2 r = riftUV(uv);
    float x = r.x * length(iResolution);
    float flow = 0.6 * noise2(vec2(x * 0.02 - iTime * 0.6, iTime * 0.3))
               + 0.4 * noise2(vec2(x * 0.07 + iTime, 3.0));

    // Cools over the first couple of seconds, then keeps a slow pulse.
    float temp = mix(1.0, 0.45, smoothstep(0.2, 2.5, iTime)) + 0.12 * (flow - 0.5);

    float crust = d < 0.0 ? exp(d / (4.0 + 6.0 * flow)) : 0.0; // glowing lip on the halves
    float rim = exp(-abs(d) / 1.5);
    float bleed = d > 0.0 ? exp(-d / 16.0) : 0.0;

    // Embers: a drop per cell, falling from one edge towards the other.
    float drops = 0.0;
    if (d > 0.0) {
        const float cell = 46.0;
        float ci = floor(x / cell);
        float h = hash12(vec2(ci, 11.0));
        float life = fract(iTime * (0.25 + 0.35 * h) + h);
        float from = h > 0.5 ? -1.0 : 1.0;
        float y = mix(from, -from * 0.4, life);
        float cx = (ci + 0.5) * cell + (h - 0.5) * 20.0;
        vec2 dp = vec2(x - cx, (r.y - y) * uGap * 0.5) / 3.0;
        drops = exp(-dot(dp, dp)) * (1.0 - life) * step(0.35, h);
    }

    vec3 col = heat(temp) * (0.8 * crust + 0.9 * rim)
             + heat(temp * 0.7) * 0.6 * bleed
             + heat(0.85) * drops;
    return vec4(col * opened, 0.0); // additive
}
