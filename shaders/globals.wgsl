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