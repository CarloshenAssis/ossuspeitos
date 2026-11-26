shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D plaster : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D panel : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 plaster_tint : source_color = vec3(0.52, 0.46, 0.40);
uniform vec3 panel_tint : source_color = vec3(0.55, 0.42, 0.32);
uniform float plaster_scale = 3.6;
uniform float panel_scale = 1.6;
uniform float wainscot_height = 1.12;
uniform float wainscot_cap = 0.07;
uniform float roughness_value = 0.72;
uniform float floor_y = 0.0;

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(sampler2D tex, float scale) {
	vec3 n = abs(world_n);
	n = n / max(n.x + n.y + n.z, 0.0001);
	vec3 p = world_pos / scale;
	return texture(tex, p.yz).rgb * n.x
		+ texture(tex, p.xz).rgb * n.y
		+ texture(tex, p.xy).rgb * n.z;
}

void fragment() {
	vec3 plaster_c = triplanar(plaster, plaster_scale) * plaster_tint;
	vec3 panel_c = triplanar(panel, panel_scale) * panel_tint;
	float h = world_pos.y - floor_y;
	float mixw = 1.0 - smoothstep(wainscot_height, wainscot_height + wainscot_cap, h);
	ALBEDO = mix(plaster_c, panel_c, mixw);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
