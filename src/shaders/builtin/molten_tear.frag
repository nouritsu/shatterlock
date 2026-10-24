// Opening: the screen tears white-hot: the crack burns as it spreads, the edges blaze while the
// halves part, and heat haze ripples the picture near them. Post-pass over the rift (uSource).

vec4 shade(vec2 uv) {
    vec2 px = toPx(uv);
    float hot = uPhase < 1.5 ? 1.0 : 1.0 - smoothstep(0.25, 1.0, uProgress);
    vec3 glow = mix(vec3(1.0, 0.42, 0.08), vec3(1.0, 0.97, 0.86), hot);

    float d = uPhase < 1.5 ? crackAt(px).r : riftDist(uv);
    float reached = uPhase < 1.5 ? step(crackAt(px).g, uSpread) : 1.0;

    float haze = exp(-abs(d) / 26.0) * hot * reached;
    vec2 wobble = vec2(noise2(px * 0.05 + iTime * 5.0), noise2(px * 0.05 - iTime * 5.0)) - 0.5;
    vec4 col = texture(uSource, toUv(px + wobble * 7.0 * haze));

    col.rgb += glow * exp(-abs(d) / 3.0) * hot * reached * 1.4;
    return col;
}
