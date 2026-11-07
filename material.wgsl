// Nimbe : la lumière et les matières du terrain.

override shadows: bool = true;
override shadow_softness: f32 = 0.6;
override sun_strength: f32 = 1.0;
override ambient_strength: f32 = 1.0;
override torch_warmth: f32 = 0.7;
override cave_light: f32 = 1.0;
override colored_lights: bool = true;
override reflections: bool = true;
override water_clarity: f32 = 0.6;
override water_waves: f32 = 1.0;
override caustics: bool = true;
override sun_glint: f32 = 1.0;
override water_style: u32 = 0u;
override relief: f32 = 0.5;
override pbr: bool = true;
override subsurface: f32 = 0.8;
override rain_puddles: f32 = 0.8;

struct ShadowResult {
    // La lumière qui arrive au point, teintée par ce qu'elle a traversé.
    light: vec3<f32>,
    // 1 si le point se trouve sous l'eau par rapport à l'astre.
    underwater: f32,
    // La longueur d'eau, en blocs, que la lumière a traversée pour arriver au point.
    water_path: f32,
}

// Ce que l'eau absorbe par bloc traversé, pour le rouge, le vert et le bleu.
fn water_density() -> vec3<f32> {
    return select(
        mix(vec3<f32>(0.55, 0.17, 0.11), vec3<f32>(0.19, 0.050, 0.034), water_clarity),
        mix(vec3<f32>(0.70, 0.15, 0.19), vec3<f32>(0.30, 0.045, 0.066), water_clarity),
        water_style == 0u);
}

// La taille, en blocs, d'un texel de la carte d'ombres au point `position`. La carte est plus
// fine près du joueur (sa distorsion la resserre au centre), donc le décalage anti-acné suit.
fn shadow_texel_blocks(position: vec3<f32>) -> f32 {
    let clip = frame.shadow_view_proj * vec4<f32>(position, 1.0);
    let k = frame.shadow_distortion;
    let spread = (length(clip.xy) * k + 1.0 - k) / max(1.0 - k, 0.05);
    return max(frame.shadow_center_texel, 0.002) * spread * spread;
}

// L'ombre de l'astre, filtrée par une grille fixe de 3×3 lectures pondérées en tente. Chaque
// lecture est déjà une comparaison bilinéaire : les bords sont nets, lisses et stables, sans
// grain ni motif qui glisse à l'écran.
// `tinted` : la lumière peut traverser l'eau ou le verre avant d'arriver. Une surface
// translucide (l'eau elle-même, une vitre) lit seulement les blocs solides, pour ne jamais se
// faire de l'ombre à elle-même.
fn sample_shadow(position: vec3<f32>, normal: vec3<f32>, foliage: bool, tinted: bool) -> ShadowResult {
    var result = ShadowResult(vec3<f32>(1.0), 0.0, 0.0);
    if !shadows || frame.has_shadow != 1u {
        return result;
    }
    let distance = length(position);
    let edge = frame.shadow_distance * 0.92;
    let outside = smoothstep(edge * 0.82, edge, distance);
    if outside >= 1.0 {
        return result;
    }

    let toward = frame.light_direction;
    let texel = shadow_texel_blocks(position);
    // Le filtre lit jusqu'à `reach` texels du point (sa grille, plus la lecture bilinéaire). Sur
    // une surface inclinée par rapport à la lumière, les texels voisins sont plus proches de
    // l'astre qu'elle, d'autant plus que l'angle est rasant : sans marge, la surface s'ombre
    // elle-même en fines rayures (l'acné). On la décale donc le long de sa normale de
    // reach × sin(angle) texels, ce qui crée exactement la marge nécessaire, et d'un demi-texel
    // vers l'astre. Cela reste sous le dixième de bloc : l'ombre ne se détache pas des objets.
    let spacing_texels = 0.45 + shadow_softness * 0.7;
    let reach = spacing_texels + 1.0;
    let cosine = clamp(dot(normal, toward), 0.0, 1.0);
    let sine = sqrt(1.0 - cosine * cosine);
    var offset = normal * texel * (0.6 + reach * sine * 1.3) + toward * texel * 0.6;
    if foliage {
        // Les plantes n'ont pas d'épaisseur : on les décale seulement vers la lumière.
        offset = toward * texel * (1.0 + reach);
    }
    let centre = shadow_position(position + offset);

    let spacing = spacing_texels / max(frame.shadow_resolution, 1.0);
    var solid = 0.0;
    var clear = 0.0;
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let weight = f32((2 - abs(x)) * (2 - abs(y)));
            let at = centre.xy + vec2<f32>(f32(x), f32(y)) * spacing;
            solid += textureSampleCompareLevel(shadow_map, shadow_sampler, at, centre.z) * weight;
            if tinted {
                clear += textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, at, centre.z) * weight;
            }
        }
    }
    solid /= 16.0;
    if !tinted {
        result.light = mix(vec3<f32>(solid), vec3<f32>(1.0), outside);
        return result;
    }
    clear /= 16.0;

    // La lumière a traversé de l'eau ou du verre coloré : on reprend sa couleur.
    var tint = vec3<f32>(1.0);
    let filtered = max(solid - clear, 0.0);
    if filtered > 0.01 {
        let size = vec2<f32>(textureDimensions(shadow_color));
        let at = vec2<i32>(clamp(centre.xy * size, vec2<f32>(0.0), size - 1.0));
        let through = textureLoad(shadow_color, at, 0);
        let water = through.a >= 0.995;
        result.underwater = select(0.0, filtered / max(solid, 0.01), water);
        if water {
            // La carte translucide garde la profondeur de la surface de l'eau vue de l'astre :
            // l'écart avec celle du point donne l'épaisseur d'eau traversée. La projection est
            // orthographique, donc cet écart se convertit en blocs par un simple facteur.
            let surface_size = vec2<f32>(textureDimensions(shadow_map_translucent));
            let surface_at = vec2<i32>(clamp(centre.xy * surface_size, vec2<f32>(0.0), surface_size - 1.0));
            let surface_depth = textureLoad(shadow_map_translucent, surface_at, 0);
            let m = frame.shadow_view_proj;
            let depth_per_block = length(vec3<f32>(m[0].z, m[1].z, m[2].z));
            result.water_path = clamp((centre.z - surface_depth) / max(depth_per_block, 1e-6), 0.0, 64.0);
        }
        // L'eau colore la lumière par absorption (voir `terrain`) : sa texture n'ajoute qu'une nuance.
        let density = select(through.a, select(0.55, 0.2, water_style == 0u), water);
        tint = mix(vec3<f32>(1.0), to_linear(through.rgb), density);
    }
    result.light = mix(clear + filtered * tint, vec3<f32>(1.0), outside);
    return result;
}

