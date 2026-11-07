// Nimbe : rayons de lumière et occlusion ambiante, à mi-résolution.
// xyz : la lumière diffusée par l'air le long du rayon. w : l'occlusion, de 0 (noir) à 1.

override volumetric: bool = true;
override volumetric_quality: u32 = 1u;
override ao_strength: f32 = 0.7;

fn ray_marches() -> i32 {
    return select(select(18, 11, volumetric_quality == 1u), 6, volumetric_quality == 0u);
}

// Lumière diffusée : la brume est plus dense près du sol, à l'aube et sous l'orage.
fn light_shafts(direction: vec3<f32>, limit: f32, pixel: vec2<f32>) -> vec3<f32> {
    if !volumetric || frame.has_shadow != 1u || frame.dimension != 0 || frame.eye_in != 0u {
        return vec3<f32>(0.0);
    }
    let indoors = smoothstep(0.02, 0.45, frame.eye_light_smooth.y);
    if indoors <= 0.0 {
        return vec3<f32>(0.0);
    }
    let reach = min(limit, frame.shadow_distance * 1.2);
    let count = ray_marches();
    let stride = reach / f32(count);
    // Quatre départs décalés sur 2×2 pixels, que le lissage réunit : quatre fois plus de pas.
    let start = (interleave_2x2(pixel) + 0.125) * stride;
    var collected = 0.0;
    for (var i = 0; i < count; i++) {
        let travelled = start + stride * f32(i);
        let p = direction * travelled;
        let inside_map = 1.0 - smoothstep(0.84, 1.0, length(p) / max(frame.shadow_distance, 1.0));
        var lit = 1.0;
        if inside_map > 0.0 {
            let s = shadow_position(p);
            let reading = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z);
            lit = mix(1.0, reading, inside_map);
        }
        let altitude = p.y + frame.camera_position.y;
        let thickness = exp(-max(altitude - 58.0, 0.0) / 72.0);
        collected += lit * thickness * stride;
    }

    let cosine = dot(direction, frame.light_direction);
    let forward = 0.5 / pow(1.46 - 1.38 * cosine, 1.5);
    let phase = 0.075 + forward * 0.085;
    let season = 0.0030 + golden_hour() * 0.0038 + storm() * 0.0006 + (1.0 - daylight()) * 0.0024;
    return direct_light() * collected * phase * season * indoors;
}

// Le point de la profondeur pleine résolution le plus proche de `uv` : sa profondeur et sa position,
// reconstruite au centre exact du texel lu. (Reconstruire avec les coordonnées d'un pixel de
// cette passe à mi-résolution décalerait chaque point d'un demi-texel, et ce décalage, qui
// change d'une ligne à l'autre, dessinait de fines bandes.) w : la profondeur, 0 pour le ciel.
fn depth_point(uv: vec2<f32>) -> vec4<f32> {
    let size = vec2<f32>(textureDimensions(scene_depth));
    let texel = clamp(floor(uv * size), vec2<f32>(0.0), size - 1.0);
    let depth = textureLoad(scene_depth, vec2<i32>(texel), 0);
    return vec4<f32>(view_position((texel + 0.5) / size, max(depth, 0.00002)), depth);
}

// La normale de la surface en `uv`, d'après ses voisins pleine résolution : de chaque côté, on
// garde le voisin le plus proche en profondeur, pour ne pas mélanger deux objets sur un bord.
fn surface_normal(uv: vec2<f32>, centre: vec3<f32>) -> vec3<f32> {
    let step = 1.0 / vec2<f32>(textureDimensions(scene_depth));
    let right = depth_point(uv + vec2<f32>(step.x, 0.0)).xyz - centre;
    let left = centre - depth_point(uv - vec2<f32>(step.x, 0.0)).xyz;
    let down = depth_point(uv + vec2<f32>(0.0, step.y)).xyz - centre;
    let up = centre - depth_point(uv - vec2<f32>(0.0, step.y)).xyz;
    let across = select(left, right, dot(right, right) < dot(left, left));
    let along = select(up, down, dot(down, down) < dot(up, up));
    var normal = cross(across, along);
    if dot(normal, normal) < 1e-12 {
        return vec3<f32>(0.0);
    }
    normal = normalize(normal);
    return select(normal, -normal, dot(normal, centre) > 0.0);
}

fn hemisphere_occlusion(uv: vec2<f32>, pixel: vec2<f32>) -> f32 {
    if ao_strength <= 0.0 {
        return 1.0;
    }
    let here = depth_point(uv);
    if here.w <= 0.0 {
        return 1.0;
    }
    let centre = here.xyz;
    let distance = length(centre);
    if distance > 160.0 {
        return 1.0;
    }
    let normal = surface_normal(uv, centre);
    if dot(normal, normal) < 0.5 {
        return 1.0;
    }
    let bias = 0.012 + distance * 0.0009;
    let radius_blocks = 0.85;
    let on_screen = clamp(radius_blocks * frame.projection[1][1] / max(distance, 0.5) * 0.5, 0.004, 0.09);
    let aspect = frame.resolution.y / frame.resolution.x;
    let spin = interleave_2x2(pixel) * 1.5707963;
    var occlusion = 0.0;
    for (var i = 0; i < 9; i++) {
        let ring = sqrt((f32(i) + 0.5) / 9.0);
        let angle = f32(i) * 2.3999632 + spin;
        let offset = vec2<f32>(cos(angle) * aspect, sin(angle)) * ring * on_screen;
        let tap_point = depth_point(uv + offset);
        if tap_point.w <= 0.0 {
            continue;
        }
        let tap = tap_point.xyz;
        let to_tap = tap - centre;
        let span = length(to_tap);
        if span < 0.0005 {
            continue;
        }
        let rise = (dot(to_tap, normal) - bias) / span;
        let weight = 1.0 - smoothstep(radius_blocks * 0.8, radius_blocks * 1.8, span);
        occlusion += max(rise, 0.0) * weight;
    }
    let shade = 1.0 - occlusion / 9.0 * 2.5;
    return mix(1.0, clamp(shade, 0.0, 1.0), ao_strength);
}

fn post(input: PostInput) -> vec4<f32> {
    let depth = input.depth;
    let ray_end = view_position(input.uv, max(depth, 0.00002));
    let distance = length(ray_end);
    let direction = ray_end / max(distance, 0.0001);
    let limit = select(420.0, distance, depth > 0.0);
    let shafts = light_shafts(direction, limit, input.pixel);
    let occlusion = hemisphere_occlusion(input.uv, input.pixel);
    return vec4<f32>(shafts, occlusion);
}
