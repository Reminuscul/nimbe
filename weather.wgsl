// Nimbe : la pluie et la neige, éclairées par le ciel et les lumières voisines.

fn weather(input: WeatherInput) -> vec4<f32> {
    let sky_part = ambient_sky() * input.light.y * input.light.y;
    let block_part = vec3<f32>(1.0, 0.72, 0.42) * pow(input.light.x, 2.2);
    let glow = sky_part * 1.4 + block_part * 0.9 + vec3<f32>(0.02);

    let distance = length(input.position);
    let vanish = 1.0 - smoothstep(frame.fog_start * 0.5, max(frame.fog_end, 1.0), distance);
    if input.snow {
        let color = to_linear(input.color.rgb) * glow * 1.15;
        return vec4<f32>(to_display(soft_highlights(color)), input.color.a * 0.90 * vanish);
    }
    let color = to_linear(input.color.rgb) * vec3<f32>(0.78, 0.86, 1.0) * glow * 1.25;
    return vec4<f32>(to_display(soft_highlights(color)), input.color.a * 0.55 * vanish);
}
