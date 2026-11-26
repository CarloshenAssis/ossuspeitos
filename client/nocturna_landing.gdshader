shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D top_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bottom_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 top_tint : source_color = vec3(0.55, 0.42, 0.32);
uniform vec3 bottom_tint : source_color = vec3(0.26, 0.24, 0.22);
uniform float top_scale = 2.2;
uniform float bottom_scale = 1.8;
uniform float top_rough = 0.75;
uniform float bottom_rough = 0.92;

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
	vec3 up = triplanar(top_tex, top_scale) * top_tint;
	vec3 down = triplanar(bottom_tex, bottom_scale) * bottom_tint;
	float face_up = step(0.35, world_n.y);
	ALBEDO = mix(down, up, face_up);
	ROUGHNESS = mix(bottom_rough, top_rough, face_up);
	METALLIC = 0.0;
}
