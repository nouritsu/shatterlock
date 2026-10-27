#version 440
// shatterlock-shader: 1
//
// The shatterlock shader contract. A slot shader (background, edge, opening) only defines
//
//     vec4 shade(vec2 uv)   // uv: 0..1 over the output, returns premultiplied RGBA
//
// and is wrapped with this prelude plus a main() by scripts/wrap-shader. Return alpha 0 with
// non-zero colour to add light (additive blending). All distances are in logical pixels.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float iTime;        // seconds since the rift started opening
    vec2 iResolution;   // output size, logical px
    float uProgress;    // 0 closed .. 1 fully open (overshoots slightly past 1)
    float uSpread;      // 0..1 how far the hairline crack has run, corner to corner
    float uLine;        // 0..1 visibility of the hairline crack (spreading, and while sealing shut)
    float uPhase;       // 0 idle, 1 spreading, 2 opening, 3 open, 4 closing, 5 firing,
                        // 6 sealing (lock), 7 locked, 8 unlocking
    float uGap;         // current gap between the halves, px
    vec2 uOffA;         // displacement of half A (top-left for "bl-tr"), px
    vec2 uOffB;         // displacement of half B, px
    vec2 uMouse;        // cursor position, px
    float uHover;       // highlighted action index, -1 when none
    vec4 uAccent;       // theme accent, premultiplied RGBA
    vec4 uVoid;         // theme void colour, premultiplied RGBA
    float uWarn;        // 1 when a custom shader failed to build (the rift shows a red hairline)
    float uObscure;     // lock blur wave: 0 none .. 1 spread over the whole screen
    float uObscureStyle; // 0 void fog, 1 frosted, 2 glass
    vec4 uCrackLine;    // the straight line the crack runs along: a corner it ends in (xy), and
                        // the unit normal pointing into half B (zw)
    float uAlertOn;     // 1 while wrong-password waves are up (see uAlert)
    float uSeam;        // how the crack is drawn: 0 a dark hairline with a bright tip and bevelled
                        // edges, 1 a sweeping line in the accent colour with clean edges
};

layout(binding = 1) uniform sampler2D uSnapshot; // the frozen screen
layout(binding = 2) uniform sampler2D uSdf;      // crack field of the closed screen:
                                                 //   r signed distance to the crack (px, < 0 on half A)
                                                 //   g position along the crack 0..1
                                                 //   b, a unused (0)
layout(binding = 3) uniform sampler2D uSource;   // opening slot: the rift as composited so far
                                                 // (other slots get the snapshot here)
layout(binding = 4) uniform sampler2D uAlert;    // wrong-password waves (screen space): r how red,
                                                 // g the wavefronts

vec2 shatterlockPx; // the pixel being shaded (px), set before shade() runs

vec2 toPx(vec2 uv) { return uv * iResolution; }
vec2 toUv(vec2 px) { return px / iResolution; }

bool onScreen(vec2 px) {
    return all(greaterThanEqual(px, vec2(0.0))) && all(lessThan(px, iResolution));
}

// Crack field of the closed screen at a pixel position.
vec4 crackAt(vec2 px) { return texture(uSdf, toUv(px)); }

// Signed distance to the crack (< 0 on half A) at a point of the closed screen. Past the screen's
// edges the halves carry on: the field is continued from the nearest point on screen along the
// crack's normal, so the broken edges run on without a seam at the border.
float crackSide(vec2 px) {
    vec2 near = clamp(px, vec2(0.5), iResolution - 0.5);
    return crackAt(near).r + dot(px - near, uCrackLine.zw);
}

// A point past the screen's edge, mirrored back in (what the halves show out there).
vec2 mirrorPx(vec2 px) {
    return iResolution - abs(iResolution - abs(px));
}

// Distance from px to the edge of half A (> 0: not on half A) and of half B (> 0: not on half B).
float awayFromA(vec2 px) {
    return crackSide(px - uOffA);
}
float awayFromB(vec2 px) {
    return -crackSide(px - uOffB);
}

// Signed distance to the nearest broken edge: > 0 inside the rift, < 0 over either half.
float riftDist(vec2 uv) {
    vec2 px = toPx(uv);
    return min(awayFromA(px), awayFromB(px));
}

// Rift-local coordinates: x along the crack 0..1, y across the gap -1 (edge A) .. 1 (edge B).
vec2 riftUV(vec2 uv) {
    vec2 px = toPx(uv);
    float dA = awayFromA(px);
    float dB = awayFromB(px);
    float along = crackAt(px - 0.5 * (uOffA + uOffB)).g;
    float across = (dA + dB) > 0.0 ? clamp((dA - dB) / (dA + dB), -1.0, 1.0) : 0.0;
    return vec2(along, across);
}

// Wrong-password waves at the pixel being shaded, and the theme accent there: red wherever a wave
// has reached.
const vec3 ALERT = vec3(1.0, 0.16, 0.2);
vec4 alertHere() { return uAlertOn > 0.5 ? texture(uAlert, toUv(shatterlockPx)) : vec4(0.0); }
vec3 accent() { return mix(uAccent.rgb, ALERT, alertHere().r); }

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

