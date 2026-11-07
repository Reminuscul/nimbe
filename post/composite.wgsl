// Nimbe : occlusion, brume et rayons de lumière, puis la vue sous l'eau et dans la lave.

override volumetric_strength: f32 = 1.0;
override haze: f32 = 1.0;

fn post(input: PostInput) -> vec4<f32> {
    var uv = input.uv;
    if frame.in_water > 0.01 {
        let t = frame.time;
        let wobble = vec2<f32>(sin(uv.y * 23.0 + t * 1.7), cos(uv.x * 19.0 + t * 1.3));
        uv = clamp(uv + wobble * 0.0022 * frame.in_water, vec2<f32>(0.0), vec2<f32>(1.0));
    }
    var color = to_linear(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb);
    let depth = depth_at(uv);
    let extra = textureSampleLevel(volumetrics_soft, linear_sampler, uv, 0.0);

    let ray_end = view_position(uv, max(depth, 0.00002));
    let distance = length(ray_end);
    let direction = ray_end / max(distance, 0.0001);

    if depth > 0.0 {
        color *= extra.a;

        // Le brouillard du jeu décide dans l'eau, la lave, la neige poudreuse, le Nether, l'End,
        // et sous les effets de cécité : il garde ainsi son comportement et ses couleurs.
        let vanilla_fog = smoothstep(frame.fog_start, max(frame.fog_end, frame.fog_start + 0.01), distance);
        let special = frame.dimension != 0 || frame.eye_in != 0u || frame.blindness > 0.001 || frame.darkness > 0.001;
        if special {
            var fog = to_linear(frame.fog_color);
            if frame.dimension == -1 {
                fog = mix(fog, vec3<f32>(0.20, 0.055, 0.035), 0.42);
            } else if frame.dimension == 1 {
                fog = mix(fog, vec3<f32>(0.05, 0.025, 0.11), 0.50);
            } else if frame.eye_in == 1u {
                fog = fog * vec3<f32>(0.55, 0.90, 1.0);
            }
            let thick = max(vanilla_fog, 1.0 - exp(-distance * 0.0009 * haze));
            color = mix(color, fog, thick);
        } else {
            // Dehors, tout se fond dans la couleur exacte du ciel derrière.
            let altitude = max(ray_end.y + frame.camera_position.y - 62.0, 0.0);
            let layer = exp(-altitude / 120.0);
            // Sous la pluie, l'air s'épaissit à peine : le lointain se voile, le proche reste net.
            let density = (0.00042 + storm() * 0.0009 + golden_hour() * 0.00022) * haze;
            let air = 1.0 - exp(-distance * density * layer);
            let cave = smoothstep(0.0, 0.45, frame.eye_light_smooth.y);
            // Le brouillard du jeu ne sert ici qu'à cacher le bord du monde chargé.
            let edge = smoothstep(mix(frame.fog_start, frame.fog_end, 0.7), max(frame.fog_end, frame.fog_start + 0.01), distance);
            let amount = max(edge, air * cave);
            // Par temps gris, la brume prend la luminosité du décor au lieu de celle de l'horizon,
            // sinon elle blanchit tout l'écran.
            let behind = sky_gradient(vec3<f32>(direction.x, max(direction.y, 0.02), direction.z)) * mix(1.0, 0.6, storm());
            color = mix(color, soft_highlights(behind), amount);
        }
    }

    color += extra.rgb * volumetric_strength;

    // La vue dans l'eau et dans la lave.
    if frame.in_water > 0.001 {
        color *= mix(vec3<f32>(1.0), vec3<f32>(0.70, 0.91, 1.0), frame.in_water);
    }
    if frame.in_lava > 0.001 {
        color = mix(color, vec3<f32>(1.0, 0.33, 0.05), frame.in_lava * 0.55);
    }

    return vec4<f32>(to_display(color), input.color.a);
}
