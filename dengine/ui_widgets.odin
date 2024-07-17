package dengine

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

button :: proc(title: string, id: string = "") -> Interaction {
	id := ui_id(id) if id != "" else ui_id(title)
	res := ui_button_interaction(id)

	color: Color = ---
	if res.is_pressed {
		color = Color_Red
	} else if res.is_hovered {
		color = Color_Gold
	} else {
		color = Color_Goldenrod
	}

	start_div(
		Div {
			id            = id,
			padding       = {24, 24, 8, 8},
			color         = color,
			border_radius = {20, 20, 20, 20}, //{10, 10, 10, 10},
			border_width  = {4, 4, 4, 4},
			border_color  = Color_Black,
		},
	)
	text(Text{str = title, font_size = 24, color = Color_Black, shadow = 0.0})
	end_div()

	return res

}

toggle :: proc(value: ^bool, title: string) {
	id := u64(uintptr(value))
	res := ui_button_interaction(id)
	active := value^
	if res.just_released {
		active = !active
		value^ = active
	}


	start_div(Div{flags = {.AxisX}, gap = 8})


	circle_color := Color_Green if active else Color_Gray
	if res.is_hovered {
		circle_color *= 1.5
	}
	pill_flags: DivFlags = {.AxisX, .WidthPx, .HeightPx}
	if active {
		pill_flags |= {.MainAlignEnd}
	}
	start_div(
		Div {
			id = id,
			color = Color_White,
			width = 64,
			height = 32,
			padding = {4, 4, 4, 4},
			flags = pill_flags,
			border_radius = {16, 16, 16, 16},
		},
	)

	div(
		Div {
			id = id + 1,
			color = circle_color,
			width = 24,
			height = 24,
			animation_speed = 10,
			flags = {.WidthPx, .HeightPx, .Animate, .PointerPassThrough},
			border_radius = {12, 12, 12, 12},
		},
	)
	end_div()
	text_color := Color_White if active else Color_Dark_Gray
	text(Text{str = title, font_size = 24, color = text_color})
	end_div()
}


slider :: proc(value: ^f32, min: f32 = 0, max: f32 = 1) {
	slider_width: f32 = 200
	knob_width: f32 = 24


	cache: ^UiCache = UI_MEMORY.cache
	id := u64(uintptr(value))
	val: f32 = value^

	f := (val - min) / (max - min)
	res := ui_button_interaction(id)
	if res.just_pressed {
		cached_div := cache.cached[id]
		print(cached_div.pos, cached_div.size)
		f =
			(cache.cursor_pos.x - knob_width / 2 - cached_div.pos.x) /
			(cached_div.size.x - knob_width)
		print(f)
		val = min + f * (max - min)
		cache.active_value.slider_value_start_drag = val
	} else if res.is_pressed {
		cursor_x := cache.cursor_pos.x
		cursor_x_start_active := cache.cursor_pos_start_active.x
		f_shift := (cursor_x - cursor_x_start_active) / (slider_width - knob_width)
		start_f := (cache.active_value.slider_value_start_drag - min) / (max - min)
		f = start_f + f_shift
		if f < 0 {
			f = 0
		}
		if f > 1 {
			f = 1
		}
		val = min + f * (max - min)
		value^ = val
	}

	start_div(
		Div {
			id = id,
			width = slider_width,
			height = 32,
			color = Color_Gray,
			flags = {.WidthPx, .HeightPx, .MainAlignCenter, .CrossAlignCenter},
		},
	)
	div(
		Div {
			width = knob_width,
			height = 32,
			color = Color_Light_Blue,
			flags = {.WidthPx, .HeightPx, .Absolute},
			absolute_unit_pos = {f, 0},
		},
	)
	text_str := fmt.aprintf("%f", val, allocator = context.temp_allocator)
	text(Text{str = text_str, color = Color_White, font_size = 24})
	end_div()
}


WINDOW_BG := color_from_hex("#262630")

end_window :: proc() {
	end_div()
}

