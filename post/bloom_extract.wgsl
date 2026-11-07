// Nimbe : garde les parties les plus lumineuses de l'image, en les réduisant de moitié.

override bloom: f32 = 0.7;

fn bright_part(uv: vec2<f32>) -> vec3<f32> {
    let display = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let brightness = max(display.r, max(display.g, display.b));
    let keep = smoothstep(0.70, 0.98, brightness);
    // Le ciel de jour est vif, mais il ne doit pas tout noyer de lumière.
    let sky_share = select(1.0, 0.24, depth_at(uv) <= 0.0);
    return to_linear(display) * keep * sky_share;
}

fn post(input: PostInput) -> vec4<f32> {
    if bloom <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let t = 1.0 / frame.resolution;
    var sum = bright_part(input.uv) * 4.0;
    sum += bright_part(input.uv + vec2<f32>(-t.x, -t.y));
    sum += bright_part(input.uv + vec2<f32>(t.x, -t.y));
    sum += bright_part(input.uv + vec2<f32>(-t.x, t.y));
    sum += bright_part(input.uv + vec2<f32>(t.x, t.y));
    return vec4<f32>(sum / 8.0, 1.0);
}
