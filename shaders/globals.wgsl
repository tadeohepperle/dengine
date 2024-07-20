struct Globals{
    screen_size: vec2<f32>,
    cursor_pos: vec2<f32>,
    camera_pos: vec2<f32>,
    camera_size: vec2<f32>,
    time_secs: f32,
    _pad: f32,
}
@group(0) @binding(0)
var<uniform> globals: Globals;

fn world_pos_to_ndc(world_pos: vec2<f32>) -> vec4<f32>{
	let ndc = (world_pos - globals.camera_pos) / globals.camera_size;
	return vec4<f32>(ndc.x, ndc.y, 0.0,1.0);
}

const SCREEN_REFERENCE_SIZE: vec2<f32> = vec2<f32>(1920, 1080);
fn ui_layout_pos_to_ndc(ui_layout_pos: vec2<f32>) -> vec4<f32>{
	let screen_size_r = vec2(SCREEN_REFERENCE_SIZE.y * globals.screen_size.x / globals.screen_size.y, SCREEN_REFERENCE_SIZE.y);
	let ndc = ui_layout_pos / screen_size_r * 2.0  -1.0;
    return  vec4(ndc.x, -ndc.y, 0.0, 1.0);
}
