shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform vec4 albedo: source_color;

void fragment() {
    ALBEDO = albedo.rgb;
    ALPHA = albedo.a;
}