// Example edge: a neon tube just inside each broken edge, with pulses racing along the crack.
//
//   config.json: "fx": { "edge": "neon.frag" }

vec4 shade(vec2 uv) {
    float opened = smoothstep(2.0, 20.0, uGap);
    float d = riftDist(uv);
    float x = riftUV(uv).x;

    float tube = exp(-abs(d - 2.5) / 1.6);
    float pulse = pow(0.5 + 0.5 * sin(x * 40.0 - iTime * 6.0), 8.0);
    vec3 col = accent() * tube * (0.6 + 1.4 * pulse) + vec3(1.0) * tube * pulse * 0.4;
    return vec4(col * opened, 0.0); // alpha 0: added on top as light
}
