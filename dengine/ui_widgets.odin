package dengine

import "core:fmt"
import "core:math"
import "core:mem"

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
			flags = {.WidthPx, .HeightPx, .Animate},
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

CONSTCOLOR := color("Hello")

color :: proc(a: string) -> Color {
	if a[0] == 'a' {
		return {0, 1, 1, 1}
	}
	return {1, 1, 1, 1}
}


lorem :: proc(letters := 300) -> string {
	LOREM := "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.   "
	letters := min(letters, len(LOREM))
	return LOREM[0:letters]
}
