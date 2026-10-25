// An action button drawing energy out of the rift: while it is held, filaments of light run from
// both broken edges into it and the edges brighten where they leave, over a wider stretch the
// longer it is held. A press sends a ring of light from the button out to the edges.

vec4 shade(vec2 uv) {
    float charge = uEnergy.z;
    float pulse = uEnergy.w;
    if (charge <= 0.0 && pulse <= 0.0)
        return vec4(0.0);

    // Button-local coordinates: x along the rift, y across it (px).
    vec2 px = toPx(uv);
    vec2 n = uCrackLine.zw;
    vec2 dir = vec2(n.y, -n.x);
    vec2 rel = px - uEnergy.xy;
    float x = dot(rel, dir);
    if (abs(x) > 480.0)
        return vec4(0.0);
    float y = dot(rel, n);
    float d = riftDist(uv); // > 0 inside the rift
    vec3 col = vec3(0.0);

    if (charge > 0.0) {
        float k = pow(charge, 0.7);
        // How far along each edge energy is drawn from.
        float reach = 40.0 + 230.0 * charge;

        // The edges light up where the energy leaves them.
        float along = exp(-pow(x / reach, 2.0));
        float rim = exp(-abs(d) / 1.8) * along;
        float seep = d > 0.0 ? exp(-d / 10.0) * along : 0.0;
        col += (accent() * (1.3 * rim + 0.45 * seep) + vec3(0.5) * rim) * k;

        // Filaments: curves from points on the edges into the button, x = x0 * s^1.6, where s runs
        // 1 at an edge to 0 at the middle. Light runs down each one, faster as the charge builds.
        if (d > 0.0) {
            float s = abs(riftUV(uv).y);
            float bend = pow(max(s, 0.02), 1.6);
            float x0 = x / bend;
            const float lane = 22.0;
            float li = floor(x0 / lane + 0.5);
            float side = y < 0.0 ? 0.0 : 1.0;
            float h = hash12(vec2(li, side));
            float laneX = (li + 0.6 * (h - 0.5)) * lane;
            float live = step(abs(laneX), reach) * step(h, 0.3 + 0.5 * charge);
            float dx = abs(x0 - laneX) * bend; // px from the filament
            float line = exp(-dx / 0.7);
            float speed = 1.2 + 3.5 * charge;
            float run = fract(s * 1.6 + iTime * speed * (0.7 + 0.6 * h) + h * 7.0);
            float spark = 0.1 + 2.2 * pow(1.0 - run, 9.0);
            float fade = smoothstep(0.12, 0.45, s) * (1.0 - 0.4 * s);
            col += (accent() * 0.9 + vec3(0.35)) * line * spark * fade * live * k;
        }
    }

    if (pulse > 0.0) {
        // A ring runs out from the button; where it meets the edges they flash.
        float radius = 30.0 + pulse * 260.0;
        float r = length(vec2(x, y * 1.15));
        float left = pow(1.0 - pulse, 1.5);
        float ring = exp(-abs(r - radius) / 5.0) * smoothstep(-3.0, 2.0, d);
        float flash = exp(-abs(d) / 1.6) * exp(-abs(r - radius) / 30.0);
        col += (accent() * 1.1 + vec3(0.35)) * (1.4 * ring + 1.8 * flash) * left;
    }
    return vec4(col, 0.0); // additive
}
