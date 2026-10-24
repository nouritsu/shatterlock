#version 440
// Locked outputs other than the rift's: dark, accent-tinted fog with smoke drifting through.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float iTime;
    vec2 iResolution;
    vec4 uAccent; // premultiplied
    vec4 uVoid;   // premultiplied
};

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
               mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise2(p);
        p = p * 2.03 + vec2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 p = qt_TexCoord0 * iResolution * 0.0035;
    vec2 drift = vec2(iTime * 0.035, -iTime * 0.022);
    float smoke = fbm(p + drift + 1.6 * fbm(p * 1.7 - drift));
    vec3 fog = mix(uVoid.rgb, uAccent.rgb * 0.32, smoothstep(0.42, 0.9, smoke)) + uAccent.rgb * 0.04;
    fragColor = vec4(fog * (0.55 + 0.9 * smoke), 1.0) * qt_Opacity;
}
