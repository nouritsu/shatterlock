#version 440
// A soft elliptical glow filling its item, added to what's below (behind the action buttons).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uColor; // premultiplied
};

void main() {
    vec2 p = qt_TexCoord0 * 2.0 - 1.0;
    float g = max(0.0, exp(-dot(p, p) * 3.5) - exp(-3.5));
    fragColor = vec4(uColor.rgb * g, 0.0) * qt_Opacity;
}
