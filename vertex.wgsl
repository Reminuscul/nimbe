// Nimbe : le vent dans les plantes et la houle de l'eau, dans le monde et sur la carte d'ombres.

override waving: f32 = 1.0;

// La force du vent : des rafales lentes qui traversent le paysage en quelques secondes.
fn gust_at(world: vec3<f32>) -> f32 {
    let t = frame.time;
    let broad = sin(t * 0.27 + world.x * 0.017 + world.z * 0.011);
    let swell = sin(t * 0.61 + world.x * 0.041 - world.z * 0.029);
    return 0.66 + 0.24 * broad + 0.10 * swell;
}

// Le balancement : une houle lente partagée par les plantes voisines, puis un frémissement léger
// propre à chacune. La vitesse ne varie jamais, seule l'ampleur suit les rafales : le mouvement
// reste fluide.
fn sway(world: vec3<f32>) -> vec3<f32> {
    let t = frame.time;
    let lean = sin(t * 1.02 + dot(world.xz, vec2<f32>(0.09, 0.06)));
    let side = sin(t * 0.75 + dot(world.xz, vec2<f32>(-0.05, 0.11)) + 1.7);
    let flutter = sin(t * 2.45 + world.x * 0.83 + world.z * 0.61 + world.y * 0.47);
    return vec3<f32>(lean + flutter * 0.16, flutter * 0.05, side * 0.75 + flutter * 0.12);
}

// Sous l'eau, le courant : un balancement ample et lent. Sa phase avance avec la hauteur, si
// bien que le varech ondule sur toute sa longueur, et ne dépend que de la position : deux blocs
// de varech empilés bougent ensemble, sans cassure.
fn current_sway(world: vec3<f32>) -> vec3<f32> {
    let t = frame.time;
    let swing = sin(t * 0.95 - world.y * 0.55 + dot(world.xz, vec2<f32>(0.21, 0.13)));
    let cross_swing = sin(t * 0.7 - world.y * 0.42 + dot(world.xz, vec2<f32>(-0.12, 0.19)) + 2.1);
    return vec3<f32>(swing, 0.0, cross_swing * 0.7);
}

fn vertex(input: VertexInput) -> vec3<f32> {
    let distance = length(input.position);
    if waving <= 0.0 || distance > 72.0 {
        return input.position;
    }
    let world = input.position + frame.camera_position;
    let fade = 1.0 - smoothstep(48.0, 72.0, distance);
    let weather = 1.0 + frame.rain * 0.6 + frame.thunder * 0.7;
    let breeze = gust_at(world) * weather * waving * fade;

    if input.fluid == 1u {
        if input.face != 1u {
            return input.position;
        }
        // Vers le bas seulement, pour ne jamais dépasser les blocs voisins.
        let a = sin(frame.time * 1.25 + world.x * 0.42 + world.z * 0.25);
        let b = sin(frame.time * 1.75 - world.x * 0.21 + world.z * 0.57);
        let roll = (a * 0.6 + b * 0.4) * 0.5 + 0.5;
        return input.position - vec3<f32>(0.0, roll * 0.11 * fade * waving, 0.0);
    }

    // Le haut d'une plante bouge, son pied reste planté : uv.y vaut 0 en haut du sprite.
    let tip = 1.0 - clamp(input.uv.y, 0.0, 1.0);

    // Les plantes sous l'eau suivent le courant, pas le vent.
    let underwater = waving * fade;
    switch input.material {
        case MAT_SEAGRASS: {
            return input.position + current_sway(world) * (0.11 * tip) * underwater;
        }
        case MAT_SEAGRASS_TOP: {
            return input.position + current_sway(world) * (0.11 + 0.11 * tip) * underwater;
        }
        case MAT_KELP: {
            return input.position + current_sway(world) * 0.10 * underwater;
        }
        default: {}
    }
    var amount = 0.0;
    switch input.material {
        case MAT_LEAVES: {
            amount = 0.024;
        }
        case MAT_PLANT_LOW: {
            amount = 0.085 * tip;
        }
        case MAT_PLANT_TALL_BOTTOM: {
            amount = 0.055 * tip;
        }
        case MAT_PLANT_TALL_TOP: {
            amount = 0.055 + 0.085 * tip;
        }
        case MAT_HANGING: {
            amount = 0.045;
        }
        case MAT_FLAT_PLANT: {
            amount = 0.012;
        }
        default: {
            return input.position;
        }
    }
    return input.position + sway(world) * amount * breeze;
}
