// Powierzchnia cieczy: fale (przesunięcie wierzchołków i zaburzona normalna), prąd przesuwający
// zmarszczki, piana przy brzegach i w płynącej wodzie, kolor zależny od głębokości, odbicie Fresnela.
// Kolor wierzchołka z siatki: r = piana, g = głębokość, b = krawędź fali, a = rodzaj cieczy / 7.
// UV = kierunek prądu (z różnicy wysokości powierzchni).
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform vec4 shallow[8] : source_color;
uniform vec4 deep[8] : source_color;
uniform vec4 foam_color[8] : source_color;
uniform float emission[8];
uniform float wave = 1.0;

varying vec3 wpos;
varying vec4 info;
varying vec2 flow;
varying float top;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	info = COLOR;
	flow = UV;
	top = NORMAL.y;
	if (COLOR.b > 0.5) {
		float t = TIME;
		float h = sin(world.x * 0.7 + t * 1.3) * 0.035 + sin(world.z * 0.9 - t * 1.1) * 0.035
			+ sin((world.x + world.z) * 1.7 + t * 2.1) * 0.015;
		VERTEX.y += (h - 0.05) * wave;
		world.y += (h - 0.05) * wave;
	}
	wpos = world;
}

void fragment() {
	int k = clamp(int(info.a * 7.0 + 0.5), 0, 7);
	float t = TIME;
	vec2 p = wpos.xz - flow * t * 1.6;
	vec3 col = mix(shallow[k].rgb, deep[k].rgb, info.g);
	float a = mix(shallow[k].a, deep[k].a, info.g);
	if (top > 0.5) {
		float dx = cos(p.x * 1.9 + t * 1.7) * 0.12 + cos((p.x + p.y) * 3.3 + t * 2.6) * 0.07 + cos(p.x * 5.1 - t * 3.0) * 0.04;
		float dz = cos(p.y * 2.2 - t * 1.5) * 0.12 + cos((p.x - p.y) * 2.9 + t * 2.2) * 0.07 + cos(p.y * 4.7 + t * 2.8) * 0.04;
		vec3 n = normalize(vec3(-dx * wave, 1.0, -dz * wave));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
		if (!FRONT_FACING) {
			NORMAL = -NORMAL;
		}
	}
	float pat = sin(p.x * 4.0 + t * 1.2) * sin(p.y * 4.3 - t * 0.9) * 0.5 + 0.5;
	float fm = smoothstep(0.35, 0.85, info.r * (0.55 + 0.6 * pat));
	col = mix(col, foam_color[k].rgb, fm);
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col;
	ALPHA = clamp(a + fm * 0.5 + fr * 0.35, 0.0, 1.0);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	EMISSION = col * emission[k];
}
