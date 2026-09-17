shader_type canvas_item;
render_mode unshaded;

// The host supplies the palette, aspect and reduced-motion speed.
uniform vec4 top_color : source_color = vec4(0.165, 0.118, 0.161, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.063, 0.059, 0.098, 1.0);
uniform vec4 glow_color : source_color = vec4(0.929, 0.745, 0.514, 1.0);
uniform vec2 aspect = vec2(1.0);
uniform float speed : hint_range(0.0, 1.0) = 0.04;

void fragment() {
	vec2 p = (UV - 0.5) * aspect;
	vec3 ink = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, UV.y));
	vec2 board = vec2(p.x + p.y, p.y - p.x) * 9.0;
	float checker = mod(floor(board.x) + floor(board.y), 2.0);
	float edge = smoothstep(0.15, 0.8, length(p));
	ink += glow_color.rgb * checker * edge * 0.018;
	float lamp = exp(-dot(p - vec2(-0.4, -0.35), p - vec2(-0.4, -0.35)) * 3.0);
	ink += glow_color.rgb * lamp * (0.022 + sin(TIME * speed) * 0.004);
	vec2 rim = abs(p) - (aspect * 0.5 - 0.035);
	float line = abs(max(rim.x, rim.y));
	ink += glow_color.rgb * (1.0 - smoothstep(0.001, 0.003, line)) * 0.10;
	ink *= 1.0 - smoothstep(0.4, 1.4, length(p)) * 0.25;
	COLOR = vec4(ink, 1.0);
}
