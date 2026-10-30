shader_type canvas_item;
uniform float wing_phase = 0.0;
uniform vec2 bird_center = vec2(831.0, 152.0);
void fragment() {
	vec2 local = UV / TEXTURE_PIXEL_SIZE - bird_center;
	// Local sampling deforms only wing pixels. The body's centre stays fixed.
	float wing = smoothstep(1.0, 5.0, abs(local.y));
	local.y /= 1.0 - wing * (0.22 + 0.22 * sin(wing_phase));
	vec4 source = texture(TEXTURE, (bird_center + local) * TEXTURE_PIXEL_SIZE);
	// The original birds are neutral charcoal/brown against saturated blue sky.
	float sky = smoothstep(0.14, 0.29, source.b - source.r);
	COLOR = vec4(source.rgb, source.a * (1.0 - sky));
}
