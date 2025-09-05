shader_type canvas_item;

uniform sampler2D accum_tex;

void fragment() {
    vec4 accum = texture(accum_tex, UV);
    float alpha = max(accum.a, 1e-6);
    vec3 final_color = accum.rgb / alpha;
    COLOR = vec4(final_color, clamp(alpha, 0.0, 1.0));
}
