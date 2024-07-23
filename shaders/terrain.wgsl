#import globals.wgsl

@group(1) @binding(0)
var t_terrain: texture_2d_array<f32>;
@group(1) @binding(1)
var s_terrain: sampler;

struct Vertex {
    @location(0) pos:        vec2<f32>,
    @location(1) ty_indices: vec3<u32>,
    @location(2) ty_weights: vec3<f32>,
}

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) pos:        vec2<f32>,
    @location(1) ty_indices: vec3<u32>,
    @location(2) ty_weights: vec3<f32>,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = world_pos_to_ndc(vertex.pos);
    out.pos = vertex.pos;
    out.ty_indices = vertex.ty_indices;
    out.ty_weights = vertex.ty_weights;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    let sample_uv = in.pos * 0.2;
    let color_0 = textureSample(t_terrain, s_terrain, sample_uv, in.ty_indices[0]).rgb;
    let color_1 = textureSample(t_terrain, s_terrain, sample_uv, in.ty_indices[1]).rgb;
    let color_2 = textureSample(t_terrain, s_terrain, sample_uv, in.ty_indices[2]).rgb;
    let color: vec3<f32> = (color_0 * in.ty_weights[0] + color_1 * in.ty_weights[1] + color_2 * in.ty_weights[2]) / 3.0;
    return vec4(color,1.0);
}
