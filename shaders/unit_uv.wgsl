struct PosAndUv{
    pos: vec2<f32>,
    uv: vec2<f32>,
}

fn pos_and_uv(vertex_index: u32, instance: SpriteInstance) -> PosAndUv{
    var out: PosAndUv;
    let size = instance.size;
    let size_half = size / 2.0;
    let u_uv = unit_uv_from_idx(vertex_index);
    out.uv = (u_uv * instance.uv.xy) + ((vec2(1.0) -u_uv )* instance.uv.zw);

    let rot = instance.rotation;
    let pos = ((vec2(u_uv.x, u_uv.y)) * size) - size_half;
    let pos_rotated = vec2(
        cos(rot)* pos.x - sin(rot)* pos.y,
        sin(rot)* pos.x + cos(rot)* pos.y,     
    );
    out.pos = pos_rotated + instance.pos;
    return out;
}

fn unit_uv_from_idx(idx: u32) -> vec2<f32> {
    return vec2<f32>(
        f32(((idx << 1) & 2) >> 1),
        f32((idx & 2) >> 1)
    );
}