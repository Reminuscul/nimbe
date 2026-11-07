// Nimbe : outils partagés par toutes les étapes (couleur, bruit, ciel, nuages).
// Les couleurs sont calculées en lumière linéaire puis converties pour l'écran.

override cloud_amount: f32 = 0.55;

const MAT_LEAVES: u32 = 1u;
const MAT_PLANT_LOW: u32 = 2u;
const MAT_PLANT_TALL_BOTTOM: u32 = 3u;
const MAT_PLANT_TALL_TOP: u32 = 4u;
const MAT_HANGING: u32 = 5u;
const MAT_FLAT_PLANT: u32 = 6u;
const MAT_SEAGRASS: u32 = 7u;
const MAT_SEAGRASS_TOP: u32 = 8u;
const MAT_KELP: u32 = 9u;
const MAT_METAL: u32 = 10u;
const MAT_POLISHED: u32 = 11u;
const MAT_CRYSTAL: u32 = 12u;

const CLOUD_BASE: f32 = 260.0;
const CLOUD_THICKNESS: f32 = 110.0;

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn to_display(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// Courbe douce : ne touche presque pas les tons moyens et retient les hautes lumières.
fn soft_highlights(c: vec3<f32>) -> vec3<f32> {
    let knee = 0.72;
    let over = max(c - vec3<f32>(knee), vec3<f32>(0.0));
    return min(c, vec3<f32>(knee)) + over / (vec3<f32>(1.0) + over / (1.0 - knee));
}

// Un motif fixe de 2×2 pixels (0, 1/2, 3/4, 1/4) pour répartir les lectures des passes à
// mi-résolution. Le lissage qui suit couvre toujours ces 2×2 pixels : le motif disparaît
// entièrement, sans bruit ni trame visibles à l'écran.
fn interleave_2x2(pixel: vec2<f32>) -> f32 {
    let cell = vec2<u32>(floor(pixel)) % vec2<u32>(2u);
    return f32((cell.x * 2u + cell.y * 3u) % 4u) * 0.25;
}

fn hash_cell(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(0.1031, 0.1137, 0.1279));
    let r = q + dot(q, q.yzx + 33.33);
    return fract((r.x + r.y) * r.z);
}

fn noise_at(uv: vec2<f32>) -> vec4<f32> {
    return textureSampleLevel(noise, noise_sampler, uv, 0.0);
}

fn storm() -> f32 {
    return clamp(max(frame.rain, frame.thunder * 1.2), 0.0, 1.0);
}

// 1 le jour, 0 la nuit, en glissant autour de l'horizon.
fn daylight() -> f32 {
    return smoothstep(-0.10, 0.14, frame.sun_direction.y);
}

// 1 quand le soleil frôle l'horizon.
fn golden_hour() -> f32 {
    return 1.0 - smoothstep(0.02, 0.42, abs(frame.sun_direction.y));
}

fn sun_color() -> vec3<f32> {
    let noon = vec3<f32>(1.0, 0.94, 0.84);
    let low = vec3<f32>(1.0, 0.50, 0.24);
    return mix(noon, low, golden_hour()) * 2.3;
}

fn moon_color() -> vec3<f32> {
    return vec3<f32>(0.34, 0.46, 0.80) * 0.26;
}

// La lumière directe de l'astre qui projette les ombres en ce moment. Elle s'éteint un instant
// quand le soleil et la lune se relaient, pour cacher le basculement des ombres.
fn direct_light() -> vec3<f32> {
    let handover = smoothstep(0.015, 0.10, abs(frame.light_direction.y));
    let source = mix(moon_color(), sun_color(), daylight());
    return source * handover * (1.0 - 0.88 * storm());
}

