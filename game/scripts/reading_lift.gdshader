shader_type canvas_item;
uniform float lift_px = 0.0;

void fragment() {
    // Both mechanical hands follow the cover. The bend fades out at the cuffs.
    float across = smoothstep(0.23, 0.35, UV.x) * (1.0 - smoothstep(0.70, 0.76, UV.x));
    float band = smoothstep(0.34, 0.375, UV.y) * (1.0 - smoothstep(0.46, 0.50, UV.y));
    vec2 sample_uv = UV - vec2(0.0, lift_px * across * band * TEXTURE_PIXEL_SIZE.y);
    COLOR = texture(TEXTURE, sample_uv);
}
