// Background: a dark abyss, deepest in the middle of the rift, with faint drifting grain.

vec4 shade(vec2 uv) {
    float d = riftDist(uv);
    float inside = clamp(d + 0.5, 0.0, 1.0);
    if (inside <= 0.0)
        return vec4(0.0);

    vec2 r = riftUV(uv);
    float depth = 1.0 - abs(r.y);                          // 1 in the middle, 0 at the edges
    float grain = noise2(toPx(uv) * 0.35 + vec2(iTime * 6.0, 0.0)) * 0.018;
    vec3 col = uVoid.rgb * (1.0 - 0.7 * depth) + accent() * 0.05 * (1.0 - depth) + grain;
    return vec4(col, 1.0) * inside;
}
