package dengine

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:strings"


UiTheme :: struct {
	font_size:               f32,
	font_size_sm:            f32,
	font_size_lg:            f32,
	text_shadow:             f32,
	disabled_opacity:        f32,
	border_width:            BorderWidth,
	border_radius:           BorderRadius,
	border_radius_sm:        BorderRadius,
	control_standard_height: f32,
	text:                    Color,
	text_secondary:          Color,
	background:              Color,
	success:                 Color,
	highlight:               Color,
	surface:                 Color,
	surface_border:          Color,
	surface_deep:            Color,
}

// not a constant, so can be switched out.
THEME: UiTheme = UiTheme {
	font_size               = 22,
	font_size_sm            = 18,
	font_size_lg            = 28,
	text_shadow             = 0.4,
	disabled_opacity        = 0.4,
	border_width            = BorderWidth{2.0, 2.0, 2.0, 2.0},
	border_radius           = BorderRadius{8.0, 8.0, 8.0, 8.0},
	border_radius_sm        = BorderRadius{4.0, 4.0, 4.0, 4.0},
	control_standard_height = 36.0,
	text                    = color_from_hex("#EFF4F7"),
	text_secondary          = color_from_hex("#777F8B"),
	background              = color_from_hex("#252833"),
	success                 = color_from_hex("#68B767"),
	highlight               = color_from_hex("#F7EFB2"),
	surface                 = color_from_hex("#577383"),
	surface_border          = color_from_hex("#8CA6BE"),
	surface_deep            = color_from_hex("#16181D"),
}


button :: proc(title: string, id: string = "") -> BtnInteraction {
	id := ui_id(id) if id != "" else ui_id(title)
	res := ui_btn_interaction(id)

	color: Color = ---
	border_color: Color = ---
	if res.is_pressed {
		color = THEME.surface_deep
		border_color = THEME.text
	} else if res.is_hovered {
		color = THEME.surface_border
		border_color = THEME.text
	} else {
		color = THEME.surface
		border_color = THEME.surface_border
	}

	start_div(
		Div {
			lerp_speed = 16,
			flags = {.LerpStyle, .CrossAlignCenter, .HeightPx, .AxisX},
			padding = {12, 12, 0, 0},
			height = THEME.control_standard_height,
			color = color,
			border_color = border_color,
			border_radius = THEME.border_radius,
			border_width = THEME.border_width,
		},
		id,
	)
	text(
		Text {
			str = title,
			font_size = THEME.font_size,
			color = THEME.text,
			shadow = THEME.text_shadow,
		},
	)
	end_div()

	return res

}

toggle :: proc(value: ^bool, title: string) {
	id := u64(uintptr(value))
	res := ui_btn_interaction(id)
	active := value^
	if res.just_pressed {
		active = !active
		value^ = active
	}


	start_div(
		Div {
			height = THEME.control_standard_height,
			flags = {.AxisX, .CrossAlignCenter, .HeightPx},
			gap = 8,
		},
	)

	circle_color: Color = ---
	pill_color: Color = ---
	text_color: Color = ---

	if active {
		circle_color = THEME.text
		text_color = THEME.text
		pill_color = THEME.success
	} else {
		circle_color = THEME.text
		text_color = THEME.text_secondary
		pill_color = THEME.text_secondary
	}
	if res.is_hovered {
		pill_color = highlight(pill_color)
	}
	pill_flags: DivFlags = {.AxisX, .WidthPx, .HeightPx}
	if active {
		pill_flags |= {.MainAlignEnd}
	}
	start_div(
		Div {
			color = pill_color,
			width = 64,
			height = 32,
			padding = {4, 4, 4, 4},
			flags = pill_flags,
			border_radius = {16, 16, 16, 16},
		},
		id = id,
	)
	div(
		Div {
			color = circle_color,
			width = 24,
			height = 24,
			lerp_speed = 10,
			flags = {.WidthPx, .HeightPx, .LerpStyle, .LerpTransform, .PointerPassThrough},
			border_radius = {12, 12, 12, 12},
		},
		id = derived_id(id),
	)
	end_div()
	text(
		Text {
			str = title,
			color = text_color,
			font_size = THEME.font_size,
			shadow = THEME.text_shadow,
		},
	)
	end_div()
}