start_window :: proc(title: string) {
	id := ui_id(title)
	cache := UI_MEMORY.cache
	assert(UI_MEMORY.parent_stack_len == 0)
	res := ui_button_interaction(id)
	if res.just_pressed {
		cache.active_value.window_pos_start_drag = UI_MEMORY.cache.cached[id].pos
	}

	window_pos: Vec2 = ---
	cache_entry, ok := cache.cached[id]
	if ok {
		if res.is_pressed {
			window_pos =
				cache.active_value.window_pos_start_drag +
				cache.cursor_pos -
				cache.cursor_pos_start_active
		} else {
			window_pos = cache_entry.pos
		}
	} else {
		window_pos = Vec2{0, 0}
	}
	max_pos := cache.layout_extent - cache_entry.size
	window_pos.x = clamp(window_pos.x, 0, max_pos.x)
	window_pos.y = clamp(window_pos.y, 0, max_pos.y)

	if res.is_pressed {


	}

	start_div(
		Div {
			id = id,
			offset = window_pos,
			border_radius = {5, 5, 5, 5},
			color = WINDOW_BG,
			flags = {.Absolute},
			padding = {8, 8, 8, 8},
		},
	)

	text(
		Text {
			color = Color_Gray if res.is_hovered else Color_Black,
			font_size = 18.0,
			str = title,
			shadow = 0.5,
		},
	)


	// div(Div{
	// 	padding = {}
	// })

}

red_box :: proc(size: Vec2 = {300, 200}) {
	div(Div{color = Color_Red, width = size.x, height = size.y, flags = {.WidthPx, .HeightPx}})
}

DO_SOMETHING := proc(t: string) {
	fmt.print("Do something", t)
}

StringBuilder :: strings.Builder
text_edit :: proc(value: ^strings.Builder) {

	input := UI_MEMORY.cache.input
	for c in input.chars[:input.chars_len] {
		strings.write_rune(value, c)
	}
	if .JustPressed in input.keys[.BACKSPACE] || .JustRepeated in input.keys[.BACKSPACE] {
		if strings.builder_len(value^) > 0 {
			strings.pop_rune(value)
		}
		print(strings.to_string(value^))
	}
	text_str := strings.to_string(value^)
	start_div(
		Div {
			width = 200,
			height = 32,
			flags = {.WidthPx, .HeightPx},
			color = color_gray(0.4),
			border_radius = {4, 4, 4, 4},
		},
	)
	text(
		Text {
			str = text_str,
			color = Color_Black,
			font_size = 18.0,
			shadow = 0.0,
			align = .Right,
			line_break = .Never,
		},
	)
	end_div()
}

enum_radio :: proc(value: ^$T, title: string = "") where intrinsics.type_is_enum(T) {
	start_div(
		Div {
			padding = {16, 16, 8, 8},
			color = color_from_hex("#252833"),
			border_radius = {8, 8, 8, 8},
		},
	)
	if title != "" {
		text(Text{str = title, color = Color_White * 3.0, font_size = 28.0, shadow = 0.3})
	}

	for variant in T {
		str := fmt.aprint(variant, allocator = context.temp_allocator)
		id := ui_id(str) ~ u64(uintptr(value))

		res := ui_button_interaction(id)
		if res.just_pressed {
			value^ = variant
		}
		selected := value^ == variant
		text_color := Color_White if selected else color_gray(0.3)
		if res.is_hovered {
			text_color = color_from_hex("#f7efb2")
		}
		start_div(
			Div {
				id = id,
				gap = 8,
				padding = {bottom = 4, top = 4},
				flags = {.AxisX, .CrossAlignCenter},
			},
		)
		div(
			Div {
				width = 20.0,
				height = 20.0,
				color = color_from_hex("#09090a") if selected else text_color,
				flags = {.WidthPx, .HeightPx, .MainAlignCenter, .CrossAlignCenter},
				border_radius = {6, 6, 6, 6},
				border_width = {4, 4, 4, 4},
				border_color = Color_White if selected else text_color,
			},
		)
		text(Text{str = str, color = text_color, font_size = 22.0, shadow = 0.3})
		end_div()
	}
	end_div()

}
