package batteries
import d ".."

draw_multi_level_grid :: proc() {
	draw_grid(1, {1, 1, 1, 0.2})
	draw_grid(5, {1, 1, 1, 0.7})
}

draw_grid :: proc(grid_size: int = 1, color: d.Color = d.Color_White) {
	aspect := d.ENGINE.screen_size_f32.x / d.ENGINE.screen_size_f32.y
	y_size := d.SCENE.camera.y_height * 2
	x_size := y_size * aspect
	cam_pos := d.SCENE.camera.pos
	min := cam_pos - d.Vec2{x_size, y_size} / 2
	max := cam_pos + d.Vec2{x_size, y_size} / 2
	x_min := int(min.x) - grid_size - (int(min.x) %% grid_size)
	y_min := int(min.y) - grid_size - (int(min.y) %% grid_size)
	x_max := int(max.x) + grid_size - (int(max.x) %% grid_size)
	y_max := int(max.y) + grid_size - (int(max.y) %% grid_size)

	for x := x_min; x <= x_max; x += grid_size {
		d.gizmos_line(d.Vec2{f32(x), f32(y_min)}, d.Vec2{f32(x), f32(y_max)}, color)
	}

	for y := y_min; y <= y_max; y += grid_size {
		d.gizmos_line(d.Vec2{f32(x_min), f32(y)}, d.Vec2{f32(x_max), f32(y)}, color)
	}
}
