// Nimbe : étale les lumières vives en un large halo, à un quart de résolution.

fn post(input: PostInput) -> vec4<f32> {
    let t = 1.0 / vec2<f32>(textureDimensions(bloom_half));
    var sum = textureSampleLevel(bloom_half, linear_sampler, input.uv, 0.0).rgb * 0.16;
    var weights = 0.16;
    for (var ring = 1; ring <= 3; ring++) {
        let radius = f32(ring) * 2.4;
        let weight = 0.105 / f32(ring);
        for (var i = 0; i < 8; i++) {
            let angle = (f32(i) + f32(ring) * 0.5) * 0.7853982;
            let offset = vec2<f32>(cos(angle), sin(angle)) * radius * t;
            sum += textureSampleLevel(bloom_half, linear_sampler, input.uv + offset, 0.0).rgb * weight;
            weights += weight;
        }
    }
    return vec4<f32>(sum / weights, 1.0);
}
