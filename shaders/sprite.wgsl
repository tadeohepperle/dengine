#import globals.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;

struct SpriteInstance {
    @location(0) pos:      vec2<f32>,
    @location(1) size:     vec2<f32>,
    @location(2) rotation: f32,
    @location(3) color:    vec4<f32>,
    @location(4) uv:       vec4<f32>, // aabb
}

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
}


fn world_pos_to_ndc(world_pos: vec2<f32>) -> vec4<f32>{
	let ndc_y_flip = (globals.camera_pos - world_pos) / globals.camera_size;
	
	return vec4<f32>(ndc_y_flip.x, -ndc_y_flip.y, 0.0,1.0);

}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32, instance: SpriteInstance) -> VertexOutput {
    let pos_and_uv = pos_and_uv(vertex_index, instance);
    var out: VertexOutput;
    out.clip_position = world_pos_to_ndc(pos_and_uv.pos);
    out.color = instance.color;
    out.uv = pos_and_uv.uv;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    let image_color = textureSample(t_diffuse, s_diffuse, in.uv);
    return image_color * in.color;
    // let n_coord = in.clip_position.xy / in.clip_position.w / vec2(screen.width, screen.height);
    // // let d = distance(vec2(0.5,0.5), n_coord);
    // // let s = smoothstep(0.5,0.2,d);
    // // return vec4(col.rgb * s, col.a);
    // let light = textureSample(t_light, s_light, n_coord);
    // return col * light;
}


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