// L'ombre des nuages, projetée à la verticale. Elle ne dépend donc pas de l'angle de l'astre et
// reste immobile quand un serveur recale l'heure du jour, chaque seconde.
fn cloud_shadow(position: vec3<f32>) -> f32 {
    if frame.dimension != 0 {
        return 1.0;
    }
    let world = position + frame.camera_position;
    let cover = cloud_cover_filtered(world.xz, 18.0);
    return 1.0 - cover * 0.5;
}

// Une onde de la surface vue par la lumière qui descend vers le fond, réduite à sa courbure
// (d²h/dx², d²h/dz², d²h/dxdz), calculée exactement : c'est elle qui concentre ou disperse les
// rayons. `d` : sa direction, `length_blocks` : sa longueur d'onde, `height` : sa hauteur relative.
fn caustic_wave(p: vec2<f32>, d: vec2<f32>, length_blocks: f32, height: f32, speed: f32) -> vec3<f32> {
    let k = 6.2831853 / length_blocks;
    let phase = dot(p, d) * k + frame.time * speed * k * 0.35 + length_blocks * 3.1;
    let s = -sin(phase) * height * length_blocks * k * k;
    return s * vec3<f32>(d.x * d.x, d.y * d.y, d.x * d.y);
}

// Dix ondes de directions bien réparties (des pas d'angle d'or), sur des coordonnées tordues à
// deux échelles : des ondulations lentes, et une dérive à très grande échelle tirée de la texture
// de bruit. Aucune direction ne domine et le motif ne se répète nulle part. `surface` : le point
// de la surface, en blocs.
fn caustic_curvature(surface: vec2<f32>) -> vec3<f32> {
    let t = frame.time;
    let xz = surface * 2.0;
    let drift = vec2<f32>(
        noise_at(surface / 150.0 + vec2<f32>(0.31, 0.17) + t * 0.0011).a,
        noise_at(surface / 150.0 + vec2<f32>(0.71, 0.53) - t * 0.0009).a) - 0.5;
    let warp = vec2<f32>(
        sin(xz.y * 0.37 + t * 0.23) * 0.5 + sin(xz.y * 0.13 - t * 0.11 + 1.3) * 0.9,
        sin(xz.x * 0.41 - t * 0.19) * 0.5 + sin(xz.x * 0.17 + t * 0.13 + 0.4) * 0.9) + drift * 4.0;
    let p = xz + warp;
    var c = caustic_wave(p, vec2<f32>(0.9553, 0.2955), 3.1, 1.0, 0.50);
    c += caustic_wave(p, vec2<f32>(-0.9041, 0.4274), 2.5, 0.90, 0.58);
    c += caustic_wave(p, vec2<f32>(0.3779, -0.9258), 2.0, 0.75, 0.66);
    c += caustic_wave(p, vec2<f32>(0.3467, 0.9380), 1.7, 0.60, 0.74);
    c += caustic_wave(p, vec2<f32>(-0.8893, -0.4574), 1.4, 0.45, 0.82);
    c += caustic_wave(p, vec2<f32>(0.9647, -0.2634), 1.15, 0.30, 0.90);
    c += caustic_wave(p, vec2<f32>(-0.5334, 0.8459), 2.8, 0.80, 0.53);
    c += caustic_wave(p, vec2<f32>(-0.1781, -0.9840), 1.9, 0.60, 0.70);
    c += caustic_wave(p, vec2<f32>(0.7960, 0.6053), 1.3, 0.40, 0.85);
    c += caustic_wave(p, vec2<f32>(-0.9958, 0.0914), 0.95, 0.28, 0.97);
    return c * (0.073 * water_waves);
}

