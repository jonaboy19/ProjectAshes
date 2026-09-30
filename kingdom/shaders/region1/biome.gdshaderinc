// Region 1 biome colour (docs/regions/LOOK_R1.md), shared by shaders/terrain.gdshader and the far horizon.
// The biome map (tools_qa/region1/bake_biome.gd, 16 m/px over the 8 km world) holds
//   R farmland, G heather uplands, B lush river greens, A dry gold meadow.
// Farmland is drawn as a patchwork of fields like the Valencious poster: rotated blocks of 30-70 m
// fields in wheat gold, fresh green, barley cream, ploughed earth and flax blue, with dark hedgerow seams.
// Everything is multiplied into the grass albedo, so textures, seasons and weather still apply on top.

uniform sampler2D region_biome : hint_default_black, filter_linear, repeat_disable;
uniform vec4 region_biome_rect = vec4(-4096.0, -4096.0, 8192.0, 8192.0);

float r1_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec4 r1_biome_sample(vec2 xz) {
	return texture(region_biome, (xz - region_biome_rect.xy) / region_biome_rect.zw);
}

// grass: the grass albedo; dirt: a ploughed-earth albedo; hedge_out: 0..1 hedgerow mask for the caller.
vec3 r1_biome(vec3 grass, vec3 dirt, vec2 xz, vec4 bio, out float hedge_out) {
	vec3 g = grass;
	// Heather: rosy-violet uplands with green left in the gaps.
	g = mix(g, g * vec3(1.02, 0.7, 0.98) + vec3(0.07, 0.0, 0.06), bio.g * 0.75);
	// Lush river and lake greens.
	g = mix(g, g * vec3(0.82, 1.1, 0.78), bio.b * 0.55);
	// Dry gold meadow.
	g = mix(g, g * vec3(1.22, 1.06, 0.55) + vec3(0.03, 0.02, 0.0), bio.a * 0.6);
	hedge_out = 0.0;
	if (bio.r > 0.02) {
		// Blocks of ~220 m each get their own field orientation.
		vec2 blk = floor(xz / 220.0);
		float ang = (r1_hash(blk) - 0.5) * 1.4;
		mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
		vec2 q = rot * xz;
		vec2 size = vec2(34.0 + 18.0 * r1_hash(blk + 3.3), 58.0 + 24.0 * r1_hash(blk + 5.1));
		vec2 cell = floor(q / size);
		vec2 f = fract(q / size);
		float h = r1_hash(cell + blk * 17.0);
		float edge = min(min(f.x, 1.0 - f.x) * size.x, min(f.y, 1.0 - f.y) * size.y);
		vec3 crop;
		float furrow = 0.5 + 0.5 * sin((q.x + q.y * 0.02) * 2.2);
		if (h < 0.3) {
			crop = g * vec3(1.42, 1.12, 0.42) + vec3(0.05, 0.03, 0.0);          // wheat gold
		} else if (h < 0.52) {
			crop = g * vec3(0.9, 1.16, 0.72);                                   // young green
		} else if (h < 0.68) {
			crop = mix(dirt * vec3(1.05, 0.92, 0.82), dirt * 0.8, furrow * 0.6); // ploughed earth
		} else if (h < 0.86) {
			crop = g * vec3(1.3, 1.22, 0.78) + vec3(0.04, 0.04, 0.02);          // barley cream
		} else {
			crop = g * vec3(0.92, 0.95, 1.18) + vec3(0.0, 0.01, 0.05);          // flax blue
		}
		if (h < 0.68 && h >= 0.52) {
			// already striped
		} else {
			crop *= mix(0.92, 1.05, furrow);
		}
		float inside = smoothstep(0.9, 2.2, edge);
		float k = clamp(bio.r * 1.4, 0.0, 1.0);
		g = mix(g, crop, k * inside * 0.85);
		// Hedgerows: a darker green seam between fields.
		hedge_out = k * (1.0 - smoothstep(0.4, 1.2, edge));
		g = mix(g, grass * vec3(0.55, 0.72, 0.45), hedge_out * 0.8);
	}
	return g;
}
