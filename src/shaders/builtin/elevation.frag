// Edge: the halves lift off the rift like sheets of paper and cast Material Design shadows into it.
// The light comes from above, so the upper edge throws a key shadow down across the rift; both
// edges also have a tight ambient shadow. Only the rift is shaded, more deeply as the halves part.

vec4 shade(vec2 uv) {
    vec2 px = toPx(uv);
    float d = riftDist(uv);
    float inside = clamp(d + 0.5, 0.0, 1.0);
    float lift = smoothstep(0.0, 48.0, uGap);
    if (inside <= 0.0 || lift <= 0.0)
        return vec4(0.0);

    // Key shadow: each half's outline, dropped and blurred.
    vec2 drop = vec2(0.0, 12.0 * lift);
    float blur = 4.0 + 12.0 * lift;
    float keyA = 1.0 - smoothstep(-blur, blur, awayFromA(px - drop));
    float keyB = 1.0 - smoothstep(-blur, blur, awayFromB(px - drop));
    float key = 0.55 * max(keyA, keyB);

    // Ambient shadow, close to either edge.
    float ambient = 0.35 * exp(-max(d, 0.0) / 7.0);

    float shadow = 1.0 - (1.0 - key) * (1.0 - ambient);
    return vec4(0.0, 0.0, 0.0, shadow * lift * inside);
}