// La part de lumière que reçoit le fond, pour une distance focale donnée. Chaque rayon est dévié
// selon la pente de la surface ; le faisceau qui couvrait une aire unité en couvre |det J|, J
// étant la façon dont la surface le déforme. Là où det J passe par zéro, les rayons se croisent :
// ce sont les lignes vives du réseau. `soft` borne cette concentration (et l'adoucit au loin).
fn caustic_gathered(c: vec3<f32>, focal: f32, soft: f32) -> f32 {
    let det = (1.0 + focal * c.x) * (1.0 + focal * c.y) - focal * focal * c.z * c.z;
    let g = 1.0 / max(abs(det), soft);
    return g / (1.0 + 0.06 * g);
}

// Les reflets de lumière sur le fond de l'eau, `depth` blocs sous la surface : un multiplicateur
// de la lumière directe. En eau très peu profonde, les rayons n'ont pas le temps de converger et
// le fond ne reçoit que de larges taches douces ; dès un bloc, ils dessinent le réseau de lignes
// fines qu'on voit au fond d'une piscine ou d'un lagon. Le bleu, plus réfracté
// que le rouge, converge un peu plus tôt : les lignes gardent une très légère frange colorée.
// Plus bas, la lumière diffusée par l'eau efface peu à peu le motif.
fn caustic_light(world: vec3<f32>, distance: f32, depth: f32) -> vec3<f32> {
    let toward = frame.light_direction;
    let fade = (1.0 - smoothstep(20.0, 48.0, distance)) * smoothstep(0.05, 0.5, depth)
        * exp(-max(depth - 4.0, 0.0) * 0.22) * smoothstep(0.08, 0.35, toward.y);
    if fade <= 0.0 {
        return vec3<f32>(1.0);
    }
    // Le motif se forme à la surface, au-dessus du point, dans la direction de l'astre.
    let surface = world.xz + toward.xz / max(toward.y, 0.25) * depth;
    let c = caustic_curvature(surface);
    // Les rayons convergent vite : dès un bloc d'eau, le réseau est formé. D'un endroit à l'autre,
    // la houle est plus ou moins creusée : ici des lignes vives et serrées, là de larges reflets
    // doux, et ces zones dérivent lentement.
    let zone = noise_at(surface / 90.0 + vec2<f32>(0.43, 0.29) + frame.time * vec2<f32>(0.0015, -0.0011)).a;
    let swell = 0.55 + 0.8 * clamp((zone - 0.25) * 2.0, 0.0, 1.0);
    let focal = 0.675 * (1.0 - exp(-depth)) * swell;
    let soft = 0.04 + distance * 0.006;
    let gathered = vec3<f32>(
        caustic_gathered(c, focal * 0.985, soft),
        caustic_gathered(c, focal, soft),
        caustic_gathered(c, focal * 1.015, soft));
    // La lumière n'est que redistribuée : on ramène sa moyenne à 1 (mesurée pour ces ondes, selon
    // la focale). Une part reste uniforme, celle que l'eau diffuse en chemin : le creux des
    // mailles n'est jamais noir.
    let formed = 1.4 * smoothstep(0.15, 0.5, focal) - 0.6 * smoothstep(0.6, 0.95, focal);
    let mean = 1.0 + formed * clamp(1.0 - (soft - 0.04) * 6.8, 0.35, 1.0);
    return mix(vec3<f32>(1.0), 0.5 + 0.5 * gathered / mean, fade);
}

