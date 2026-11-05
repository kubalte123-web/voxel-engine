shader_type spatial;
// Części modeli bloków z klocków: kolor z wierzchołków (albo tint dla części z tagiem), oświetlenie
// z mapy światła ustawiane z GDScript (sky = jasność nieba, torch = ciepłe światło bloków).
render_mode cull_back;

uniform vec3 tint = vec3(1.0);
uniform float sky = 1.0;
uniform vec3 torch = vec3(0.0);

void fragment() {
	vec3 c = COLOR.rgb * tint;
	ALBEDO = c * sky;
	EMISSION = c * torch;
	ROUGHNESS = 0.85;
}
