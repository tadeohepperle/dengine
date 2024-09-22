#import globals.wgsl



const GIZMOS_MODE_WORLD_SPACE : u32 = 0u;
const GIZMOS_MODE_UI_LAYOUT_SPACE : u32 = 1u;
var<push_constant> gizmos_mode: u32;

struct Vertex {
    @location(0) pos:      vec3<f32>,
    @location(1) color:    vec4<f32>,
}

struct VertexOutput{
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
}

@vertex
fn vs_main(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;
    switch gizmos_mode {
        case GIZMOS_MODE_WORLD_SPACE: {
            out.clip_position = world_pos_to_ndc(vertex.pos);
        }
        case GIZMOS_MODE_UI_LAYOUT_SPACE, default: {
            out.clip_position = ui_layout_pos_to_ndc(vertex.pos.xy);
        }
    }
    out.color = vertex.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32>  {
    return in.color;
}