fn detail_normal(input: MaterialInput, geometric: vec3<f32>) -> vec3<f32> {
    let t = input.tangent.xyz;
    let b = cross(geometric, t) * input.tangent.w;
    if pbr && block_pbr_maps() {
        let n = block_normal_map(input.uv);
        let xy = n.xy * 2.0 - 1.0;
        let z = sqrt(max(1.0 - dot(xy, xy), 0.0));
        return normalize(t * xy.x + b * xy.y + geometric * z);
    }
    if relief <= 0.0 || block_texture_lod() > 1.5 || input.translucent {
        return geometric;
    }
    let step_size = 1.0 / block_texture_size();
    let centre = luma(block_texture(input.uv).rgb);
    let right = luma(block_texture(input.uv + vec2<f32>(step_size.x, 0.0)).rgb);
    let down = luma(block_texture(input.uv + vec2<f32>(0.0, step_size.y)).rgb);
    let slope = vec2<f32>(centre - right, centre - down) * relief * 2.2;
    let fade = 1.0 - smoothstep(0.5, 1.5, block_texture_lod());
    return normalize(geometric + (t * slope.x + b * slope.y) * fade);
}

fn block_light_tone(input: MaterialInput) -> vec3<f32> {
    let warm = mix(vec3<f32>(1.0, 0.86, 0.68), vec3<f32>(1.0, 0.62, 0.30), torch_warmth);
    if !colored_lights {
        return warm;
    }
    let source = block_light_color(input.position);
    let reach = clamp(source.a * 1.4, 0.0, 1.0);
    return mix(warm, to_linear(source.rgb), reach);
}

fn dimension_ambient() -> vec3<f32> {
    if frame.dimension == -1 {
        return vec3<f32>(0.26, 0.105, 0.070);
    }
    if frame.dimension == 1 {
        return vec3<f32>(0.115, 0.075, 0.20);
    }
    return vec3<f32>(0.08);
}

fn specular_term(normal: vec3<f32>, view: vec3<f32>, light: vec3<f32>, smoothness: f32) -> f32 {
    if smoothness <= 0.01 {
        return 0.0;
    }
    let halfway = normalize(view + light);
    let power = mix(14.0, 950.0, smoothness * smoothness);
    let peak = pow(max(dot(normal, halfway), 0.0), power);
    let normalize_energy = (power + 8.0) / 80.0;
    return peak * min(normalize_energy, 6.0) * smoothstep(0.0, 0.12, dot(normal, light));
}

