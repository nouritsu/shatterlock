#version 440
// Bakes the crack field (see uSdf in prelude.glsl) once per open into a float texture.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 iResolution; // logical px
    vec2 uFrom;       // crack start corner
    vec2 uDir;        // unit direction of the straight diagonal
    vec2 uNormal;     // unit normal, pointing into half B
    float uLength;    // length of the diagonal
    // 129 crack offsets along uNormal at evenly spaced points; element k of a matrix is m[k % 4][k / 4].
    mat4 uV0; mat4 uV1; mat4 uV2; mat4 uV3; mat4 uV4; mat4 uV5; mat4 uV6; mat4 uV7; mat4 uV8;
    // 12 branch segments (x1, y1, x2, y2), unused ones far off-screen, and the spread value at
    // which each one appears.
    mat4 uB0; mat4 uB1; mat4 uB2;
    mat4 uBR;
};

const int N = 128;
const int BRANCHES = 12;

float at(mat4 m, int k) { return m[k % 4][k / 4]; }

float crackV(int i) {
    int m = i / 16, k = i % 16;
    if (m == 0) return at(uV0, k);
    if (m == 1) return at(uV1, k);
    if (m == 2) return at(uV2, k);
    if (m == 3) return at(uV3, k);
    if (m == 4) return at(uV4, k);
    if (m == 5) return at(uV5, k);
    if (m == 6) return at(uV6, k);
    if (m == 7) return at(uV7, k);
    return at(uV8, k);
}

vec4 branch(int i) {
    mat4 m = i < 4 ? uB0 : (i < 8 ? uB1 : uB2);
    int k = (i % 4) * 4;
    return vec4(at(m, k), at(m, k + 1), at(m, k + 2), at(m, k + 3));
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
    return length(p - a - ab * t);
}

void main() {
    vec2 p = qt_TexCoord0 * iResolution;
    float du = uLength / float(N);

    // Side: the crack is a function over the diagonal, so compare against it at p's position.
    float u = dot(p - uFrom, uDir);
    float v = dot(p - uFrom, uNormal);
    float fi = clamp(u / du, 0.0, float(N) - 0.0001);
    int i0 = int(floor(fi));
    float vc = mix(crackV(i0), crackV(i0 + 1), fract(fi));

    // The distance along the normal, |v - vc|, bounds the true distance, and the nearest point
    // can't be further along the diagonal than that, so only nearby segments need checking.
    // Beyond MAX_REACH px the field is only used for faint falloffs; it stays a close bound.
    const float MAX_REACH = 240.0;
    int reach = int(ceil(min(abs(v - vc), MAX_REACH) / du)) + 1;
    int first = max(0, i0 - reach);
    int last = min(N, i0 + reach + 1);
    float d = abs(v - vc);
    vec2 prev = uFrom + uDir * (float(first) * du) + uNormal * crackV(first);
    for (int i = first + 1; i <= last; i++) {
        vec2 cur = uFrom + uDir * (float(i) * du) + uNormal * crackV(i);
        d = min(d, segDist(p, prev, cur));
        prev = cur;
    }
    float signedDist = v >= vc ? d : -d;

    float bd = 1e4;
    float reveal = 2.0;
    for (int i = 0; i < BRANCHES; i++) {
        vec4 s = branch(i);
        float bi = segDist(p, s.xy, s.zw);
        if (bi < bd) {
            bd = bi;
            reveal = at(uBR, i);
        }
    }

    fragColor = vec4(signedDist, clamp(u / uLength, 0.0, 1.0), bd, reveal);
}
