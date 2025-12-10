shader_type spatial;

render_mode unshaded, depth_draw_always, alpha_to_coverage;

uniform vec4 albedo_colour: source_color;
uniform vec4 wireframe_colour: source_color;
uniform float line_width: hint_range(0.0, 15.0) = 1.0;
uniform bool filtered = false;

const vec3 vectors[3] = {
	vec3(1.0, 0.0, 0.0),
	vec3(0.0, 1.0, 0.0),
	vec3(0.0, 0.0, 1.0)
};

varying vec3 bary_coord;

void vertex()
{
	bary_coord = vectors[VERTEX_ID % 3];
}

void fragment() {
	vec3 d_bary_coord_x = dFdx(bary_coord);
	vec3 d_bary_coord_y = dFdy(bary_coord);
	vec3 d_bary_coord = sqrt(d_bary_coord_x*d_bary_coord_x + d_bary_coord_y*d_bary_coord_y);

	vec3 remap = smoothstep(
		vec3(0.0),
		d_bary_coord * line_width,
		bary_coord
	);
	
	remap = filtered ? remap : step(0.5, remap);

	float closest_edge = min(min(remap.x, remap.y), remap.z);

	ALBEDO = mix(wireframe_colour, albedo_colour, closest_edge).xyz;
	ALPHA = mix(1.0, albedo_colour.a, closest_edge);
}