fn terrain(input: MaterialInput) -> vec4<f32> {
    let surface_id = input.material;
    let foliage = surface_id >= MAT_LEAVES && surface_id <= MAT_KELP;
    let distance = length(input.position);
    let view = -input.position / max(distance, 0.001);
    let world = input.position + frame.camera_position;
    let overworld = frame.dimension == 0;

    var normal = input.normal;
    if !foliage {
        normal = detail_normal(input, input.normal);
    }

    var albedo = to_linear(input.albedo.rgb * input.tint.rgb);
    var smoothness = 0.0;
    var reflectance = 0.04;
    var metal = false;
    if surface_id == MAT_METAL {
        smoothness = 0.68;
        reflectance = 0.55;
        metal = true;
    } else if surface_id == MAT_POLISHED {
        smoothness = 0.46;
    } else if surface_id == MAT_CRYSTAL {
        smoothness = 0.88;
    }
    var pack_emission = 0.0;
    if pbr && block_pbr_maps() {
        let s = block_specular_map(input.uv);
        if s.r > 0.0 || s.g > 0.0 {
            smoothness = s.r;
            metal = s.g > 229.5 / 255.0;
            reflectance = select(max(s.g, 0.02), 0.7, metal);
        }
        if s.a < 0.999 {
            pack_emission = s.a * 255.0 / 254.0;
        }
    }

    // Sol mouillé : là où la pluie tombe et sur les faces tournées vers le ciel.
    let exposed = smoothstep(0.82, 0.97, input.light.y);
    let facing_up = smoothstep(0.55, 0.92, input.normal.y);
    var wet = frame.wetness * exposed * rain_puddles;
    if frame.precipitation != 1u {
        wet = 0.0;
    }
    if wet > 0.001 && !foliage {
        let spots = noise_at(world.xz / 11.0 + vec2<f32>(0.13, 0.57)).g;
        let puddle = smoothstep(0.42, 0.62, spots) * facing_up;
        let soak = wet * (0.42 + 0.58 * puddle);
        albedo *= mix(vec3<f32>(1.0), vec3<f32>(0.58), soak);
        smoothness = max(smoothness, soak * mix(0.58, 0.94, puddle));
        if puddle > 0.5 {
            normal = normalize(mix(normal, input.normal, puddle * wet));
        }
    }

    // La lumière directe.
    var direct = vec3<f32>(0.0);
    var visible = vec3<f32>(0.0);
    var through_foliage = vec3<f32>(0.0);
    if overworld {
        let toward = frame.light_direction;
        let shade = sample_shadow(input.position, input.normal, foliage, !input.translucent);
        let sky_gate = smoothstep(0.0, 0.33, input.light.y);
        visible = shade.light * cloud_shadow(input.position) * sky_gate;
        let lit = direct_light() * sun_strength;
        if foliage {
            // Les feuilles se laissent traverser : elles restent claires à contre-jour.
            let wrapped = clamp(dot(normal, toward) * 0.5 + 0.5, 0.0, 1.0);
            let behind = pow(max(dot(view, -toward), 0.0), 3.0);
            direct = lit * visible * (0.42 + wrapped * 0.40);
            through_foliage = lit * visible * (0.24 + behind * 1.5) * subsurface * vec3<f32>(1.12, 1.18, 0.62);
        } else {
            direct = lit * visible * max(dot(normal, toward), 0.0);
        }
        if shade.underwater > 0.01 {
            // Sous l'eau, la lumière perd d'abord son rouge, puis son vert, selon l'épaisseur
            // traversée : un fond peu profond reste clair et sableux, un fond profond bleuit et
            // s'assombrit.
            var under = exp(-water_density() * shade.water_path);
            if caustics {
                under *= caustic_light(world, distance, shade.water_path * toward.y);
            }
            let reach = mix(vec3<f32>(1.0), under, shade.underwater);
            direct *= reach;
            through_foliage *= reach;
        }
    }

    // La lumière diffuse.
    let sky_level = input.light.y * input.light.y;
    var ambient = vec3<f32>(0.0);
    if overworld {
        let hemisphere = 0.72 + 0.28 * normal.y;
        ambient = ambient_sky() * sky_level * hemisphere * ambient_strength * 0.82;
        let bounce = direct_light() * 0.035 * sky_level;
        ambient += bounce;
    } else {
        ambient = dimension_ambient() * (0.72 + 0.28 * normal.y) * ambient_strength;
    }
    let block_level = input.light.x * input.light.x * (0.45 + 0.55 * input.light.x);
    let tone = block_light_tone(input);
    let block = tone * block_level * 1.28;
    let safety = to_linear(input.lightmap) * 0.06;
    let cave_floor = vec3<f32>(0.0065, 0.0085, 0.0125) * cave_light * (0.55 + frame.brightness * 1.25);
    let vision = vec3<f32>(frame.night_vision * 0.55);
    var diffuse = ambient + block + safety + cave_floor + vision + input.colored_light * 1.2;
    diffuse *= 1.0 - frame.darkness * 0.82;

    var color = albedo * (direct + diffuse + through_foliage);
    if metal {
        color = albedo * (direct * 0.35 + diffuse * 0.38);
    }

    // Les reflets.
    if smoothness > 0.01 {
        let toward = frame.light_direction;
        let fresnel = reflectance + (1.0 - reflectance) * pow(1.0 - max(dot(normal, view), 0.0), 5.0);
        let tone_reflect = select(vec3<f32>(1.0), albedo, metal);
        if overworld {
            let highlight = specular_term(normal, view, toward, smoothness);
            color += direct_light() * visible * highlight * fresnel * tone_reflect * sun_strength;
            let mirrored = reflect(-view, normal);
            let environment = sky_gradient(vec3<f32>(mirrored.x, abs(mirrored.y), mirrored.z)) * sky_level;
            color += environment * fresnel * smoothness * tone_reflect;
        }
        color += block * specular_term(normal, view, normalize(input.normal + view), smoothness) * fresnel * 0.08;
    }

    // Les blocs qui brillent.
    if input.emission > 0.0 || pack_emission > 0.0 {
        let bright = luma(input.albedo.rgb);
        let mask = max(smoothstep(0.34, 0.86, bright) * input.emission, pack_emission);
        color += to_linear(input.albedo.rgb) * mask * 1.55;
    }

    var alpha = input.albedo.a;
    if input.translucent {
        // Glace et verre : ils prennent davantage de couleur quand on les regarde de côté.
        let fresnel = pow(1.0 - max(dot(normal, view), 0.0), 4.0);
        alpha = mix(alpha, 1.0, fresnel * 0.55);
    }
    return vec4<f32>(to_display(soft_highlights(color)), alpha);
}

// Une vague de la houle : sa direction, sa longueur d'onde en blocs et sa hauteur.
// xy : sa pente, z : sa courbure, calculées exactement. w : la part de sa pente trop fine pour
// être dessinée à cette distance, en variance. Elle n'est pas perdue : elle élargit le reflet
// du soleil, exactement comme les vagues lointaines le font sur une vraie mer.
fn wave(xz: vec2<f32>, direction: vec2<f32>, length_blocks: f32, height: f32, seed: f32, distance: f32) -> vec4<f32> {
    let k = 6.2831853 / length_blocks;
    // Les vagues plus courtes qu'un pixel au loin s'effacent, au lieu de crépiter.
    let keep = 1.0 - smoothstep(length_blocks * 7.0, length_blocks * 22.0, distance);
    let speed = sqrt(9.8 * k) * 0.72;
    let phase = k * dot(direction, xz) - speed * frame.time + seed;
    let a = height * keep;
    let steepness = height * k;
    return vec4<f32>(direction * (a * k * cos(phase)), -a * k * k * sin(phase), steepness * steepness * 0.5 * (1.0 - keep));
}

