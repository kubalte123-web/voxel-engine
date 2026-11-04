// Daleki teren: uproszczone kafle z wysokości kolumn, kolor z wierzchołków.
// Fragmenty bliżej niż `inner` od gracza są odrzucane, bo tam stoją prawdziwe chunki.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform vec3 center;
uniform float inner = 100.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (distance(wpos.xz, center.xz) < inner) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
