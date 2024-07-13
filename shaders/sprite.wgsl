#import globals.wgsl
#import unit_uv.wgsl

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
    return image_color.rgba * in.color * 3.0;
}