// Edge: the broken edges glow in the accent colour, bleeding into the rift, with a slow shimmer.

vec4 shade(vec2 uv) {
    float d = riftDist(uv);
    float opened = smoothstep(0.0, 18.0, uGap);
    if (opened <= 0.0)
        return vec4(0.0);

    float along = riftUV(uv).x;
    float shimmer = 0.8 + 0.2 * noise2(vec2(along * 60.0, iTime * 2.5));

    float rim = exp(-abs(d) / 1.4);                        // thin hot line on the edge itself
    float bleed = d > 0.0 ? exp(-d / 22.0) : exp(d / 3.0); // into the rift; barely onto the halves
    vec3 col = accent() * (0.95 * rim + 0.5 * bleed) * shimmer * opened;
    col += vec3(1.0) * 0.25 * rim * opened;                // white-hot core
    return vec4(col, 0.0);                                 // additive
}