slider :: proc {
	slider_f32,
	slider_f64,
	slider_int,
}

slider_int :: proc(value: ^int, min: int = 0, max: int = 1, id: UI_ID = 0) {
	value_f32 := f32(value^)
	slider_f32(&value_f32, f32(min), f32(max))
	value^ = int(math.round(value_f32))
}

// todo! maybe the slider_f32 should be the wrapper instead.
slider_f64 :: proc(value: ^f64, min: f64 = 0, max: f64 = 1, id: UI_ID = 0) {
	value_f32 := f32(value^)
	id := id if id != 0 else u64(uintptr(value))
	slider_f32(&value_f32, f32(min), f32(max), id = id)
	value^ = f64(value_f32)
}

slider_f32 :: proc(value: ^f32, min: f32 = 0, max: f32 = 1, id: UI_ID = 0) {
	slider_width: f32 = 192
	knob_width: f32 = 24

	cache: ^UiCache = UI_MEMORY.cache
	id := id if id != 0 else u64(uintptr(value))
	val: f32 = value^

	f := (val - min) / (max - min)
	res := ui_btn_interaction(id)

	if res.just_pressed {
		cached := cache.cached[id]
		f = (cache.cursor_pos.x - knob_width / 2 - cached.pos.x) / (cached.size.x - knob_width)
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
			width = slider_width,
			height = THEME.control_standard_height,
			flags = {.WidthPx, .HeightPx, .AxisX, .CrossAlignCenter, .MainAlignCenter},
		},
	)
	div(
		Div {
			width = 1,
			height = 32,
			color = THEME.text_secondary,
			border_radius = THEME.border_radius_sm,
			flags = {.WidthFraction, .HeightPx, .Absolute},
			absolute_unit_pos = {0.5, 0.5},
		},
		id = id,
	)
	knob_border_color: Color = THEME.surface if !res.is_hovered else THEME.surface_border
	div(
		Div {
			width = knob_width,
			height = THEME.control_standard_height,
			color = THEME.surface_deep,
			border_width = THEME.border_width,
			border_color = knob_border_color,
			flags = {.WidthPx, .HeightPx, .Absolute, .LerpStyle, .PointerPassThrough},
			border_radius = THEME.border_radius_sm,
			absolute_unit_pos = {f, 0.5},
			lerp_speed = 20.0,
		},
		id = derived_id(id),
	)
	text_str := fmt.aprintf("%f", val, allocator = context.temp_allocator)
	text(
		Text {
			str = text_str,
			color = THEME.text,
			font_size = THEME.font_size,
			shadow = THEME.text_shadow,
		},
	)

	end_div()
}

end_window :: proc() {
	end_div()
}

