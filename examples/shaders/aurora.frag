// Example background: slow aurora curtains drifting through the rift, tinted by the accent.
//
//   cp aurora.frag ~/.config/shatterlock/shaders/
//   config.json: "fx": { "background": "aurora.frag" }

vec4 shade(vec2 uv) {
    float d = riftDist(uv);
    if (d <= -1.0)
        return vec4(0.0); // over the halves: nothing to draw

    vec2 r = riftUV(uv); // x along the crack 0..1, y across it -1..1
    float t = iTime * 0.25;
    float bands = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float wave = sin(r.x * (8.0 + fi * 5.0) + t * (1.0 + fi) + noise2(vec2(r.x * 6.0, t + fi)) * 3.0);
        bands += smoothstep(0.35, 0.0, abs(r.y - 0.4 * wave)) * (0.6 - fi * 0.15);
    }

    vec3 tint = mix(accent(), vec3(0.3, 1.0, 0.7), 0.4 + 0.3 * sin(t + r.x * 3.0));
    vec3 col = uVoid.rgb + bands * tint;
    return vec4(col, 1.0) * clamp(d + 0.5, 0.0, 1.0);
}
