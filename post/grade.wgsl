// Nimbe : le halo, l'exposition et la couleur finale de l'image.

override bloom: f32 = 0.7;
override exposure: f32 = 1.0;
override saturation: f32 = 1.12;
override contrast: f32 = 1.06;
override vignette: f32 = 0.3;

fn post(input: PostInput) -> vec4<f32> {
    var color = to_linear(input.color.rgb);

    if bloom > 0.0 {
        let near = textureSampleLevel(bloom_half, linear_sampler, input.uv, 0.0).rgb;
        let wide = textureSampleLevel(bloom_quarter, linear_sampler, input.uv, 0.0).rgb;
        color += (near * 0.34 + wide * 0.86) * bloom;
    }

    // L'œil s'ouvre un peu dans le noir et se referme en plein jour.
    let adapted = mix(1.20, 0.98, smoothstep(0.08, 0.85, frame.eye_light_smooth.y));
    color *= exposure * adapted;
    color = soft_highlights(color);

    var display = to_display(color);

    // Contraste autour d'un gris moyen, puis saturation qui ménage les couleurs déjà vives.
    display = mix(vec3<f32>(0.46), display, contrast);
    let grey = luma(display);
    let vivid = max(display.r, max(display.g, display.b)) - min(display.r, min(display.g, display.b));
    let amount = 1.0 + (saturation - 1.0) * (1.0 - vivid * 0.55);
    display = mix(vec3<f32>(grey), display, amount);

    // Une touche froide dans les ombres, une touche dorée dans les lumières.
    let lifted = smoothstep(0.0, 0.5, grey);
    display *= mix(vec3<f32>(0.975, 0.99, 1.035), vec3<f32>(1.018, 1.0, 0.972), lifted);

    if vignette > 0.0 {
        let aspect = frame.resolution.x / frame.resolution.y;
        let from_centre = (input.uv - 0.5) * vec2<f32>(aspect, 1.0);
        let reach = length(from_centre) / length(vec2<f32>(aspect, 1.0) * 0.5);
        display *= 1.0 - smoothstep(0.52, 1.12, reach) * vignette;
    }

    return vec4<f32>(clamp(display, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
