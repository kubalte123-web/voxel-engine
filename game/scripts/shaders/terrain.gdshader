// Teren: tekstura z atlasu, cienie w rogach (AO) i światło z wierzchołków.
// COLOR.r = AO i cieniowanie ściany, COLOR.g = światło nieba (0..1), COLOR.b = światło bloków (0..1).
// Światło nieba mnoży kolor (słońce i niebo oświetlają tylko miejsca, do których dociera niebo),
// światło bloków (pochodnie, lampy) świeci ciepłym kolorem niezależnie od pory dnia.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float min_light = 0.025;
uniform vec3 torch_color : source_color = vec3(1.0, 0.78, 0.5);
uniform float torch_strength = 0.9;
uniform vec3 hand_pos = vec3(0.0, -10000.0, 0.0);
uniform float hand_light = 0.0;
instance uniform vec2 light_override = vec2(-1.0, -1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float curve(float l) {
	// 15 poziomów jak w MC: każdy poziom niżej to 80% jasności
	return pow(0.8, (1.0 - l) * 15.0);
}

void fragment() {
	vec4 tex = texture(atlas, UV);
	float sky = COLOR.g;
	float blk = COLOR.b;
	if (light_override.x >= 0.0) {
		sky = light_override.x;
		blk = light_override.y;
	}
	if (hand_light > 0.0) {
		float d = distance(wpos, hand_pos);
		blk = max(blk, hand_light * clamp(1.0 - d / 14.0, 0.0, 1.0));
	}
	float ao = pow(COLOR.r, 2.2);
	vec3 base = tex.rgb * 0.8 * ao;
	float s = curve(sky);
	float b = blk > 0.01 ? curve(blk) : 0.0;
	ALBEDO = base * max(s, min_light);
	EMISSION = base * torch_color * b * torch_strength;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