// Le dégradé du ciel le long d'un rayon, sans nuages ni astres. Sert aussi de couleur de brume,
// pour que le terrain lointain se fonde exactement dans l'horizon.
fn sky_gradient(direction: vec3<f32>) -> vec3<f32> {
    let day = daylight();
    let gold = golden_hour();
    let zenith_day = mix(vec3<f32>(0.075, 0.25, 0.68), vec3<f32>(0.17, 0.17, 0.46), gold);
    let horizon_day = mix(vec3<f32>(0.56, 0.76, 0.98), vec3<f32>(1.0, 0.46, 0.27), gold);
    let zenith = mix(vec3<f32>(0.004, 0.007, 0.022), zenith_day, day);
    let horizon = mix(vec3<f32>(0.014, 0.026, 0.060), horizon_day, day);

    let up = max(direction.y, 0.0);
    let blend = pow(1.0 - up, 3.6);
    var color = mix(zenith, horizon, blend);

    // Un ruban rosé juste au-dessus de l'horizon, au lever et au coucher.
    let band = exp(-pow((direction.y - 0.13) / 0.14, 2.0));
    color += vec3<f32>(0.42, 0.12, 0.26) * band * gold * day;

    // Le halo de l'astre.
    let toward_sun = max(dot(direction, frame.sun_direction), 0.0);
    let glow = pow(toward_sun, 7.0) * 0.16 + pow(toward_sun, 72.0) * 0.46;
    color += sun_color() * glow * (0.22 + 0.78 * gold) * smoothstep(-0.22, 0.02, frame.sun_direction.y);
    let toward_moon = max(dot(direction, frame.moon_direction), 0.0);
    color += moon_color() * pow(toward_moon, 40.0) * 0.5 * (1.0 - day);

    // Sous l'horizon, le ciel s'assombrit légèrement.
    color *= mix(0.55, 1.0, smoothstep(-0.32, 0.0, direction.y));

    // Par temps couvert, le ciel devient gris en gardant sa luminosité générale.
    let grey = vec3<f32>(luma(color)) * vec3<f32>(0.78, 0.82, 0.90) * 0.62;
    return mix(color, grey, storm() * 0.92);
}

fn sky_display(direction: vec3<f32>) -> vec3<f32> {
    return to_display(soft_highlights(sky_gradient(direction)));
}

// Lumière diffuse reçue du ciel entier.
fn ambient_sky() -> vec3<f32> {
    let above = sky_gradient(vec3<f32>(0.0, 1.0, 0.0));
    let around = sky_gradient(normalize(vec3<f32>(-frame.sun_direction.x, 0.22, -frame.sun_direction.z)));
    return above * 0.62 + around * 0.38;
}

// La couverture de nuages au-dessus d'un point du monde, de 0 à 1. `footprint` est la taille
// d'un pixel au sol, en blocs : les détails plus petits qu'un pixel sont remplacés par leur
// moyenne, ce qui évite le scintillement et les traînées des nuages lointains.
fn cloud_cover_filtered(world_xz: vec2<f32>, footprint: f32) -> f32 {
    let wind = vec2<f32>(frame.time * 2.1, frame.time * 0.65);
    let large = noise_at((world_xz + wind) / 3100.0).r;
    let medium = noise_at((world_xz + wind * 1.4) / 980.0 + vec2<f32>(0.37, 0.11)).g;
    let fine = noise_at((world_xz + wind * 1.9) / 270.0 + vec2<f32>(0.73, 0.59)).b;
    let keep_large = 1.0 - smoothstep(90.0, 320.0, footprint);
    let keep_medium = 1.0 - smoothstep(10.0, 40.0, footprint);
    let keep_fine = 1.0 - smoothstep(1.5, 6.0, footprint);
    let shape = mix(0.5, large, keep_large) * 0.60
        + mix(0.5, medium, keep_medium) * 0.29
        + mix(0.5, fine, keep_fine) * 0.11;
    // Sous l'orage, le ciel se couvre presque entièrement.
    let threshold = mix(0.68, 0.34, clamp(cloud_amount + storm() * 0.55, 0.0, 1.0)) - storm() * 0.16;
    // Les bords restent doux, et plus encore au loin, pour ne jamais paraître crénelés.
    let softness = 0.30 + clamp(footprint / 400.0, 0.0, 0.25);
    return smoothstep(threshold, threshold + softness, shape);
}

fn cloud_cover(world_xz: vec2<f32>) -> f32 {
    return cloud_cover_filtered(world_xz, 0.0);
}
