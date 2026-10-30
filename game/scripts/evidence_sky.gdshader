shader_type canvas_item;
// Three tiny sky patches, sampled from the same painting, keep the original
// city pixels intact and separate the formerly baked-in birds from the plate.
void fragment() {
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	vec4 result = texture(TEXTURE, UV);
	vec2 centers[3] = vec2[3](vec2(831.0, 151.0), vec2(910.0, 138.0), vec2(947.0, 135.0));
	for (int i = 0; i < 3; i++) {
		vec2 center = centers[i];
		float mask = 1.0 - smoothstep(10.0, 14.0, distance(px, center));
		// Same scanline preserves the original vertical daylight gradient.
		vec4 left_sky = texture(TEXTURE, vec2(center.x - 17.0, px.y) * TEXTURE_PIXEL_SIZE);
		vec4 right_sky = texture(TEXTURE, vec2(center.x + 17.0, px.y) * TEXTURE_PIXEL_SIZE);
		vec4 sky = mix(left_sky, right_sky, clamp((px.x - center.x + 17.0) / 34.0, 0.0, 1.0));
		result = mix(result, sky, mask);
	}
	COLOR = result;
}
