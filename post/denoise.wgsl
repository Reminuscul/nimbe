// Nimbe : lisse le résultat des rayons et de l'occlusion sans baver sur les bords des objets.

fn post(input: PostInput) -> vec4<f32> {
    let size = vec2<f32>(textureDimensions(volumetrics));
    let texel = 1.0 / size;
    let centre_depth = input.depth;
    let centre_far = select(1.0 / max(centre_depth, 1e-5), 1e5, centre_depth <= 0.0);
    var total = vec4<f32>(0.0);
    var weights = 0.0;
    for (var y = -2; y <= 2; y++) {
        for (var x = -2; x <= 2; x++) {
            let offset = vec2<f32>(f32(x), f32(y));
            let uv = input.uv + offset * texel * 1.25;
            let tap_depth = depth_at(uv);
            let tap_far = select(1.0 / max(tap_depth, 1e-5), 1e5, tap_depth <= 0.0);
            let gap = abs(tap_far - centre_far) / max(centre_far, 1e-3);
            let edge = exp(-gap * 18.0);
            let spatial = exp(-dot(offset, offset) * 0.22);
            let weight = edge * spatial + 1e-4;
            total += textureSampleLevel(volumetrics, linear_sampler, uv, 0.0) * weight;
            weights += weight;
        }
    }
    return total / weights;
}
