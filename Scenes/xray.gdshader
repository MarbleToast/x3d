shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 0.3);
uniform bool do_emission = false;

// Max contribution per fragment (adjust to taste)
const float MAX_WEIGHT = 0.3;

void fragment() {
    // Base color
    vec3 base_color = albedo.rgb;
    float alpha = albedo.a;

    if (do_emission) {
        base_color *= 1.2;   // simple emission boost
        alpha = 0.9;         // stronger if glowing
    }

    // Weight capped to avoid color blowout
    float weight = clamp(alpha, 0.0, MAX_WEIGHT);

    // Premultiply alpha for accumulation
    ALBEDO = base_color * weight;
    ALPHA = weight;
}