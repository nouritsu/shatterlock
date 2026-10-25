#version 440
// Wrong-password waves (see RiftWindow.reject): red spreading out from where each orb hit the
// rift's edges until it covers the screen. Drawn at a fraction of the resolution into the texture
// the rift's shaders read as uAlert: r how red, g the wavefronts.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 iResolution; // output size, logical px
    float uElapsed;   // s since the orbs turned red
    float uFade;      // 1 while the waves are up .. 0 gone
    float uCount;     // impacts in use (up to 32)
    float uSpeed;     // how fast the waves run, px/s
    // Impact points as (x, y) pairs, 8 per matrix, and when each wave starts (s); element k of a
    // matrix is m[k % 4][k / 4].
    mat4 uP0; mat4 uP1; mat4 uP2; mat4 uP3;
    mat4 uT0; mat4 uT1;
};

float at(mat4 m, int k) { return m[k % 4][k / 4]; }

vec2 point(int i) {
    mat4 m = i < 8 ? uP0 : (i < 16 ? uP1 : (i < 24 ? uP2 : uP3));
    int k = (i % 8) * 2;
    return vec2(at(m, k), at(m, k + 1));
}

float start(int i) {
    return i < 16 ? at(uT0, i) : at(uT1, i - 16);
}

void main() {
    vec2 p = qt_TexCoord0 * iResolution;
    // The waves merge into one red area; `edge` is how far outside it p is (< 0 inside).
    float edge = 1e5;
    for (int i = 0; i < 32; i++) {
        if (float(i) >= uCount)
            break;
        float r = (uElapsed - start(i)) * uSpeed;
        if (r > 0.0)
            edge = min(edge, length(p - point(i)) - r);
    }
    float red = 1.0 - smoothstep(-120.0, 0.0, edge);
    float front = exp(-abs(edge) / 16.0);
    fragColor = vec4(red * uFade, front * uFade, 0.0, 1.0);
}
