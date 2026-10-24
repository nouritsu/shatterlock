#version 440
// One shard of the frozen screen: a triangle cut from the snapshot, drawn by fx/Shards.qml.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uSrc;   // where the shard came from in the snapshot, uv (x, y, w, h)
    vec2 uA;     // triangle corners in the shard's own 0..1 coordinates
    vec2 uB;
    vec2 uC;
    vec4 uTint;  // premultiplied
    vec4 uRim;   // edge highlight, premultiplied
};

layout(binding = 1) uniform sampler2D uSnapshot;

float side(vec2 p, vec2 a, vec2 b) {
    return (p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x);
}

// Distance from p to the line through a and b, in the shard's 0..1 units.
float edgeDist(vec2 p, vec2 a, vec2 b) {
    return abs(side(p, a, b)) / max(length(b - a), 1e-4);
}

void main() {
    vec2 p = qt_TexCoord0;
    float e0 = side(p, uA, uB);
    float e1 = side(p, uB, uC);
    float e2 = side(p, uC, uA);
    bool inside = (e0 >= 0.0 && e1 >= 0.0 && e2 >= 0.0) || (e0 <= 0.0 && e1 <= 0.0 && e2 <= 0.0);
    if (!inside) {
        fragColor = vec4(0.0);
        return;
    }
    vec4 c = texture(uSnapshot, uSrc.xy + p * uSrc.zw);
    c.rgb = mix(c.rgb, uTint.rgb, 0.2) * 0.8;
    // A lit broken edge, so dark pieces still read against the void.
    float e = min(edgeDist(p, uA, uB), min(edgeDist(p, uB, uC), edgeDist(p, uC, uA)));
    c.rgb += uRim.rgb * (1.0 - smoothstep(0.0, 0.07, e)) * 0.9;
    fragColor = c * qt_Opacity;
}
