package example

import d "../dengine"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import "core:time"

Vec2 :: [2]f32
Color :: [4]f32


recorded_dt: [dynamic]f32

main :: proc() {
	d.init()
	defer {d.deinit()}

	fmt.println("sizeL", size_of(d.TerrainVertex))

	terrain_textures_paths := [?]string {
		"./assets/t_0.png",
		"./assets/t_1.png",
		"./assets/t_2.png",
		"./assets/t_3.png",
	}
	terrain_textures, terrain_textures_err := d.load_texture_array(terrain_textures_paths[:])
	assert(terrain_textures_err == "")

	d.SCENE.terrain_textures = &terrain_textures

	terrain_mesh := d.terrain_mesh_create(
		{
			d.TerrainVertex{pos = {0, 0}, indices = {0, 1, 2}, weights = {1, 0, 0}},
			d.TerrainVertex{pos = {5, 7}, indices = {0, 1, 2}, weights = {0, 1, 0}},
			d.TerrainVertex{pos = {10, 0}, indices = {0, 1, 2}, weights = {0, 0, 1}},
		},
		d.ENGINE.device,
		d.ENGINE.queue,
	)
	fmt.println(terrain_mesh)


	corn, corn_err := d.load_texture_as_tile("./assets/corn.png")
	sprite, sprite_err := d.load_texture_as_tile("./assets/can.png")
	assert(corn_err == nil)
	assert(sprite_err == nil)


	player_pos := Vec2{0, 0}
	forest := [?]Vec2{{0, 0}, {2, 0}, {3, 0}, {5, 2}, {6, 3}}

	snake := snake_create({3, 3})

	text_to_edit: strings.Builder
	strings.write_string(&text_to_edit, "I made this UI from scratch in Odin!")

	background_color: Color = Color{0, 0.01, 0.02, 1.0}
	color2: Color = d.Color_Beige
	color3: Color = d.Color_Chartreuse
	text_align: d.TextAlign

	for d.frame() {
		append(&recorded_dt, d.ENGINE.delta_secs * 1000.0)
		d.start_window("Example Window")
		btn_text := "Hold to Record"
		if d.ui_interaction(d.ui_id("record_btn")).pressed {
			btn_text = fmt.aprint(
				"Recording",
				len(d.ENGINE.time_frame_sections),
				"frames",
				allocator = context.temp_allocator,
			)
		}
		i := d.button(btn_text, id = "record_btn")
		if i.just_pressed {
			d.engine_start_record_frame_times()
		}
		if i.just_released {
			frame_times := d.engine_end_record_frame_times()
			save_frame_times_to_csv(frame_times)
		}
		d.enum_radio(&text_align, "Text Align")
		d.enum_radio(&d.ENGINE.settings.tonemapping, "Tonemapping")
		d.color_picker(&background_color, "Background")
		d.color_picker(&color2, "Color 2")
		d.color_picker(&color3, "Color 3")
		// enum_radio(&line_break, "Line Break Value")
		d.toggle(&d.ENGINE.settings.bloom_enabled, "Bloom")
		// d.check_box(&d.ENGINE.settings.bloom_enabled, "Bloom enabled")
		d.text("Bloom blend factor:")
		d.slider(&d.ENGINE.settings.bloom_settings.blend_factor)
		d.text_edit(&text_to_edit, align = .Center, font_size = d.THEME.font_size)

		d.end_window()

		d.draw_terrain_mesh(&terrain_mesh)

		for y in -5 ..= 5 {
			d.gizmos_line(Vec2{-5, f32(y)}, Vec2{5, f32(y)}, color2)
		}
		for x in -5 ..= 5 {
			d.gizmos_line(Vec2{f32(x), -5}, Vec2{f32(x), 5}, color2)
		}

		d.draw_sprite(
			d.Sprite {
				texture = sprite,
				pos = {-3, 5},
				size = {1, 2.2},
				rotation = 0,
				color = d.Color_White,
			},
		)
		// d.gizmos_rect(player_pos, Vec2{0.2, 0.8})

		for pos, i in forest {
			d.draw_sprite(
				d.Sprite {
					texture = corn,
					pos = pos,
					size = {1, 2},
					rotation = math.cos(f32(i) + d.ENGINE.total_secs),
					color = {1, 1, 1, 1},
				},
			)
		}

		keys := [?]d.Key{.LEFT, .RIGHT, .UP, .DOWN}
		directions := [?]Vec2{{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
		move: Vec2
		for k, i in keys {
			if d.key_pressed(k) {
				move += directions[i]
			}
		}
		if move != {0, 0} {
			move = linalg.normalize(move)
			player_pos += move * 20 * d.ENGINE.delta_secs
		}

		// poly := [?]d.Vec2{{-5, -5}, {-5, 0}, {0, 0}, {-5, -5}, {0, 0}, {0, -5}}
		// d.draw_color_mesh(poly[:])
		snake_update_body(&snake, d.ENGINE.hit_pos)
		snake_draw(&snake)
		d.ENGINE.settings.clear_color = background_color

	}

}

Snake :: struct {
	indices:  [dynamic]u32,
	vertices: [dynamic]d.ColorMeshVertex,
	points:   [dynamic]Vec2,
}
SNAKE_PTS :: 50
SNAKE_PT_DIST :: 0.16
SNAKE_LERP_SPEED :: 40
snake_create :: proc(head_pos: Vec2) -> Snake {
	snake: Snake
	next_pt := head_pos
	dir := Vec2{1, 0}
	for i in 0 ..< SNAKE_PTS {
		append(&snake.points, next_pt)
		next_pt += dir * SNAKE_PT_DIST
	}
	// update_body(&snake, head_pos)

	return snake
}

snake_update_body :: proc(snake: ^Snake, head_pos: Vec2) {
	prev_pos: Vec2
	snake.points[0] = head_pos
	s := d.ENGINE.delta_secs * SNAKE_LERP_SPEED
	s = clamp(s, 0, 1)
	for i in 1 ..< SNAKE_PTS {
		follow_pos := snake.points[i - 1]
		current_pos := snake.points[i]
		desired_pos := follow_pos + linalg.normalize(current_pos - follow_pos) * SNAKE_PT_DIST
		snake.points[i] = d.lerp(current_pos, desired_pos, s)
	}

	color := d.Color{0, 0, 2.0, 1.0} + 1
	if color.a > 1 {
		color.a = 1 // learned: when alpha > 1 in two regions overlapping -> alpha blending makes alpha be 0 instead. (happ)
	}
	clear(&snake.vertices)
	clear(&snake.indices)
	for i in 0 ..< SNAKE_PTS {
		pt := snake.points[i]
		is_first := i == 0
		is_last := i == SNAKE_PTS - 1
		dir: Vec2
		if is_first {
			dir = snake.points[1] - pt
		} else if is_last {
			dir = pt - snake.points[i - 1]
		} else {
			dir = snake.points[i + 1] - snake.points[i - 1]
		}

		dir = linalg.normalize(dir)
		dir_t := Vec2{-dir.y, dir.x}

		f := f32(i) / f32(SNAKE_PTS)
		body_width: f32 = 0.4 * (1.0 - f)
		append(&snake.vertices, d.ColorMeshVertex{pos = pt + dir_t * body_width, color = color})
		append(&snake.vertices, d.ColorMeshVertex{pos = pt - dir_t * body_width, color = color})
		base_idx := u32(i * 2)
		if i != SNAKE_PTS - 1 {
			append(&snake.indices, base_idx)
			append(&snake.indices, base_idx + 1)
			append(&snake.indices, base_idx + 2)
			append(&snake.indices, base_idx + 2)
			append(&snake.indices, base_idx + 3)
			append(&snake.indices, base_idx + 1)
		}
	}
	// add a circle for the head:
	circle_left := snake.vertices[0].pos
	circle_right := snake.vertices[1].pos
	dir := (circle_right - circle_left) / 2
	mapping_matrix: matrix[2, 2]f32 = {dir.x, dir.y, dir.y, -dir.x} // (1,0) mapped to dir.x, dir.y.   (0,1) mapped to dir.y, -dir.x
	head_pt := snake.points[0]
	CIRCLE_N :: 10
	for i in 1 ..< CIRCLE_N {
		angle := math.PI * f32(i) / f32(CIRCLE_N)
		unit_circle_pt := Vec2{math.cos(angle), math.sin(angle)}
		pos := head_pt + mapping_matrix * unit_circle_pt
		append(&snake.vertices, d.ColorMeshVertex{pos = pos, color = color})

		v_idx_next := u32(len(snake.vertices))
		v_idx := v_idx_next - 1
		if i == CIRCLE_N - 1 {
			v_idx_next = 0 // right side of circle (second pt of mesh)
		}
		append(&snake.indices, 1)
		append(&snake.indices, v_idx)
		append(&snake.indices, v_idx_next)
	}
}

snake_draw :: proc(snake: ^Snake) {
	white := d.TextureTile {
		texture = &d.ENGINE.ui_renderer.white_px_texture,
	}
	// for p in snake.vertices {
	// 	d.draw_sprite(
	// 		d.Sprite {
	// 			texture = white,
	// 			pos = p.pos,
	// 			size = {0.1, 0.1},
	// 			rotation = 0,
	// 			color = {1, 0, 0, 1},
	// 		},
	// 	)
	// }
	// d.draw_color_mesh_indexed(snake.vertices[:], snake.indices[:])


	// new_vertices := make([dynamic]d.ColorMeshVertex)
	// defer {delete(new_vertices)}
	// for i in snake.indices {
	// 	append(&new_vertices, snake.vertices[i])
	// }
	// d.draw_color_mesh(new_vertices[:])
	d.draw_color_mesh_indexed(snake.vertices[:], snake.indices[:])
}


save_frame_times_to_csv :: proc(times: [][d.FrameSection]d.Duration, filename := "times.csv") {
	buf: ^strings.Builder = new(strings.Builder)
	defer {
		strings.builder_destroy(buf)
		free(buf)
	}
	for t in d.FrameSection {
		fmt.sbprintf(buf, "%s,", t)
	}
	fmt.sbprint(buf, "\n")
	for sample, i in times {
		for t, t_i in d.FrameSection {
			ns := f64(sample[t])
			ms := ns / f64(time.Millisecond)
			fmt.sbprintf(buf, "%.3f,", ms)
		}
		if i != len(times) - 1 {
			fmt.sbprint(buf, "\n")
		}
	}
	os.write_entire_file(filename, buf.buf[:])
}
