#import globals.wgsl

@group(1) @binding(0)
var t_terrain: texture_2d_array<f32>;
@group(1) @binding(1)
var s_terrain: sampler;

struct Vertex {
    @location(0) pos:        vec2<f32>,
    @location(1) indices: vec3<u32>,
    @location(2) weights: vec3<f32>,
}

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) pos:        vec2<f32>,
    @location(1) indices: vec3<u32>,
    @location(2) weights: vec3<f32>,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = world_pos_to_ndc(vertex.pos);
    out.pos = vertex.pos;
    out.indices = vertex.indices;
    out.weights = vertex.weights;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    let sample_uv = in.pos * 0.2;
    let weights = accentuate_weights_exp(in.weights,8.0);
    let color_0 = textureSample(t_terrain, s_terrain, sample_uv, in.indices[0]).rgb;
    let color_1 = textureSample(t_terrain, s_terrain, sample_uv, in.indices[1]).rgb;
    let color_2 = textureSample(t_terrain, s_terrain, sample_uv, in.indices[2]).rgb;
    let color: vec3<f32> = (color_0 * weights[0] + color_1 * weights[1] + color_2 * weights[2]);
    return vec4(color,1.0);
}


fn accentuate_weights_exp(weights: vec3<f32>, exponent: f32) -> vec3<f32> {
    let pow_weights = vec3<f32>(
        pow(weights.x, exponent),
        pow(weights.y, exponent),
        pow(weights.z, exponent)
    );
    let sum = pow_weights.x + pow_weights.y + pow_weights.z;
    return pow_weights / sum;
}