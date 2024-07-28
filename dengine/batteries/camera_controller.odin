package batteries

import d ".."

DEFAULT_CAMERA_CONTROLLER_SETTINGS := CameraSettings {
	min_size           = 2.0,
	max_size           = 700.0,
	default_size       = 10.0,
	lerp_speed         = 30.0,
	zoom_sensitivity   = 0.24,
	scroll_sensitivity = 0.12,
}

CameraSettings :: struct {
	min_size:           f32,
	max_size:           f32,
	default_size:       f32,
	lerp_speed:         f32,
	zoom_sensitivity:   f32,
	scroll_sensitivity: f32,
}

CameraController :: struct {
	settings: CameraSettings,
	target:   d.Camera,
	current:  d.Camera,
}

camera_controller_create :: proc(
	settings: CameraSettings = DEFAULT_CAMERA_CONTROLLER_SETTINGS,
	camera: d.Camera = {y_height = 10},
) -> CameraController {
	return CameraController{settings = settings, target = camera, current = camera}
}

camera_controller_set_immediately :: proc(cam: ^CameraController) {
	cam.current = cam.target
}

camera_controller_update :: proc(cam: ^CameraController) {
	screen_size := d.ENGINE.screen_size_f32
	input := &d.ENGINE.input

	pan_button_pressed := .Pressed in input.mouse_buttons[.Middle]
	if pan_button_pressed && input.cursor_delta != {0, 0} {
		cursor_pos := input.cursor_pos
		cursor_pos_before := cursor_pos - input.cursor_delta
		point_before := d.cursor_2d_hit_pos(cursor_pos_before, screen_size, &cam.current)
		point_after := d.cursor_2d_hit_pos(cursor_pos, screen_size, &cam.current)
		cam.target.pos += point_before - point_after
	}

	scroll := input.scroll
	if abs(scroll) > 0 {
		cursor_pos := input.cursor_pos
		// calculate new size
		size_before := cam.current.y_height
		size_after := size_before - scroll * size_before * cam.settings.zoom_sensitivity
		size_after = clamp(size_after, cam.settings.min_size, cam.settings.max_size)
		cam.target.y_height = size_after

		// calculate plane point shift
		pt_before := d.cursor_2d_hit_pos(cursor_pos, screen_size, &cam.current)
		pt_after := d.cursor_2d_hit_pos(cursor_pos, screen_size, &cam.target)
		cam.target.pos += pt_before - pt_after
	}


	s := input.delta_secs * cam.settings.lerp_speed
	cam.current.pos = d.lerp(cam.current.pos, cam.target.pos, s)
	cam.current.y_height = d.lerp(cam.current.y_height, cam.target.y_height, s)

	d.SCENE.camera = cam.current
}