start_window :: proc(title: string) {
	id := ui_id(title)
	cache := UI_MEMORY.cache
	assert(UI_MEMORY.parent_stack_len == 0)
	res := ui_btn_interaction(id)
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
			offset = window_pos,
			border_radius = {5, 5, 5, 5},
			color = THEME.background,
			flags = {.Absolute},
			padding = {8, 8, 8, 8},
		},
		id = id,
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

	id := u64(uintptr(value))
	res := ui_btn_interaction(id)

	input := UI_MEMORY.cache.input

	if res.is_focused {
		for c in input.chars[:input.chars_len] {
			strings.write_rune(value, c)
		}
		if .JustPressed in input.keys[.BACKSPACE] || .JustRepeated in input.keys[.BACKSPACE] {
			if strings.builder_len(value^) > 0 {
				strings.pop_rune(value)
			}
			print(strings.to_string(value^))
		}
	}

	text_str := strings.to_string(value^)
	bg_color := color_gray(0.4) if res.is_focused else color_gray(0.2)
	start_div(
		Div {
			width = 400,
			height = 300,
			flags = {.WidthPx, .HeightPx, .MainAlignCenter, .LayoutAsText},
			color = bg_color,
			border_radius = {4, 4, 4, 4},
		},
		id = id,
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
	div(Div{width = 8, height = 8, color = Color_Chocolate, flags = {.WidthPx, .HeightPx}})
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
	start_div(Div{padding = {16, 16, 8, 8}, border_radius = {8, 8, 8, 8}})
	if title != "" {
		text(
			Text {
				str = title,
				color = THEME.text,
				font_size = THEME.font_size_lg,
				shadow = THEME.text_shadow,
			},
		)
	}

	for variant in T {
		str := fmt.aprint(variant, allocator = context.temp_allocator)
		id := ui_id(str) ~ u64(uintptr(value))

		res := ui_btn_interaction(id)
		if res.just_pressed {
			value^ = variant
		}
		selected := value^ == variant
		text_color: Color = ---
		knob_inner_color: Color = ---
		if selected || res.is_pressed {
			text_color = THEME.text
			knob_inner_color = THEME.surface_deep
		} else if res.is_hovered {
			text_color = THEME.highlight
			knob_inner_color = THEME.text_secondary
		} else {
			text_color = THEME.text_secondary
			knob_inner_color = THEME.text_secondary
		}
		start_div(
			Div {
				height = THEME.control_standard_height,
				gap = 8,
				flags = {.AxisX, .CrossAlignCenter, .HeightPx},
			},
			id = id,
		)
		div(
			Div {
				width = 24.0,
				height = 24.0,
				color = knob_inner_color,
				border_color = text_color,
				flags = {.WidthPx, .HeightPx, .MainAlignCenter, .CrossAlignCenter},
				border_radius = THEME.border_radius,
				border_width = {4, 4, 4, 4},
			},
		)
		text(
			Text {
				str = "Hello Hello Hello Hello Hello",
				color = text_color,
				font_size = THEME.font_size,
				shadow = THEME.text_shadow,
			},
		)
		end_div()
	}
	end_div()

}


