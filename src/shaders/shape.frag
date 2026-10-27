#version 440
// A filled Material shape centred in its item: one of the Expressive shapes, or a blend of two
// (their distance fields mixed), so any shape can morph into any other.
//
//  0 circle      1 square      2 pill       3 triangle    4 diamond     5 pentagon
//  6 clover      7 cookie (6)  8 cookie (9) 9 sunny      10 soft burst 11 cookie (4)
// 12 oval

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uColor;    // premultiplied
    vec2 uSize;     // item size, px
    float uRadius;  // the shape's radius, px
    float uShapeA;
    float uShapeB;
    float uMix;     // 0 shape A .. 1 shape B
    float uSpin;    // turn, radians
};

const float PI = 3.14159265;

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdTriangle(vec2 p, float r) {
    const float k = 1.7320508;
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0)
        p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

float sdRhombus(vec2 p, vec2 b) {
    p = abs(p);
    float h = clamp((b.x * (b.x - 2.0 * p.x) - b.y * (b.y - 2.0 * p.y)) / dot(b, b), -1.0, 1.0);
    float d = length(p - 0.5 * b * vec2(1.0 - h, 1.0 + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

float sdPentagon(vec2 p, float r) {
    const vec3 k = vec3(0.809016994, 0.587785252, 0.726542528);
    p.x = abs(p.x);
    p -= 2.0 * min(dot(vec2(-k.x, k.y), p), 0.0) * vec2(-k.x, k.y);
    p -= 2.0 * min(dot(vec2(k.x, k.y), p), 0.0) * vec2(k.x, k.y);
    p -= vec2(clamp(p.x, -r * k.z, r * k.z), r);
    return length(p) * sign(p.y);
}

// Shapes given by their radius at each angle.
float polarRadius(int i, float a) {
    if (i == 6)
        return 0.56 + 0.44 * pow(abs(cos(2.0 * a)), 0.7);
    if (i == 7)
        return 0.9 + 0.1 * cos(6.0 * a);
    if (i == 8)
        return 0.92 + 0.08 * cos(9.0 * a);
    if (i == 9)
        return 0.78 + 0.22 * pow(0.5 + 0.5 * cos(8.0 * a), 2.0);
    if (i == 10)
        return 0.85 + 0.15 * pow(0.5 + 0.5 * cos(12.0 * a), 1.5);
    return 0.86 + 0.14 * cos(4.0 * a);
}

float sdPolar(int i, vec2 p) {
    float a = atan(p.y, p.x);
    float r = polarRadius(i, a);
    float dr = (polarRadius(i, a + 0.01) - polarRadius(i, a - 0.01)) / 0.02;
    float len = length(p);
    return (len - r) / sqrt(1.0 + dr * dr / max(len * len, 1e-4));
}

// Signed distance to shape i, in units of its radius (y points down, so flip what points up).
float sdShape(int i, vec2 p) {
    if (i == 0)
        return length(p) - 1.0;
    if (i == 1)
        return sdRoundBox(p, vec2(0.84), 0.3);
    if (i == 2)
        return length(p - vec2(clamp(p.x, -0.45, 0.45), 0.0)) - 0.58;
    if (i == 3)
        return sdTriangle(vec2(p.x, -p.y - 0.12), 0.9) - 0.14;
    if (i == 4)
        return sdRhombus(p, vec2(0.86, 1.04)) - 0.08;
    if (i == 5)
        return sdPentagon(vec2(p.x, -p.y + 0.06), 0.72) - 0.16;
    if (i == 12)
        return (length(p / vec2(1.0, 0.72)) - 1.0) * 0.72;
    return sdPolar(i, p);
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * uSize / uRadius;
    float c = cos(uSpin), s = sin(uSpin);
    p = mat2(c, s, -s, c) * p;
    float d = mix(sdShape(int(uShapeA + 0.5), p), sdShape(int(uShapeB + 0.5), p), clamp(uMix, 0.0, 1.0));
    float alpha = clamp(0.5 - d * uRadius, 0.0, 1.0);
    fragColor = uColor * alpha * qt_Opacity;
}
