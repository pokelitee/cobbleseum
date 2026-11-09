// Full-screen impact frame: the rendered image reduced to two colours, inverted, for the
// classic high-contrast "smash" frame on big hits.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec4 ink : source_color = vec4(0.04, 0.03, 0.08, 1.0);
uniform vec4 paper : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform float threshold = 0.5;

void fragment() {
	vec3 colour = texture(screen_texture, SCREEN_UV).rgb;
	float luminance = dot(colour, vec3(0.299, 0.587, 0.114));
	COLOR = luminance > threshold ? ink : paper;
}