// COLOR_PICKER_DIALOG_ID := ui_id("color_picker_dialog")
// COLOR_PICKER_SQUARE_ID := ui_id("color_picker_square")
// COLOR_PICKER_HUE_SLIDER_ID := ui_id("color_picker_slider_hue")
color_picker :: proc(value: ^Color, title: string = "", id: UI_ID = 0) {
	// use some local variables to remember the last valid values, because:
	// - in HSV if value = 0 then saturation and hue not reconstructable
	// - if saturation = 0 then hue not reconstructable
	@(thread_local)
	last_id: UI_ID
	@(thread_local)
	last_hue: f64
	@(thread_local)
	last_saturation: f64

	id: UI_ID = u64(uintptr(value)) if id == 0 else id
	dialog_id := derived_id(id)
	square_id := derived_id(dialog_id)
	hue_slider_id := derived_id(square_id)

	color := value^
	color_rgb := Rgb{f64(color.r), f64(color.g), f64(color.b)}
	color_hsv := rbg_to_hsv(color_rgb)


	cache := UI_MEMORY.cache
	res_knob := ui_btn_interaction(id, manually_unfocus = false)
	res_dialog := ui_btn_interaction(dialog_id, manually_unfocus = false)
	res_square := ui_btn_interaction(square_id, manually_unfocus = false)
	res_hue_slider := ui_btn_interaction(hue_slider_id, manually_unfocus = false)

	cached_square, ok := cache.cached[square_id]
	if ok {
		if res_square.is_pressed {
			unit_pos_in_square: Vec2 = (cache.cursor_pos - cached_square.pos) / cached_square.size
			unit_pos_in_square.x = clamp(unit_pos_in_square.x, 0, 1)
			unit_pos_in_square.y = clamp(unit_pos_in_square.y, 0, 1)
			color_hsv.s = f64(unit_pos_in_square.x)
			color_hsv.v = f64(1.0 - unit_pos_in_square.y)

		}
	}

	cached_hue_slider, h_ok := cache.cached[hue_slider_id]
	if h_ok {
		if res_hue_slider.is_pressed {
			fract_in_slider: f32 =
				(cache.cursor_pos.x - cached_square.pos.x) / cached_square.size.x
			fract_in_slider = clamp(fract_in_slider, 0, 1)
			color_hsv.h = f64(fract_in_slider) * 359.8 // so that we dont loop around
		}
	}
	color_picker_ids := [?]UI_ID{id, dialog_id, square_id, hue_slider_id}
	show_dialog := cache_any_active_or_focused(cache, color_picker_ids[:])


	if show_dialog && id == last_id {
		if color_hsv.v == 0 {
			assert(color_hsv.s == 0)
			color_hsv.h = last_hue
			color_hsv.s = last_saturation
		} else if color_hsv.s == 0 {
			color_hsv.h = last_hue
			last_saturation = color_hsv.s
		} else {
			last_hue = color_hsv.h
			last_saturation = color_hsv.s
		}
	} else {
		last_id = id
		last_hue = color_hsv.h
		last_saturation = color_hsv.s
	}


	start_div(
		Div {
			height = THEME.control_standard_height,
			gap = 8,
			flags = {.AxisX, .CrossAlignCenter, .HeightPx},
		},
		id = id,
	)

	border_color: Color = ---
	if res_knob.is_hovered {
		border_color = THEME.text
	} else {
		border_color = THEME.surface_border
	}


	div(
		Div {
			color = color,
			border_radius = THEME.border_radius,
			border_color = border_color,
			border_width = THEME.border_width,
			width = 48,
			height = 32,
			flags = {.WidthPx, .HeightPx},
		},
		id = id,
	)


	if title != "" {
		text(
			Text {
				str = title,
				color = THEME.text_secondary,
				font_size = THEME.font_size,
				shadow = THEME.text_shadow,
			},
		)
	}

	if show_dialog {
		start_div(
			Div {
				padding           = Padding{16, 16, 16, 16},
				color             = THEME.surface_deep,
				border_width      = THEME.border_width,
				border_radius     = THEME.border_radius,
				border_color      = THEME.surface_border,
				absolute_unit_pos = Vec2{0, 0},
				z_bias            = 1,
				flags             = {.Absolute},
				offset            = {54, -100}, // {54, 4}
				gap               = 8,
			},
			id = dialog_id,
		)

		colors_n_x := 10
		colors_n_y := 10
		colors := make([]Color, colors_n_x * colors_n_y, allocator = context.temp_allocator)
		cross_hair_pos := Vec2{f32(color_hsv.s), 1.0 - f32(color_hsv.v)}
		for y in 0 ..< colors_n_y {
			for x in 0 ..< colors_n_x {
				va_fact := 1.0 - f64(y) / f64(colors_n_y - 1)
				sat_fact := f64(x) / f64(colors_n_x - 1)
				col := color_from_hsv(last_hue, sat_fact, va_fact)
				colors[y * colors_n_x + x] = col
			}
		}
		start_div(Div{}, id = square_id)
		color_gradient_rect(
			ColorGradientRect {
				width_px = 168,
				height_px = 168,
				colors_n_x = colors_n_x,
				colors_n_y = colors_n_y,
				colors = colors,
			},
		)
		crosshair_at_unit_pos(cross_hair_pos)
		end_div() // square area.

		hue_colors_n := 20
		hue_colors := make([]Color, hue_colors_n * 2, allocator = context.temp_allocator)
		for x in 0 ..< hue_colors_n {
			hue_fact := f64(x) / f64(hue_colors_n - 1) * 360.0
			col := color_from_hsv(hue_fact, 1, 1)
			hue_colors[x] = col
			hue_colors[x + hue_colors_n] = col
		}
		hue_slider_cross_hair_pos := Vec2{f32(color_hsv.h) / 360.0, 0.5}
		start_div(Div{}, id = hue_slider_id)
		color_gradient_rect(
			ColorGradientRect {
				width_px = 168,
				height_px = 16,
				colors_n_x = hue_colors_n,
				colors_n_y = 2,
				colors = hue_colors,
			},
		)
		crosshair_at_unit_pos(hue_slider_cross_hair_pos)
		end_div() // hue slider area


		// slider(&color_hsv.h, 0.0, 360.0, id = COLOR_PICKER_SLIDER_1_ID)
		// if color_hsv.v == 0 || color_hsv.s == 0 {
		// 	last_hue = color_hsv.h
		// }
		// // slider(&color_hsv.s, 0.0, 1.0, id = COLOR_PICKER_SLIDER_2_ID)
		// // slider(&color_hsv.v, 0.0, 1.0, id = COLOR_PICKER_SLIDER_3_ID)

		value^ = rbg_to_color(hsv_to_rgb(color_hsv))
		end_div() // dialog
	}

	end_div()
}

