shader_type canvas_item;

// Fundo do CORREDOR — tradução do `background` do body no style.css:
//   radial-gradient(ellipse at 50% 0%,  rgba(255,122,41,0.08), transparent 55%)
//   radial-gradient(ellipse at 20% 90%, rgba(226, 89,28,0.10), transparent 60%)
//   repeating-linear-gradient(135deg, ...)  -> riscas diagonais ténues
//   linear-gradient(180deg, stone-900, stone-950 60%)

uniform vec3 stone_900 : source_color = vec3(0.086, 0.075, 0.059);
uniform vec3 stone_950 : source_color = vec3(0.051, 0.043, 0.031);
uniform vec3 glow_top : source_color = vec3(1.0, 0.478, 0.161);
uniform vec3 glow_bottom : source_color = vec3(0.886, 0.349, 0.110);

uniform float glow_top_alpha = 0.08;
uniform float glow_bottom_alpha = 0.10;
uniform float stripe_alpha = 0.015;

// Proporção do ecrã, para as elipses não ficarem esticadas.
uniform vec2 viewport_size = vec2(1280.0, 800.0);

void fragment() {
	vec2 uv = UV;

	// linear-gradient(180deg, stone-900, stone-950 60%)
	vec3 col = mix(stone_900, stone_950, clamp(uv.y / 0.6, 0.0, 1.0));

	float aspect = viewport_size.x / max(viewport_size.y, 1.0);

	// Elipse superior ao centro (50% 0%), a desvanecer até 55%
	vec2 d_top = vec2((uv.x - 0.5) * aspect, uv.y - 0.0);
	float f_top = 1.0 - smoothstep(0.0, 0.55 * aspect, length(d_top));
	col += glow_top * (glow_top_alpha * f_top);

	// Elipse inferior esquerda (20% 90%), a desvanecer até 60%
	vec2 d_bot = vec2((uv.x - 0.2) * aspect, uv.y - 0.9);
	float f_bot = 1.0 - smoothstep(0.0, 0.60 * aspect, length(d_bot));
	col += glow_bottom * (glow_bottom_alpha * f_bot);

	// Riscas diagonais a 135°, 2px opacas em cada 6px
	vec2 px = uv * viewport_size;
	float diag = (px.x - px.y) * 0.7071;
	float stripe = step(mod(diag, 6.0), 2.0);
	col += vec3(1.0) * (stripe_alpha * stripe);

	COLOR = vec4(col, 1.0);
}
