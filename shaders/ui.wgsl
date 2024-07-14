#import globals.wgsl

@group(1) @binding(0)
var t_diffuse: texture_2d<f32>;
@group(1) @binding(1)
var s_diffuse: sampler;


const SCREEN_REFERENCE_SIZE: vec2<f32> = vec2<f32>(1920, 1080);
fn screen_size_r() -> vec2<f32> {
	return vec2(SCREEN_REFERENCE_SIZE.y * globals.screen_size.x / globals.screen_size.y, SCREEN_REFERENCE_SIZE.y);
}

struct GlyphInstance {
	@location(0) pos:    vec2<f32>,
	@location(1) size:   vec2<f32>,
	@location(2) uv:     vec4<f32>, // aabb
	@location(3) color:  vec4<f32>,
	@location(4) shadow: f32,
}

struct Vertex {
	@location(0) pos:     vec2<f32>,
	@location(1) normal:  vec2<f32>,
	@location(2) color:  vec4<f32>,
	@location(3) uv:     vec2<f32>,
}

struct VsColoredOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
}

@vertex
fn vs_colored(vertex: Vertex) -> VsColoredOut {
	let screen_size_r = vec2(SCREEN_REFERENCE_SIZE.y * globals.screen_size.x / globals.screen_size.y, SCREEN_REFERENCE_SIZE.y);
	var out: VsColoredOut;
	out.clip_position = vec4(vertex.pos / screen_size_r * 2.0  -1.0, 0.0, 1.0);
	out.color = vertex.color;
	return out;
}

@fragment
fn fs_colored(in: VsColoredOut) -> @location(0) vec4<f32> {
	return in.color;
}

struct VsTexturedOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
}

@vertex
fn vs_textured(vertex: Vertex) -> VsTexturedOut {
	var out: VsTexturedOut;
	out.clip_position = vec4(vertex.pos / screen_size_r() * 2.0  -1.0, 0.0, 1.0);
	out.color = vertex.color;
	out.uv = vertex.uv;
  	return out;
}

@fragment
fn fs_textured(in: VsTexturedOut) -> @location(0) vec4<f32> {
	return vec4<f32>(1.0);
}

struct VsGlyphOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) shadow_intensity: f32,
}

@vertex
fn vs_glyph(@builtin(vertex_index) vertex_index: u32, instance: GlyphInstance) -> VsGlyphOut {
    let u_uv: vec2<f32> = unit_uv_from_idx(vertex_index);
	let uv = ((1.0 - u_uv) * instance.uv.xy + u_uv * instance.uv.zw);
	let v_pos: vec2<f32> = instance.pos + u_uv * instance.size;
	var out: VsGlyphOut;
	out.clip_position = vec4(v_pos / screen_size_r() * 2.0  -1.0, 0.0, 1.0);
	out.color = instance.color;
	out.uv = uv;
	out.shadow_intensity = instance.shadow; 
	return out;
}

@fragment
fn fs_glyph(in: VsGlyphOut) -> @location(0) vec4<f32> {
	let sdf: f32 = textureSample(t_diffuse, s_diffuse, in.uv).r;
    var sz : vec2<u32> = textureDimensions(t_diffuse, 0);
    var dx : f32 = dpdx(in.uv.x) * f32(sz.x);
    var dy : f32 = dpdy(in.uv.y) * f32(sz.y);
    var to_pixels : f32 = 32.0 * inverseSqrt(dx * dx + dy * dy);
    let inside_factor = clamp((sdf - 0.5) * to_pixels + 0.5, 0.0, 1.0);
    
    // smoothstep(0.5 - smoothing, 0.5 + smoothing, sample);
    let shadow_alpha = (1.0 - (pow(1.0 - sdf, 2.0)) )* in.shadow_intensity * in.color.a;
    let shadow_color = vec4(0.0,0.0,0.0, shadow_alpha);
    let color = mix(shadow_color, in.color, inside_factor);
    return color; // * vec4(1.0,1.0,1.0,5.0);
}

fn unit_uv_from_idx(idx: u32) -> vec2<f32> {
    return vec2<f32>(
        f32(((idx << 1) & 2) >> 1),
        f32((idx & 2) >> 1)
    );
}
