shader_type canvas_item;
// The town's diorama lens (HD-2D look, Vanta's pick): sharp across a band
// in the middle, blurring toward the top and bottom edges like a tilt-shift
// photo, with a soft vignette and a touch of warmth. A screen pass on the
// rendered town, so it runs on the Compatibility renderer.

uniform float focus_center = 0.55;
uniform float focus_half_width = 0.12;
uniform float max_blur_px = 10.0;
uniform float vignette = 0.28;

void fragment() {
	float away = max(abs(UV.y - focus_center) - focus_half_width, 0.0) / (0.5 - focus_half_width);
	float radius = smoothstep(0.0, 1.0, clamp(away, 0.0, 1.0)) * max_blur_px;
	vec3 color = texture(TEXTURE, UV).rgb;
	if (radius > 0.25) {
		vec4 sum = vec4(0.0);
		float weight = 0.0;
		for (int i = -3; i <= 3; i++) {
			for (int j = -3; j <= 3; j++) {
				vec2 offset = vec2(float(i), float(j)) / 3.0 * radius * TEXTURE_PIXEL_SIZE;
				float k = exp(-float(i * i + j * j) / 6.0);
				sum += texture(TEXTURE, UV + offset) * k;
				weight += k;
			}
		}
		color = sum.rgb / weight;
	}
	color *= vec3(1.03, 1.0, 0.95);
	float edge = distance(UV, vec2(0.5, 0.55));
	color *= 1.0 - vignette * smoothstep(0.35, 0.85, edge);
	COLOR = vec4(color, 1.0);
}