crosshair_at_unit_pos :: proc(unit_pos: Vec2) {
	start_div(Div{flags = {.Absolute, .WidthPx, .HeightPx}, absolute_unit_pos = unit_pos})
	div(
		Div {
			width = 16,
			height = 16,
			color = {1.0, 1.0, 1.0, 0.0},
			border_radius = {8, 8, 8, 8},
			border_width = {2, 2, 2, 2},
			border_color = THEME.text,
			flags = {.WidthPx, .HeightPx, .Absolute},
			absolute_unit_pos = Vec2{0.5, 0.5},
		},
	)
	end_div()
}

ColorGradientRect :: struct {
	width_px:   f32,
	height_px:  f32,
	colors_n_x: int, // number of columns of colors
	colors_n_y: int, // number of rows of colors
	colors:     []Color, // the colors should be in here row-wise, e.g. first row [a,b,c] then second row [d,e,f], ...
}

color_gradient_rect :: proc(rect: ColorGradientRect, id: UI_ID = 0) {

	// Big problem right now: the verts are always thinking they are sitting on the edge and thus getting
	// sdfs of 0.0 whihc amount to 0.5 when smoothed. Makes color grey instead of white.
	// negative border_width can help but not completely.

	assert(rect.colors_n_x >= 2)
	assert(rect.colors_n_y >= 2)
	assert(len(rect.colors) == rect.colors_n_x * rect.colors_n_y)
	set_size :: proc(data: ^ColorGradientRect, max_size: Vec2) -> (used_size: Vec2) {
		return Vec2{data.width_px, data.height_px}
	}
	add_elements :: proc(
		data: ^ColorGradientRect,
		pos: Vec2,
		size: Vec2,
		primitives: ^Primitives,
		pre_batches: ^[dynamic]PreBatch,
	) {
		n_x := data.colors_n_x
		n_y := data.colors_n_y
		border_width := BorderWidth{-10.0, -10.0, -10.0, -10.0}
		vertex_idx := u32(len(primitives.vertices))
		// add vertices:
		for y in 0 ..< n_y {
			for x in 0 ..< n_x {
				i := y * n_x + x
				color := data.colors[i]
				unit_pos := Vec2{f32(x) / f32(n_x - 1), f32(y) / f32(n_y - 1)}
				vertex_pos := pos + size * unit_pos
				append(
					&primitives.vertices,
					UiVertex {
						pos = vertex_pos,
						color = color,
						border_radius = {0, 0, 0, 0},
						size = size,
						flags = 0,
						border_width = border_width,
						border_color = {},
					},
				)
			}
		}
		// add indices: 
		for y in 0 ..< n_y - 1 {
			for x in 0 ..< n_x - 1 {
				idx_0 := vertex_idx + u32(y * n_x + x)
				idx_1 := idx_0 + u32(n_x)
				idx_2 := idx_0 + u32(n_x) + 1
				idx_3 := idx_0 + 1
				append(&primitives.indices, idx_0)
				append(&primitives.indices, idx_1)
				append(&primitives.indices, idx_2)
				append(&primitives.indices, idx_0)
				append(&primitives.indices, idx_2)
				append(&primitives.indices, idx_3)
			}
		}
		append(
			pre_batches,
			PreBatch{kind = .Rect, end_idx = len(primitives.indices), texture = nil},
		)
	}

	custom_ui_element(rect, set_size, add_elements)

}
