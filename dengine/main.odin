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

	@(static)
	text_to_edit: StringBuilder
	strings.write_string(&text_to_edit, "This is text.")

	for engine_start_frame(&engine) {


		start_div(
			Div {
				padding = {10, 10, 10, 10},
				color   = {}, //   color_gray(0.2),
				width   = 1,
				height  = 400,
				flags   = {.WidthFraction, .HeightPx},
			},
		)
		start_div(Div{color = Color_White})
		text(
			Text {
				str       = "Hello! I am Tadeo.\nI would like to buy a sandwich! :)\nThis is gonna be the best day of my li i life, .... saksakslas",
				// str       = "What is this?\nHello I want to buy a big fat sandwich, I want to buy a big fat sandwich, I want to buy a big fat sandwich, I want to buy a big fat sandwich, ",
				font_size = 24.0,
				shadow    = 0.4,
				color     = Color_White,
			},
		)
		end_div()

		@(thread_local)
		value: f32
		slider(&value, 0, 1)

		@(thread_local)
		open: bool
		button("The first button", "btn2")
		btn := button("Click me!", "btn1")
		if btn.just_pressed {
			open = !open
			print("just_pressed")
		}
		if btn.just_released {
			print("just_released")
		}

		toggle(&open, "show panel")
		if open {
			start_div(Div{padding = {10, 10, 10, 10}, color = Color_Blue})
			text(Text{str = "Hello!", font_size = 100, color = Color_White})
			end_div()
		}


		@(static)
		border_width: BorderWidth = {
			top    = 20,
			left   = 20,
			bottom = 20,
			right  = 20,
		}
		@(static)
		border_radius: BorderRadius = {
			top_left     = 120,
			bottom_left  = 200,
			top_right    = 30,
			bottom_right = 60,
		}
		@(static)
		size := Vec2{700, 600}
		@(static)
		should_clip := true
		@(static)
		line_break: LineBreak
		@(static)
		text_align: TextAlign
		slider(&border_radius.top_left, 0, 200)
		slider(&border_radius.top_right, 0, 200)
		slider(&border_radius.bottom_right, 0, 200)
		slider(&border_radius.bottom_left, 0, 200)
		slider(&border_width.top, 0, 200)
		slider(&border_width.left, 0, 200)
		slider(&border_width.bottom, 0, 200)
		slider(&border_width.right, 0, 200)
		slider(&size.x, 0, 800)
		slider(&size.y, 0, 800)
		flags: DivFlags = {.WidthPx, .HeightPx, .Absolute}
		toggle(&should_clip, "should clip")
		if should_clip {
			flags |= {.ClipContent}
		}
		start_div(
			Div {
				color = Color_Green,
				width = size.x,
				height = size.y,
				flags = flags,
				absolute_unit_pos = {1, 0.5},
				padding = {},
				border_color = Color_White,
				border_width = border_width,
				border_radius = border_radius,
				offset = Vec2{-300, 300},
			},
		)
		text(
			Text {
				font_size = 24.0,
				str = lorem(300),
				shadow = 0.5,
				color = Color_White,
				line_break = line_break,
				align = text_align,
			},
		)
		end_div()

		end_div()

		start_window("Hello")
		text_edit(&text_to_edit)
		red_box()
		enum_radio(&line_break, "Line Break Value")
		enum_radio(&text_align, "Text Align")
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

		engine.settings.bloom_enabled = .Pressed in engine.input.keys[.SPACE]
		keys := [?]Key{.LEFT, .RIGHT, .UP, .DOWN}
		directions := [?]Vec2{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

		for k, i in keys {
			if .Pressed in engine.input.keys[k] {
				player_pos += directions[i] * 20 * engine.delta_secs
			}
		}

		engine_end_frame(&engine, scene)
	}

}