// La valeur tirée au hasard pour un coin de la grille du bruit. La grille est repliée tous les
// 512 carreaux pour garder toute sa précision loin de l'origine du monde.
fn ripple_cell(c: vec2<f32>, seed: f32) -> f32 {
    return hash_cell(vec3<f32>(c - 512.0 * floor(c / 512.0), seed));
}

// La pente d'un bruit lisse : des valeurs au hasard aux coins d'une grille, raccordées par une
// courbe quintique (continue jusqu'à la courbure), dérivée exactement.
fn ripple_noise_slope(p: vec2<f32>, seed: f32) -> vec2<f32> {
    let i = floor(p);
    let f = p - i;
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    let a = ripple_cell(i, seed);
    let b = ripple_cell(i + vec2<f32>(1.0, 0.0), seed);
    let c = ripple_cell(i + vec2<f32>(0.0, 1.0), seed);
    let d = ripple_cell(i + vec2<f32>(1.0, 1.0), seed);
    let k = a - b - c + d;
    return du * vec2<f32>(b - a + k * u.y, c - a + k * u.x);
}

// Une échelle de rides, irrégulières, sans motif qui se répète : deux couches de bruit, la
// seconde tournée, qui dérivent dans des directions différentes. Leur somme se déforme sans cesse
// au lieu de glisser d'un bloc. `cell` : la taille des rides en blocs. xy : la pente, z : la
// variance de la pente trop fine pour être dessinée à cette distance (comme pour `wave`).
fn ripple_octave(xz: vec2<f32>, cell: f32, height: f32, flow_a: vec2<f32>, flow_b: vec2<f32>, seed: f32, distance: f32) -> vec3<f32> {
    let keep = 1.0 - smoothstep(cell * 9.0, cell * 26.0, distance);
    let gain = height / cell;
    if keep <= 0.0 {
        return vec3<f32>(0.0, 0.0, gain * gain * 0.7);
    }
    let t = frame.time;
    let turn = mat2x2<f32>(vec2<f32>(0.6, 0.8), vec2<f32>(-0.8, 0.6));
    let a = ripple_noise_slope(xz / cell + flow_a * t, seed);
    let b = ripple_noise_slope(turn * xz / cell + flow_b * t, seed + 3.7);
    let slope = (a + transpose(turn) * b) * gain;
    return vec3<f32>(slope * keep, gain * gain * 0.7 * (1.0 - keep));
}

// Le vent ne souffle pas partout pareil : des risées dérivent lentement sur l'eau, plus ridées et
// plus mates que l'eau calme qui les entoure, où le ciel se reflète plus net.
fn wind_roughness(xz: vec2<f32>) -> f32 {
    let t = frame.time;
    let broad = noise_at(xz / 110.0 + vec2<f32>(0.19, 0.83) + t * vec2<f32>(0.0019, 0.0012)).a;
    let gust = noise_at(xz / 37.0 + vec2<f32>(0.57, 0.08) + t * vec2<f32>(-0.0021, 0.0034)).a;
    return mix(0.4, 1.45, smoothstep(0.25, 0.75, broad * 0.7 + gust * 0.3));
}

// La surface de l'eau, sans texture : une houle de vagues régulières, et par-dessus, si `detail`,
// des rides irrégulières à trois échelles dont l'ampleur suit les risées.
fn water_waves_at(xz: vec2<f32>, distance: f32, detail: bool) -> vec4<f32> {
    var sum = wave(xz, vec2<f32>(0.80, 0.60), 19.0, 0.170, 0.7, distance);
    sum += wave(xz, vec2<f32>(0.96, 0.28), 11.0, 0.150, 0.0, distance);
    sum += wave(xz, vec2<f32>(-0.41, 0.91), 6.7, 0.090, 1.9, distance);
    sum += wave(xz, vec2<f32>(0.70, -0.71), 4.1, 0.050, 4.1, distance);
    sum += wave(xz, vec2<f32>(-0.89, -0.46), 2.6, 0.025, 2.7, distance);
    if detail {
        let rough = wind_roughness(xz);
        var fine = ripple_octave(xz, 1.3, 0.10, vec2<f32>(0.17, 0.10), vec2<f32>(-0.12, 0.16), 11.0, distance);
        fine += ripple_octave(xz, 0.62, 0.048, vec2<f32>(0.42, -0.19), vec2<f32>(-0.28, -0.37), 23.0, distance);
        fine += ripple_octave(xz, 0.29, 0.020, vec2<f32>(0.66, 0.47), vec2<f32>(-0.75, 0.30), 37.0, distance);
        sum += vec4<f32>(fine.xy * rough, 0.0, fine.z * rough * rough);
    }
    return vec4<f32>(sum.xyz * water_waves, sum.w * water_waves * water_waves);
}

