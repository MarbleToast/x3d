shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform float fill_progress: hint_range(0.0, 1.0) = 0.0;
uniform vec3 fill_color: source_color = vec3(1.0, 0.0, 1.0);
uniform float feather: hint_range(0.0, 0.1) = 0.02;

void fragment() {
    vec3 pos = VERTEX;

    float angle = atan(pos.z, pos.x);
    angle = (angle + PI) / (2.0 * PI);

    float alpha = smoothstep(fill_progress, fill_progress - feather, angle);

    ALBEDO = fill_color;
    ALPHA = alpha;
}