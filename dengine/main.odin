package dengine

import "core:fmt"
import "core:math"
import "core:strings"

import wgpu "vendor:wgpu"

main :: proc() {
	engine: Engine
	engine_create(&engine, DEFAULT_ENGINE_SETTINGS)
	defer {engine_destroy(&engine)}
	scene := scene_create()
	defer {scene_destroy(scene)}

	corn_tex, _ := texture_from_image_path(engine.device, engine.queue, path = "./assets/corn.png")
	corn := TextureTile {
		texture = &corn_tex,
		uv      = {{0, 0}, {1, 1}},
	}
	sprite_tex, err := texture_from_image_path(
		engine.device,
		engine.queue,
		path = "./assets/can.png",
	)
	sprite := TextureTile {
		texture = &sprite_tex,
		uv      = {{0, 0}, {1, 1}},
	}
	if err != nil {
		print(err)
		panic("c")
	}

	player_pos := Vec2{0, 0}
	forest := [?]Vec2{{0, 0}, {2, 0}, {3, 0}, {5, 2}, {6, 3}}


	text_to_edit: StringBuilder
	strings.write_string(
		&text_to_edit,
		"This is text that I like to share with the entire Wärld!",
	)

	border_width: BorderWidth = {
		top    = 20,
		left   = 20,
		bottom = 20,
		right  = 20,
	}
	border_radius: BorderRadius = {
		top_left     = 120,
		bottom_left  = 30,
		top_right    = 30,
		bottom_right = 60,
	}
	size := Vec2{700, 600}
	should_clip := true
	line_break: LineBreak
	text_align: TextAlign

	background_color: Color = Color_Beige
	color2: Color = Color_Dark_Gray
	color3: Color = Color_Chartreuse

	for engine_start_frame(&engine) {
		start_window("Example Window")

		// enum_radio(&text_align, "Text Align")
		// color_picker(&background_color, "Background")
		// color_picker(&color2, "Color 2")
		// color_picker(&color3, "Color 3")
		// enum_radio(&line_break, "Line Break Value")
		// check_box(&engine.settings.bloom_enabled, "Bloom enabled")
		text_edit(&text_to_edit, align = .Center, font_size = THEME.font_size_sm)
		// button("Hello!")
		end_window()
		append(
			&scene.sprites,
			Sprite {
				texture = sprite,
				pos = player_pos,
				size = {1, 2.2},
				rotation = 0,
				color = Color_White,
			},
		)

		for y in -5 ..= 5 {
			gizmos_line(&engine.gizmos_renderer, Vec2{-5, f32(y)}, Vec2{5, f32(y)}, Color_Sky_Blue)
		}
		for x in -5 ..= 5 {
			gizmos_line(&engine.gizmos_renderer, Vec2{f32(x), -5}, Vec2{f32(x), 5}, Color_Sky_Blue)
		}

		gizmos_rect(&engine.gizmos_renderer, player_pos, Vec2{0.2, 0.8})

		for pos, i in forest {
			append(
				&scene.sprites,
				Sprite {
					texture = corn,
					pos = pos,
					size = {1, 2},
					rotation = math.cos(f32(i) + engine.total_secs),
					color = Color_White,
				},
			)
		}

		// append(
		// 	&scene.sprites,
		// 	Sprite{texture = corn, pos = {0, 0}, size = {1, 1}, rotation = 0, color = Color_Aqua},
		// )

		keys := [?]Key{.LEFT, .RIGHT, .UP, .DOWN}
		directions := [?]Vec2{{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
		engine.settings.clear_color = background_color


		for k, i in keys {
			if .Pressed in engine.input.keys[k] {
				player_pos += directions[i] * 20 * engine.delta_secs
			}
		}

		engine_end_frame(&engine, scene)
	}

}