// Des anneaux de gouttes sous la pluie : de petites ondes qui s'élargissent puis s'éteignent.
fn rain_rings(xz: vec2<f32>) -> vec2<f32> {
    let cell = floor(xz * 1.6);
    var slope = vec2<f32>(0.0);
    for (var i = 0; i < 2; i++) {
        let c = cell + vec2<f32>(f32(i) * 0.5);
        let seed = hash_cell(vec3<f32>(c, f32(i)));
        let centre = (c + vec2<f32>(hash_cell(vec3<f32>(c, 7.0)), hash_cell(vec3<f32>(c, 13.0)))) / 1.6;
        let age = fract(frame.time * 0.8 + seed);
        let from_centre = xz - centre;
        let r = length(from_centre);
        let front = r - age * 0.45;
        let ring = exp(-front * front * 900.0) * (1.0 - age);
        slope += from_centre / max(r, 1e-3) * ring * 0.9;
    }
    return slope;
}

fn straight_line_distance(screen: vec2<f32>, depth: f32) -> f32 {
    if depth <= 0.0 {
        return 8192.0;
    }
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, depth, 1.0);
    let v = frame.projection_inverse * clip;
    return length(v.xyz / v.w);
}

// Le reflet du soleil, d'après le modèle à micro-facettes (GGX) : la surface est vue comme une
// infinité de petites facettes, dont la pente moyenne vaut `roughness2`. Lisse, elle renvoie
// un éclat net ; agitée par des vagues trop fines pour être dessinées, elle étale ce même éclat
// en un chemin de lumière vers le soleil.
fn sun_reflection(normal: vec3<f32>, view: vec3<f32>, light: vec3<f32>, roughness2: f32) -> f32 {
    let h = normalize(view + light);
    let nh = clamp(dot(normal, h), 0.0, 1.0);
    let nl = clamp(dot(normal, light), 0.0, 1.0);
    let nv = clamp(dot(normal, view), 1e-3, 1.0);
    let a2 = roughness2;
    let spread = nh * nh * (a2 - 1.0) + 1.0;
    let distribution = a2 / (3.1415927 * spread * spread);
    let visibility = 0.5 / (nl * sqrt(nv * nv * (1.0 - a2) + a2) + nv * sqrt(nl * nl * (1.0 - a2) + a2) + 1e-5);
    let fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(h, view), 0.0, 1.0), 5.0);
    return min(distribution * visibility * fresnel * nl, 60.0);
}