// The lock blur wave runs out from the broken edges. How far it has got (px), and how obscured a
// point that far from its edge is: 1 behind the wavefront, 0 ahead of it.
float obscureFront() { return uObscure * (length(iResolution) + 160.0); }

// How far the screen's farthest point is from the straight line the crack runs along, px.
float farthestFromCrack() {
    vec2 a = abs(vec2(dot(-uCrackLine.xy, uCrackLine.zw), dot(vec2(iResolution.x, 0.0) - uCrackLine.xy, uCrackLine.zw)));
    vec2 b = abs(vec2(dot(vec2(0.0, iResolution.y) - uCrackLine.xy, uCrackLine.zw), dot(iResolution - uCrackLine.xy, uCrackLine.zw)));
    return max(max(a.x, a.y), max(b.x, b.y));
}
float obscureAmount(float edgeDist) {
    return uObscure >= 1.0 ? 1.0 : 1.0 - smoothstep(obscureFront() - 140.0, obscureFront(), edgeDist);
}

// The frozen screen at source position q (px, in its half's own coordinates) whose distance from
// the broken edge is edgeDist, seen through the lock blur wherever the wave has reached.
// uSnapshot must be mipmapped.
vec3 obscuredSnapshot(vec2 q, float edgeDist) {
    float k = obscureAmount(edgeDist);
    if (k <= 0.0)
        return texture(uSnapshot, toUv(q)).rgb;

    vec3 col;
    if (uObscureStyle < 0.5) {
        // Void fog: the picture sinks into dark, accent-tinted fog with slow smoke curling through.
        // While unlocking it streams back into the rift as it clears.
        vec3 remains = textureLod(uSnapshot, toUv(q), 7.0 * k).rgb;
        float back = uPhase > 7.5 && uPhase < 8.5 ? 1.0 - clamp(obscureFront() / farthestFromCrack(), 0.0, 1.0) : 0.0;
        vec2 intoRift = uCrackLine.zw * (crackSide(q) < 0.0 ? 1.0 : -1.0);
        vec2 p = (q - intoRift * 220.0 * back) * 0.0035;
        vec2 drift = vec2(iTime * 0.035, -iTime * 0.022);
        float smoke = fbm(p + drift + 1.6 * fbm(p * 1.7 - drift));
        float wisps = smoothstep(0.42, 0.9, smoke);
        vec3 fog = mix(uVoid.rgb, accent() * 0.32, wisps) + accent() * 0.04;
        col = mix(remains * 0.5, fog * (0.55 + 0.9 * smoke), k);
    } else if (uObscureStyle < 1.5) {
        // Frosted: a wide blur from the mip chain, scattered by noise, with a fixed grain.
        float lod = 6.0 * k;
        float spin = hash12(q) * 6.2832;
        col = vec3(0.0);
        for (int i = 0; i < 4; i++) {
            float a = spin + float(i) * 1.5708;
            vec2 o = vec2(cos(a), sin(a)) * (6.0 + 10.0 * hash12(q + float(i))) * k;
            col += textureLod(uSnapshot, toUv(q + o), lod).rgb;
        }
        col *= 0.25;
        float grey = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(col, vec3(grey), 0.25 * k) * (1.0 - 0.18 * k);
        col += (hash12(floor(q)) - 0.5) * 0.06 * k;
    } else {
        // Glass: rippled, fluted glass bends and softens the picture; glints catch the light.
        vec2 n = vec2(noise2(q * 0.011 + iTime * 0.04), noise2(q * 0.011 + 37.0 - iTime * 0.03)) - 0.5;
        float flute = sin(dot(q, vec2(0.7071)) * 0.06 + n.x * 4.0);
        vec2 o = (n * 70.0 + vec2(flute * 10.0)) * k;
        col = textureLod(uSnapshot, toUv(q + o), 4.5 * k).rgb;
        col = col * (1.0 - 0.1 * k) + pow(max(0.0, flute), 12.0) * 0.18 * k + accent() * 0.06 * k;
    }

    // The wavefront glows as it passes, and so do the fronts of wrong-password waves.
    float ring = uObscure < 1.0 ? exp(-abs(edgeDist - obscureFront()) / 22.0) : 0.0;
    return col + accent() * ring * 0.45 + vec3(ring * 0.15) + ALERT * alertHere().g * 0.45;
}

// The frozen screen as displayed: each half's pixels at their moved position (inside the rift,
// the nearer edge's), obscured where the lock blur has reached.
vec4 snapshot(vec2 uv) {
    vec2 px = toPx(uv);
    vec2 off = awayFromA(px) < awayFromB(px) ? uOffA : uOffB;
    vec2 q = px - off;
    return vec4(obscuredSnapshot(mirrorPx(q), abs(crackSide(q))), 1.0);
}
