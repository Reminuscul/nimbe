// Nimbe : le ciel. Dégradé peint, soleil, étoiles, aurores, cumulus et cirrus.

override cloud_quality: u32 = 1u;
override stars_amount: f32 = 1.0;
override aurora: bool = true;

// Le nombre de lectures vers l'astre pour l'ombre propre des nuages : 1, 2 ou 3.
fn cloud_light_taps() -> i32 {
    return i32(min(cloud_quality, 2u)) + 1;
}

fn sky_pixel(direction: vec3<f32>) -> vec2<f32> {
    let clip = frame.projection * frame.view * vec4<f32>(direction, 0.0);
    let ndc = clip.xy / max(abs(clip.w), 1e-4);
    return (ndc * vec2<f32>(0.5, -0.5) + 0.5) * frame.resolution;
}

fn sun_disc(direction: vec3<f32>) -> vec3<f32> {
    let cosine = dot(direction, frame.sun_direction);
    let disc = smoothstep(0.99945, 0.99975, cosine);
    let rim = smoothstep(0.9965, 0.9994, cosine) * 0.30;
    let horizon_fade = smoothstep(-0.03, 0.03, direction.y);
    return sun_color() * (disc * 7.0 + rim) * horizon_fade * (1.0 - storm());
}

// Les étoiles tournent avec le ciel, autour de l'axe de la course du soleil.
fn star_field(direction: vec3<f32>) -> vec3<f32> {
    if stars_amount <= 0.0 {
        return vec3<f32>(0.0);
    }
    let angle = frame.day_time * 6.2831853;
    let c = cos(angle);
    let s = sin(angle);
    let d = vec3<f32>(direction.x, direction.y * c - direction.z * s, direction.y * s + direction.z * c);
    let cells = d * 170.0;
    let cell = floor(cells);
    let seed = hash_cell(cell);
    let presence = step(0.9925 - 0.004 * (stars_amount - 1.0), seed);
    if presence <= 0.0 {
        return vec3<f32>(0.0);
    }
    let centre = vec3<f32>(hash_cell(cell + 3.1), hash_cell(cell + 7.7), hash_cell(cell + 13.3)) * 0.6 + 0.2;
    let spot = smoothstep(0.34, 0.03, length(fract(cells) - centre));
    let twinkle = 0.72 + 0.28 * sin(frame.time * (1.4 + seed * 5.0) + seed * 80.0);
    let hue = mix(vec3<f32>(0.68, 0.80, 1.0), vec3<f32>(1.0, 0.82, 0.68), hash_cell(cell + 21.0));
    return hue * spot * twinkle * stars_amount * 0.95;
}

// Une nébuleuse très discrète, pour que la nuit ne soit jamais un noir uni.
fn nebula(direction: vec3<f32>) -> vec3<f32> {
    let uv = direction.xz / (abs(direction.y) + 0.45);
    let a = noise_at(uv * 0.09 + vec2<f32>(0.21, 0.47)).g;
    let b = noise_at(uv * 0.21 + vec2<f32>(0.63, 0.14)).b;
    let cloud = smoothstep(0.46, 0.82, a * 0.68 + b * 0.32);
    return mix(vec3<f32>(0.018, 0.012, 0.055), vec3<f32>(0.005, 0.030, 0.050), b) * cloud * stars_amount;
}

// Des voiles qui ondulent vers le nord, seulement dans les biomes froids.
fn aurora_veil(direction: vec3<f32>) -> vec3<f32> {
    if !aurora || direction.y <= 0.02 || frame.temperature > 0.32 {
        return vec3<f32>(0.0);
    }
    var light = vec3<f32>(0.0);
    let night = 1.0 - smoothstep(-0.18, -0.02, frame.sun_direction.y);
    if night <= 0.0 {
        return light;
    }
    for (var i = 0; i < 6; i++) {
        let height = 0.14 + f32(i) * 0.075;
        let t = height / direction.y;
        let p = direction.xz * t;
        let wave = noise_at(vec2<f32>(p.x * 0.17 + frame.time * 0.0035, p.y * 0.05 - frame.time * 0.002)).r;
        let curtain = smoothstep(0.50, 0.70, wave) * smoothstep(0.62, 0.18, abs(p.y + 0.55));
        let hue = mix(vec3<f32>(0.12, 0.95, 0.56), vec3<f32>(0.42, 0.20, 0.95), f32(i) / 5.0);
        light += hue * curtain / (1.0 + f32(i));
    }
    return light * 0.12 * night * smoothstep(0.02, 0.22, direction.y) * (1.0 - storm());
}

// L'endroit où le rayon coupe le plan horizontal `height` et la taille d'un pixel à cet endroit,
// en blocs. x < 0 : le rayon ne coupe pas ce plan.
fn cut_plane(direction: vec3<f32>, height: f32) -> vec2<f32> {
    let distance = (height - frame.camera_position.y) / direction.y;
    if abs(direction.y) < 0.004 || distance <= 0.0 {
        return vec2<f32>(-1.0, 0.0);
    }
    let pixel_angle = 2.0 / (frame.projection[1][1] * frame.resolution.y);
    return vec2<f32>(distance, distance * pixel_angle / max(abs(direction.y), 0.035));
}