fn water(input: MaterialInput) -> vec4<f32> {
    let distance = length(input.position);
    let view = -input.position / max(distance, 0.001);
    let world = input.position + frame.camera_position;
    let from_below = frame.eye_in == 1u;
    let top = input.face == 1u;

    var normal = input.normal;
    var unresolved = 0.0;
    if top {
        let waves = water_waves_at(world.xz, distance, true);
        var slope = waves.xy;
        unresolved = waves.w;
        if frame.wetness > 0.01 && frame.precipitation == 1u && distance < 40.0 {
            slope += rain_rings(world.xz) * frame.wetness * smoothstep(0.6, 1.0, input.light.y) * (1.0 - distance / 40.0);
        }
        normal = normalize(vec3<f32>(-slope.x, 1.0, -slope.y));
    }

    // Ce qu'on voit à travers l'eau, déplacé par les vagues et les rides : la lumière qui remonte
    // du fond est d'autant plus déviée que l'eau est épaisse. Près des berges, l'eau trop mince
    // ne tord presque plus l'image.
    let size = frame.resolution;
    let straight_depth = textureLoad(opaque_depth, vec2<i32>(input.screen * size), 0);
    let straight_thickness = max(straight_line_distance(input.screen, straight_depth) - distance, 0.0);
    let bend = normal.xz * 0.018 * min(straight_thickness, 4.0) / (1.0 + distance * 0.06);
    var at = clamp(input.screen + bend, vec2<f32>(0.0), vec2<f32>(0.9999));
    var behind_depth = textureLoad(opaque_depth, vec2<i32>(at * size), 0);
    var behind_distance = straight_line_distance(at, behind_depth);
    if behind_distance < distance {
        // Le décalage a touché quelque chose devant l'eau : on regarde tout droit.
        at = input.screen;
        behind_depth = straight_depth;
        behind_distance = straight_line_distance(at, behind_depth);
    }
    let behind = to_linear(textureLoad(opaque_color, vec2<i32>(at * size), 0).rgb);
    let thickness = max(behind_distance - distance, 0.0);

    let water_tone = to_linear(input.tint.rgb);
    // Turquoise : le rouge est absorbé vite, le vert et le bleu passent ; une eau peu profonde
    // tire sur l'émeraude, une eau profonde sur le bleu-vert sombre. Biome : la teinte du jeu.
    // (Des `let` et `select` plutôt qu'un `var` modifié : naga 30, qui traduit les shaders du jeu,
    // produit un SPIR-V invalide pour un `var` initialisé à partir d'une option.)
    let turquoise = water_style == 0u;
    let transmitted = exp(-water_density() * min(thickness, 96.0));
    var ambient = ambient_sky() * input.light.y * input.light.y * 0.62;
    ambient += block_light_tone(input) * input.light.x * input.light.x * 0.30;
    ambient += vec3<f32>(0.006, 0.010, 0.016) * cave_light;
    let deep = select(mix(water_tone, vec3<f32>(0.020, 0.25, 0.36), 0.55), vec3<f32>(0.010, 0.17, 0.15), turquoise);
    var body = behind * transmitted + deep * ambient * (1.0 - transmitted);

    // La surface lit seulement les blocs solides : elle ne se fait pas d'ombre à elle-même.
    let shade = sample_shadow(input.position, vec3<f32>(0.0, 1.0, 0.0), false, false);
    let sky_gate = smoothstep(0.0, 0.33, input.light.y);
    let visible = shade.light * cloud_shadow(input.position) * sky_gate;
    let light_on_water = direct_light() * sun_strength * visible;
    body += deep * light_on_water * (1.0 - transmitted) * max(frame.light_direction.y, 0.0) * 0.20;

    if from_below {
        let inside = pow(max(dot(normal, view), 0.0), 2.0);
        return vec4<f32>(to_display(soft_highlights(mix(ambient * vec3<f32>(0.25, 0.55, 0.75), behind, inside))), 1.0);
    }

    let cos_view = max(dot(normal, view), 0.0);
    var fresnel = 0.02 + 0.98 * pow(1.0 - cos_view, 5.0);
    // Au ras des berges, l'eau s'efface doucement au lieu de finir sur une arête.
    let shore = smoothstep(0.0, 0.30, thickness);
    fresnel *= shore;
    let mirrored = reflect(-view, normal);
    var reflection_color = sky_gradient(vec3<f32>(mirrored.x, abs(mirrored.y), mirrored.z)) * input.light.y;
    if reflections && frame.has_reflection == 1u && top {
        let ripple_shift = normal.xz * vec2<f32>(0.016, 0.034) / (1.0 + distance * 0.015);
        let mirror_uv = clamp(input.screen + ripple_shift, vec2<f32>(0.001), vec2<f32>(0.999));
        let world_in_water = to_linear(textureSampleLevel(reflection, reflection_sampler, mirror_uv, 0.0).rgb);
        reflection_color = mix(reflection_color, world_in_water, 0.9);
    }
    var color = mix(body, reflection_color, fresnel);

    // Face au soleil, la lumière traverse le haut des vagues et les fait luire de l'intérieur.
    let against_light = pow(clamp(dot(-view, frame.light_direction), 0.0, 1.0), 4.0);
    let tilt = clamp(length(normal.xz) * 5.0, 0.0, 1.0);
    color += vec3<f32>(0.10, 0.42, 0.40) * light_on_water * against_light * tilt * 0.10 * shore;

    // Le reflet du soleil. De près, la houle et ses rides le brisent en éclats ; au loin, les
    // vagues trop fines pour être dessinées l'étirent en un chemin de lumière. Une légère pente
    // de base (0,04) garde l'éclat plus large qu'un pixel : il ne scintille pas.
    if sun_glint > 0.0 && top {
        let roughness2 = 0.0016 + 2.0 * unresolved;
        let glint = sun_reflection(normal, view, frame.light_direction, roughness2);
        // Autour des éclats, un halo plus large : la lumière renvoyée par les rides de toutes
        // les pentes, qui fait luire la surface entre les éclats.
        let sheen = sun_reflection(normal, view, frame.light_direction, roughness2 * 8.0 + 0.012);
        color += light_on_water * (glint * 0.6 + sheen * 0.12) * sun_glint * shore;
    }

    return vec4<f32>(to_display(soft_highlights(color)), 1.0);
}

fn lava(input: MaterialInput) -> vec4<f32> {
    let world = input.position + frame.camera_position;
    let flow = noise_at(world.xz / 9.0 + vec2<f32>(frame.time * 0.007, frame.time * 0.004)).g;
    let base = to_linear(input.albedo.rgb * input.tint.rgb);
    let hot = base * (1.45 + flow * 1.1) + vec3<f32>(0.34, 0.075, 0.008) * flow;
    return vec4<f32>(to_display(soft_highlights(hot)), input.albedo.a);
}

fn material(input: MaterialInput) -> Surface {
    if input.fluid == 1u {
        return Surface(water(input));
    }
    if input.fluid == 2u {
        return Surface(lava(input));
    }
    return Surface(terrain(input));
}
