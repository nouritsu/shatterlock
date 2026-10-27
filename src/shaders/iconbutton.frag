#version 440
// A Material icon button's shapes, centred in its item: the tonal disc, the focus ring around it
// (3 px, 2 px out) and, while it is held, a determinate progress ring further out: a 4 px arc
// with round caps from the top, clockwise, and the track for the rest, with gaps between them.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;        // item size, px
    float uRadius;     // the disc's radius, px
    vec4 uContainer;   // premultiplied
    vec4 uFocusColor;  // premultiplied
    float uFocus;      // 0..1 focus ring visibility
    vec4 uArcColor;    // premultiplied
    vec4 uTrackColor;  // premultiplied
    float uArc;        // 0..1 how far the progress ring has filled
    float uRing;       // 0..1 progress ring visibility
};

const float TAU = 6.28318531;

// Coverage of a radial band [inner, outer], antialiased over a pixel.
float band(float r, float inner, float outer) {
    return clamp(r - inner + 0.5, 0.0, 1.0) * clamp(outer - r + 0.5, 0.0, 1.0);
}

// Coverage of a stroke `width` px wide along the circle of radius `radius`, clockwise from
// fraction `a` to `b` of a turn (0 at the top), with round caps.
float arc(vec2 p, float radius, float width, float a, float b) {
    if (b <= a)
        return 0.0;
    float f = atan(p.x, -p.y) / TAU;
    f = f < 0.0 ? f + 1.0 : f;
    float d;
    if (f >= a && f <= b) {
        d = abs(length(p) - radius);
    } else {
        vec2 pa = radius * vec2(sin(a * TAU), -cos(a * TAU));
        vec2 pb = radius * vec2(sin(b * TAU), -cos(b * TAU));
        d = min(length(p - pa), length(p - pb));
    }
    return clamp(width * 0.5 - d + 0.5, 0.0, 1.0);
}

vec4 over(vec4 dst, vec4 src) {
    return src + dst * (1.0 - src.a);
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * uSize;
    float r = length(p);

    vec4 col = uContainer * clamp(uRadius - r + 0.5, 0.0, 1.0);
    col = over(col, uFocusColor * band(r, uRadius + 2.0, uRadius + 5.0) * uFocus);

    if (uRing > 0.0) {
        float ringRadius = uRadius + 8.0;
        float stroke = 4.0;
        // Caps eat into the gaps: 4 px of clear space between the arc and the track.
        float gap = (4.0 + stroke) / (TAU * ringRadius);
        float filled = clamp(uArc, 0.0, 1.0);
        float track = arc(p, ringRadius, stroke, filled > 0.0 ? filled + gap : 0.0, filled > 0.0 ? 1.0 - gap : 1.0);
        float filledArc = filled > 0.002 ? arc(p, ringRadius, stroke, 0.0, filled) : 0.0;
        col = over(col, uTrackColor * track * uRing);
        col = over(col, uArcColor * filledArc * uRing);
    }

    fragColor = col * qt_Opacity;
}