// Les cumulus : une couche dont le relief vient de la lumière. Leur ombre propre vers l'astre
// assombrit les cœurs épais, les bords minces s'illuminent à contre-jour, le dessous s'assombrit
// vu d'en bas. xyz : la lumière des nuages, w : la part du ciel qui passe à travers.
fn cumulus(direction: vec3<f32>, horizon: vec3<f32>) -> vec4<f32> {
    let clear = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    let cut = cut_plane(direction, CLOUD_BASE + CLOUD_THICKNESS * 0.5);
    let distance = cut.x;
    let footprint = cut.y;
    if distance <= 0.0 {
        return clear;
    }
    let fade = 1.0 - smoothstep(2600.0, 9500.0, distance);
    if fade <= 0.0 {
        return clear;
    }
    let p = frame.camera_position.xz + direction.xz * distance;
    let cover = cloud_cover_filtered(p, footprint);
    if cover <= 0.002 {
        return clear;
    }
    // Des bords effilochés de près, lissés au loin.
    let keep_detail = 1.0 - smoothstep(3.0, 20.0, footprint);
    let wind = vec2<f32>(frame.time * 2.6, frame.time * 0.8);
    let erosion = (noise_at((p + wind) / 64.0).a - 0.5) * 0.22 * keep_detail * (1.0 - cover);
    let density = clamp(cover + erosion, 0.0, 1.0);
    if density <= 0.002 {
        return clear;
    }

    let toward = frame.light_direction.xz / max(frame.light_direction.y, 0.12);
    let taps = cloud_light_taps();
    var shading = 0.0;
    for (var i = 1; i <= taps; i++) {
        shading += cloud_cover_filtered(p + toward * (30.0 * f32(i)), footprint);
    }
    shading /= f32(taps);

    let forward = max(dot(direction, frame.light_direction), 0.0);
    let phase = 0.62 + pow(forward, 6.0) * 0.55 + pow(forward, 40.0) * 0.9;
    let attenuation = exp(-shading * 2.5);
    let powder = 1.0 - exp(-density * 4.5);
    let rim = pow(forward, 10.0) * (1.0 - density) * 1.4;
    let below = frame.camera_position.y < CLOUD_BASE + CLOUD_THICKNESS * 0.5;
    // Vu d'en dessous, on regarde la face qui ne reçoit pas le soleil.
    let underside = select(1.0, mix(1.0, 0.42, density), below && frame.light_direction.y > 0.0);
    let sunlit = direct_light() * (attenuation * phase * (0.35 + 0.65 * powder) * underside + rim) * 0.5;
    let skylit = ambient_sky() * mix(0.95, 0.62, density * select(0.0, 1.0, below));
    var body = skylit + sunlit;
    body = mix(body, horizon, 1.0 - exp(-distance / 7000.0));

    let slant = min(1.0 / max(abs(direction.y), 0.035), 12.0);
    let alpha = (1.0 - exp(-density * CLOUD_THICKNESS * slant * 0.035)) * fade;
    return vec4<f32>(body * alpha, 1.0 - alpha);
}

// Des cirrus : de longs voiles très hauts, étirés par le vent d'altitude.
fn cirrus(direction: vec3<f32>, horizon: vec3<f32>) -> vec4<f32> {
    let clear = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    if cloud_quality == 0u || frame.camera_position.y > 560.0 {
        return clear;
    }
    let cut = cut_plane(direction, 560.0);
    if cut.x <= 0.0 {
        return clear;
    }
    let fade = 1.0 - smoothstep(4000.0, 14000.0, cut.x);
    let p = frame.camera_position.xz + direction.xz * cut.x + vec2<f32>(frame.time * 4.0, frame.time * 1.1);
    // Le long du vent (x) les voiles sont très étirés.
    let along = vec2<f32>(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8);
    let keep = 1.0 - smoothstep(40.0, 200.0, cut.y);
    let streak = noise_at(vec2<f32>(along.x / 7000.0, along.y / 1900.0)).g;
    let fibre = mix(0.5, noise_at(vec2<f32>(along.x / 2600.0, along.y / 260.0) + vec2<f32>(0.31, 0.77)).b, keep);
    let wisps = smoothstep(0.62, 0.90, streak * 0.78 + fibre * 0.22);
    let amount = wisps * (0.25 + cloud_amount * 0.45) * (1.0 - storm()) * fade;
    if amount <= 0.002 {
        return clear;
    }
    let forward = max(dot(direction, frame.light_direction), 0.0);
    var body = ambient_sky() * 1.05 + direct_light() * (0.30 + pow(forward, 8.0) * 0.6) * 0.45;
    body = mix(body, horizon, 1.0 - exp(-cut.x / 12000.0));
    let alpha = amount * 0.34;
    return vec4<f32>(body * alpha, 1.0 - alpha);
}

fn clouds(direction: vec3<f32>, pixel: vec2<f32>) -> vec4<f32> {
    if cloud_amount <= 0.0 && storm() <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let horizon = sky_gradient(normalize(vec3<f32>(direction.x, max(abs(direction.y), 0.02), direction.z)));
    let high = cirrus(direction, horizon);
    let low = cumulus(direction, horizon);
    // Les cumulus passent devant les cirrus.
    return vec4<f32>(high.xyz * low.w + low.xyz, high.w * low.w);
}

fn sky(input: SkyInput) -> vec4<f32> {
    let direction = input.direction;
    var color = sky_gradient(direction);

    let night = (1.0 - daylight()) * (1.0 - storm());
    if night > 0.001 && direction.y > -0.04 {
        let horizon_fade = smoothstep(-0.04, 0.10, direction.y);
        color += (star_field(direction) + nebula(direction)) * night * horizon_fade;
    }
    color += aurora_veil(direction);
    color += sun_disc(direction);

    let layer = clouds(direction, sky_pixel(direction));
    color = color * layer.w + layer.xyz;

    return vec4<f32>(to_display(soft_highlights(color)), input.color.a);
}
