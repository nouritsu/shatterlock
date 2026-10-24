// Example opening: a shockwave ripples out from the middle of the crack as the screen tears,
// bending the picture as it passes. Opening shaders post-process the whole rift via uSource.
//
//   config.json: "fx": { "opening": "ripple.frag" }

vec4 shade(vec2 uv) {
    vec2 px = toPx(uv);
    vec2 centre = 0.5 * iResolution;
    float reach = uPhase < 1.5 ? 0.3 * uSpread : 0.3 + uProgress;
    float radius = reach * length(iResolution) * 0.6;

    float ring = exp(-abs(length(px - centre) - radius) / 30.0) * (1.0 - smoothstep(0.6, 1.0, uProgress));
    vec2 dir = normalize(px - centre + 1e-4);
    vec4 col = texture(uSource, toUv(px - dir * ring * 14.0));
    col.rgb += accent() * ring * 0.25;
    return col;
}
