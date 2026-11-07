// Nimbe : adoucit les bords à partir du contraste entre pixels voisins.
// Dernière passe : elle dessine à la taille de la fenêtre.

override antialias: bool = true;

fn brightness_at(uv: vec2<f32>) -> f32 {
    return luma(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb);
}

fn post(input: PostInput) -> vec4<f32> {
    if !antialias {
        return input.color;
    }
    let t = 1.0 / vec2<f32>(textureDimensions(previous));
    let uv = input.uv;
    let middle = luma(input.color.rgb);
    let north = brightness_at(uv + vec2<f32>(0.0, -t.y));
    let south = brightness_at(uv + vec2<f32>(0.0, t.y));
    let west = brightness_at(uv + vec2<f32>(-t.x, 0.0));
    let east = brightness_at(uv + vec2<f32>(t.x, 0.0));
    let lowest = min(middle, min(min(north, south), min(west, east)));
    let highest = max(middle, max(max(north, south), max(west, east)));
    let spread = highest - lowest;
    if spread < max(0.045, highest * 0.13) {
        return input.color;
    }

    let nw = brightness_at(uv + vec2<f32>(-t.x, -t.y));
    let ne = brightness_at(uv + vec2<f32>(t.x, -t.y));
    let sw = brightness_at(uv + vec2<f32>(-t.x, t.y));
    let se = brightness_at(uv + vec2<f32>(t.x, t.y));

    // La direction du bord, puis des lectures le long de celui-ci.
    var along = vec2<f32>((nw + ne) - (sw + se), (nw + sw) - (ne + se));
    let shrink = max((nw + ne + sw + se) * 0.03, 0.008);
    along = clamp(along / (min(abs(along.x), abs(along.y)) + shrink), vec2<f32>(-6.0), vec2<f32>(6.0)) * t;

    let inner = (textureSampleLevel(previous, linear_sampler, uv - along * 0.17, 0.0).rgb
        + textureSampleLevel(previous, linear_sampler, uv + along * 0.17, 0.0).rgb) * 0.5;
    let outer = (inner + textureSampleLevel(previous, linear_sampler, uv - along * 0.5, 0.0).rgb
        + textureSampleLevel(previous, linear_sampler, uv + along * 0.5, 0.0).rgb) / 3.0;
    let settled = luma(outer);
    let picked = select(outer, inner, settled < lowest || settled > highest);
    return vec4<f32>(picked, input.color.a);
}
