package dengine


import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:os"
import wgpu "vendor:wgpu"

SCREEN_REFERENCE_SIZE :: [2]u32{1920, 1080}

NO_ID: UI_ID = 0
UI_ID :: u64

ui_id :: proc(str: string) -> UI_ID {
	return hash.crc64_xz(transmute([]byte)str)
}

Interaction :: struct {
	just_pressed:  bool,
	is_hovered:    bool,
	is_pressed:    bool,
	just_released: bool,
}


ui_button_interaction :: proc(id: UI_ID, cache: ^UiCache = UI_MEMORY.cache) -> (res: Interaction) {
	cache := UI_MEMORY.cache
	cached, ok := cache.cached[id]

	if !ok {
		return Interaction{}
	}
	press := cache.mouse_buttons[.Left]
	cursor_in_bounds :=
		cache.cursor_pos.x >= cached.pos.x &&
		cache.cursor_pos.y >= cached.pos.y &&
		cache.cursor_pos.x <= cached.pos.x + cached.size.x &&
		cache.cursor_pos.y <= cached.pos.y + cached.size.y
	if cursor_in_bounds && cache.hot_active_id == 0 || cache.hot_active_id == id {
		res.is_hovered = true
	}
	if cache.hot_active_id == id {
		if cache.is_active {
			// ACTIVE
			res.is_pressed = true
			if press == .JustReleased {
				if cursor_in_bounds {
					res.just_released = true
					cache.is_active = false
				} else {
					cache.hot_active_id = 0
				}
			}
		} else {
			// HOT
			if cursor_in_bounds {
				if press == .JustPressed {
					res.is_pressed = true
					res.just_pressed = true
					cache.is_active = true
					cache.cursor_pos_start_active = cache.cursor_pos
				}
			} else {
				cache.hot_active_id = 0
			}
		}
	} else {
		// NONE
		if cursor_in_bounds && cache.hot_active_id == 0 {
			cache.hot_active_id = id
			cache.is_active = false
		}
	}
	return
}


ActiveValue :: struct #raw_union {
	slider_value_start_drag: f32,
	window_pos_start_drag:   Vec2,
}

UiCache :: struct {
	cached:                  map[UI_ID]CachedDiv,
	hot_active_id:           UI_ID, // if "" -> none.
	is_active:               bool, // refers to hot_active_id: if false -> hot, if true -> active
	cursor_pos_start_active: Vec2,
	active_value:            ActiveValue,
	mouse_buttons:           [MouseButton]KeyState,
	cursor_pos:              Vec2, // (scaled to reference cursor pos)
	layout_extent:           Vec2,
}

CachedDiv :: struct {
	pos:        Vec2,
	size:       Vec2,
	color:      Color,
	generation: int,
}

ComputedGlyph :: struct {
	pos:  Vec2,
	size: Vec2,
	uv:   Aabb,
}

HotActive :: enum {
	None,
	Hot,
	Active,
}

UiBatches :: struct {
	vertices:         [dynamic]UiVertex,
	indices:          [dynamic]u32,
	glyphs_instances: [dynamic]UiGlyphInstance,
	batches:          [dynamic]UiBatch,
}

UiGlyphInstance :: struct {
	pos:    Vec2,
	size:   Vec2,
	uv:     Aabb,
	color:  Color,
	shadow: f32,
}

UI_VERTEX_FLAG_TEXTURED :: 1
UI_VERTEX_FLAG_RIGHT_VERTEX :: 2
UI_VERTEX_FLAG_BOTTOM_VERTEX :: 4

UiVertex :: struct {
	pos:           Vec2,
	size:          Vec2, // size of the rect this is part of
	uv:            Vec2,
	color:         Color,
	border_color:  Color,
	border_radius: BorderRadius,
	border_width:  BorderWidth,
	flags:         u32,
}

UiBatch :: struct {
	start_idx:  int,
	end_idx:    int,
	kind:       UiBatchKind,
	texture:    ^Texture,
	clipped_to: Aabb,
}

UiBatchKind :: enum {
	Rect,
	Glyph,
}

@(private)
@(thread_local)
UI_MEMORY: UiMemory
MAX_UI_ELEMENTS :: 10000
MAX_GLYPHS :: 100000
MAX_PARENT_LEVELS :: 124
UiMemory :: struct {
	glyphs:             [MAX_GLYPHS]ComputedGlyph,
	glyphs_len:         int,
	elements:           [MAX_UI_ELEMENTS]UiElement,
	elements_len:       int,
	parent_stack:       [MAX_PARENT_LEVELS]int, // the last item in this stack is the index of the current parent
	parent_stack_len:   int,
	default_font:       Font,
	default_font_color: Color,
	default_font_size:  f32,
	cache:              ^UiCache,
}

UiElement :: union {
	DivWithComputed,
	TextWithComputed,
}

DivWithComputed :: struct {
	using div:         Div,
	pos:               Vec2, // computed
	size:              Vec2, // computed
	content_size:      Vec2, // computed
	child_count:       int, // direct children of this Div
	child_count_total: int, // number elements in the hierarchy under this div.
}

TextWithComputed :: struct {
	using text:       Text,
	pos:              Vec2, // computed
	size:             Vec2, // computed
	glyphs_start_idx: int,
	glyphs_end_idx:   int,
}

Div :: struct {
	width:             f32,
	height:            f32,
	padding:           Padding,
	offset:            Vec2,
	absolute_unit_pos: Vec2, // only taken into account if flag .Absolute set
	color:             Color,
	gap:               f32, // gap between children
	flags:             DivFlags,
	z_index:           i16,
	id:                UI_ID,
	texture:           TextureTile,
	border_radius:     BorderRadius,
	border_width:      BorderWidth,
	border_color:      Color,
	animation_speed:   f32, //   (lerp speed)
}

Padding :: struct {
	left:   f32,
	right:  f32,
	top:    f32,
	bottom: f32,
}

BorderRadius :: struct {
	top_left:     f32,
	top_right:    f32,
	bottom_right: f32,
	bottom_left:  f32,
}

BorderWidth :: struct {
	top:    f32,
	left:   f32,
	bottom: f32,
	right:  f32,
}

Text :: struct {
	str:       string,
	font:      ^Font,
	color:     Color,
	font_size: f32,
	shadow:    f32,
	offset:    Vec2,
}

DivFlags :: bit_set[DivFlag]
DivFlag :: enum {
	WidthPx,
	WidthFraction,
	HeightPx,
	HeightFraction,
	AxisX, // as opposed to AxisY
	MainAlignCenter,
	MainAlignEnd,
	MainAlignSpaceBetween,
	MainAlignSpaceAround,
	CrossAlignCenter,
	CrossAlignEnd,
	Absolute,
	LayoutAsText,
	Animate,
	ClipChildren,
}

ui_start_frame :: proc(cache: ^UiCache) {
	UI_MEMORY.cache = cache
	rand.reset(42)
	// clear the ui buffer:
	clear_UI_MEMORY()
}
clear_UI_MEMORY :: proc() {
	UI_MEMORY.elements_len = 0
	UI_MEMORY.glyphs_len = 0
	UI_MEMORY.parent_stack_len = 0
}

ui_end_frame :: proc(batches: ^UiBatches, max_size: Vec2, delta_secs: f32) {
	if UI_MEMORY.cache == nil {
		print("Cannot end frame when cache == nil")
		os.exit(1)
	}

	layout(max_size)
	update_ui_cache(UI_MEMORY.cache, delta_secs)
	build_ui_batches(batches)
	clear_UI_MEMORY()
	UI_MEMORY.cache = nil
	// if true {os.write_entire_file("hello.txt", transmute([]u8)fmt.aprint(batches));os.exit(1)}
	return
}

DIV_DEFAULT_LERP_SPEED :: 5.0

update_ui_cache :: proc(cache: ^UiCache, delta_secs: f32) {
	@(thread_local)
	generation: int
	@(thread_local)
	remove_queue: [dynamic]UI_ID

	clear(&remove_queue)
	generation += 1


	for i in 0 ..< UI_MEMORY.elements_len {
		#partial switch &div in &UI_MEMORY.elements[i] {
		case DivWithComputed:
			if div.id != 0 {
				cached_div, ok := &cache.cached[div.id]
				if ok {
					cached_div.generation = generation
					if DivFlag.Animate in div.flags {
						lerp_speed := div.animation_speed
						if lerp_speed == 0 {
							lerp_speed = DIV_DEFAULT_LERP_SPEED
						}
						s := lerp_speed * delta_secs
						cached_div.color = lerp(cached_div.color, div.color, s)
						div.color = cached_div.color
						cached_div.pos = lerp(cached_div.pos, div.pos, s)
						div.pos = cached_div.pos
						cached_div.size = lerp(cached_div.size, div.size, s)
						div.size = cached_div.size
					} else {
						cached_div.color = div.color
						cached_div.pos = div.pos
						cached_div.size = div.size
					}
				} else {
					cache.cached[div.id] = CachedDiv {
						pos        = div.pos,
						size       = div.size,
						color      = div.color,
						generation = generation,
					}

				}
			}
		}
	}

	for k, &v in cache.cached {
		if v.generation != generation {
			append(&remove_queue, k)
		}
	}

	for k in remove_queue {
		delete_key(&cache.cached, k)
	}
}


start_children :: proc() {
	div_idx := UI_MEMORY.elements_len - 1
	text, is_text := &UI_MEMORY.elements[div_idx].(TextWithComputed)
	if is_text {
		fmt.printfln("Cannot start children if the parent would be a text section: '%s'", text.str)
		os.exit(1)
	}
	UI_MEMORY.parent_stack[UI_MEMORY.parent_stack_len] = div_idx
	UI_MEMORY.parent_stack_len += 1
}

end_children :: proc() {
	UI_MEMORY.parent_stack_len -= 1
	if UI_MEMORY.parent_stack_len < 0 {
		UI_MEMORY.parent_stack_len = 0
	}
}

_pre_add_div_or_text :: #force_inline proc() {
	if UI_MEMORY.elements_len == MAX_UI_ELEMENTS {
		fmt.printfln("Too many Ui Elements (MAX_UI_ELEMENTS = %d)!", MAX_UI_ELEMENTS)
		os.exit(1)
	}
	if UI_MEMORY.parent_stack_len != 0 {
		parent_idx := UI_MEMORY.parent_stack[UI_MEMORY.parent_stack_len - 1]
		parent_div: ^DivWithComputed
		is_div: bool
		parent_div, is_div = &UI_MEMORY.elements[parent_idx].(DivWithComputed)
		assert(is_div)
		parent_div.child_count += 1
	}

}

div :: proc(div: Div) {
	_pre_add_div_or_text()
	UI_MEMORY.elements[UI_MEMORY.elements_len] = DivWithComputed {
		div          = div,
		pos          = {0, 0},
		size         = {0, 0},
		content_size = {0, 0},
		child_count  = 0,
	}
	UI_MEMORY.elements_len += 1
}

text_from_struct :: proc(text: Text) {
	_pre_add_div_or_text()
	UI_MEMORY.elements[UI_MEMORY.elements_len] = TextWithComputed {
		text             = text,
		pos              = {0, 0},
		size             = {0, 0},
		glyphs_start_idx = UI_MEMORY.glyphs_len,
		glyphs_end_idx   = 0,
	}
	if text.font == nil {
		if default_font_is_not_set() {
			fmt.println(
				"No default font set! Use set_default_font or profive a font in the Text struct.",
			)
			os.exit(1)
		}
		text := &UI_MEMORY.elements[UI_MEMORY.elements_len].(TextWithComputed)
		text.font = &UI_MEMORY.default_font
	}
	UI_MEMORY.elements_len += 1
}

text :: proc {
	text_from_string,
	text_from_struct,
}

text_from_string :: proc(text: string) {

	if default_font_is_not_set() {
		fmt.println(
			"No default font set! Use set_default_font. Cannot create text element from string alone.",
		)
		os.exit(1)
	}

	text_from_struct(
		Text {
			str = text,
			font = &UI_MEMORY.default_font,
			color = UI_MEMORY.default_font_color,
			font_size = UI_MEMORY.default_font_size,
			shadow = 0.0,
		},
	)

}


default_font_is_not_set :: #force_inline proc() -> bool {
	return &UI_MEMORY.default_font.texture == nil
}

// layout pass over the UI_MEMORY, after this, for each element, 
// the elements_computed buffer should contain the correct values
@(private)
layout :: proc(max_size: Vec2) {
	initial_pos := Vec2{0, 0}
	i: int = 0
	for i < UI_MEMORY.elements_len {
		element := &UI_MEMORY.elements[i]
		_size, skipped := set_size(i, element, max_size)
		set_position(i, element, initial_pos)
		i += skipped
	}
}

set_size :: proc(i: int, element: ^UiElement, max_size: Vec2) -> (size: Vec2, skipped: int) {
	switch &element in element {
	case DivWithComputed:
		skipped = set_size_for_div(i, &element, max_size)
		size = element.size
	case TextWithComputed:
		set_size_for_text(&element, max_size)
		skipped = 1
		size = element.size
	}
	return
}

set_position :: proc(i: int, element: ^UiElement, pos: Vec2) -> (skipped: int) {
	switch &element in element {
	case DivWithComputed:
		skipped = set_position_for_div(i, &element, pos)
	case TextWithComputed:
		set_position_for_text(&element, pos)
		skipped = 1
	}
	return
}

set_size_for_text :: proc(text: ^TextWithComputed, max_size: Vec2) {
	ctx := tmp_text_layout_ctx(max_size, 0.0)
	layout_text_in_text_ctx(&ctx, text)
	text.size = finalize_text_layout_ctx_and_return_size(&ctx)
}

set_size_for_div :: proc(i: int, div: ^DivWithComputed, max_size: Vec2) -> (skipped: int) {
	width_fixed := false
	if DivFlag.WidthPx in div.flags {
		width_fixed = true
		div.size.x = div.width
	} else if DivFlag.WidthFraction in div.flags {
		width_fixed = true
		div.size.x = div.width * max_size.x
	}
	height_fixed := false
	if DivFlag.HeightPx in div.flags {
		height_fixed = true
		div.size.y = div.height
	} else if DivFlag.HeightFraction in div.flags {
		height_fixed = true
		div.size.y = div.height * max_size.y
	}
	pad_x := div.padding.left + div.padding.right
	pad_y := div.padding.top + div.padding.bottom

	if div.child_count > 1 && div.gap != 0 {
		if DivFlag.LayoutAsText in div.flags {
			// if there is min 1 text child, then text layout mode is used.
			// there we add the div.gap onto each line instead.
		} else {
			additional_gap_space := div.gap * f32(div.child_count - 1)
			if DivFlag.AxisX in div.flags {
				pad_x += additional_gap_space
			} else {
				pad_y += additional_gap_space
			}
		}
	}

	if width_fixed {
		if height_fixed {
			max_size := div.size - Vec2{pad_x, pad_y}
			skipped = set_child_sizes_for_div(i, div, max_size)
		} else {
			max_size := Vec2{div.size.x - pad_x, max_size.y}
			skipped = set_child_sizes_for_div(i, div, max_size)
			div.size.y = div.content_size.y + pad_y
		}
	} else {
		if height_fixed {
			max_size := Vec2{max_size.x, div.size.y - pad_y}
			skipped = set_child_sizes_for_div(i, div, max_size)
			div.size.x = div.content_size.x + pad_x
		} else {
			skipped = set_child_sizes_for_div(i, div, max_size)
			div.size = Vec2{div.content_size.x + pad_x, div.content_size.y + pad_y}
		}
	}
	return
}

absolute_positioning :: proc(element: ^UiElement) -> bool {
	#partial switch &element in element {
	case DivWithComputed:
		if DivFlag.Absolute in element.flags {
			return true
		}
	}
	return false
}

set_child_sizes_for_div :: proc(i: int, div: ^DivWithComputed, max_size: Vec2) -> (skipped: int) {
	skipped = 1
	axis_is_x := DivFlag.AxisX in div.flags

	if DivFlag.LayoutAsText in div.flags {
		// perform a text layout with all children:
		ctx := tmp_text_layout_ctx(max_size, f32(div.gap))
		for _ in 0 ..< div.child_count {
			c_idx := i + skipped
			element := &UI_MEMORY.elements[c_idx]
			ch_skip := layout_element_in_text_ctx(&ctx, c_idx, element)
			skipped += ch_skip
		}
		div.content_size = finalize_text_layout_ctx_and_return_size(&ctx)
	} else {
		// perform normal layout:
		div.content_size = Vec2{0, 0}
		for _ in 0 ..< div.child_count {
			c_idx := i + skipped
			ch := &UI_MEMORY.elements[c_idx]
			ch_size, ch_skip := set_size(c_idx, ch, max_size)
			skipped += ch_skip
			if !absolute_positioning(ch) {
				if axis_is_x {
					div.content_size.x += ch_size.x
					div.content_size.y = max(div.content_size.y, ch_size.y)
				} else {
					div.content_size.x = max(div.content_size.x, ch_size.x)
					div.content_size.y += ch_size.y
				}
			}
		}
	}


	return
}

break_line :: proc(ctx: ^TextLayoutCtx) {
	ctx.current_line.glyphs_end_idx = UI_MEMORY.glyphs_len
	append(&ctx.lines, ctx.current_line)
	// note: we keep the metrics of the line before
	ctx.current_line.advance = 0
	ctx.current_line.glyphs_start_idx = UI_MEMORY.glyphs_len
}

layout_element_in_text_ctx :: proc(
	ctx: ^TextLayoutCtx,
	i: int,
	element: ^UiElement,
) -> (
	skipped: int,
) {
	switch &element in element {
	case DivWithComputed:
		skipped = layout_div_in_text_ctx(ctx, i, &element)
	case TextWithComputed:
		layout_text_in_text_ctx(ctx, &element)
		skipped = 1
	}
	return
}

layout_text_in_text_ctx :: proc(ctx: ^TextLayoutCtx, text: ^TextWithComputed) {
	font := text.font
	font_size := text.font_size
	scale := font_size / f32(font.rasterization_size)
	ctx.current_line.metrics = merge_line_metrics_to_max(
		ctx.current_line.metrics,
		scale_line_metrics(font.line_metrics, scale),
	)
	ctx.current_font = text.font
	text.glyphs_start_idx = UI_MEMORY.glyphs_len
	for ch in text.str {
		g, ok := ctx.current_font.glyphs[ch]
		if !ok {
			print("Character", ch, "not rastierized yet!")
			os.exit(1)
		}
		g.advance *= scale
		g.xmin *= scale
		g.ymin *= scale
		g.width *= scale
		g.height *= scale
		if ch == '\n' {
			break_line(ctx)
			continue
		}
		needs_line_break := ctx.current_line.advance + g.advance > ctx.max_width
		if needs_line_break {
			break_line(ctx)
			if g.is_white_space {
				// just break, note: the whitespace here is omitted and does not add extra space.
				// (we do not want to have extra white space at the end of a line or at the start of a line unintentionally.)
				clear(&ctx.last_non_whitespace_advances)
				continue
			} else {
				// now move all letters that have been part of this word before onto the next line:
				move_n_to_next_line := len(ctx.last_non_whitespace_advances)
				last_line: ^LineRun = &ctx.lines[len(ctx.lines) - 1]
				last_line.glyphs_end_idx -= move_n_to_next_line
				ctx.current_line.glyphs_start_idx -= move_n_to_next_line
				for j in 0 ..< move_n_to_next_line {
					oa := ctx.last_non_whitespace_advances[j]
					glyph_idx := ctx.current_line.glyphs_start_idx + j
					UI_MEMORY.glyphs[glyph_idx].pos.x = ctx.current_line.advance + oa.offset
					ctx.current_line.advance += oa.advance
					last_line.advance -= oa.advance
				}
			}
		}
		// now add the glyph to the current line:
		if g.is_white_space {
			clear(&ctx.last_non_whitespace_advances)
		} else {
			x_offset := g.xmin
			y_offset := -g.ymin
			height := g.height

			UI_MEMORY.glyphs[UI_MEMORY.glyphs_len] = ComputedGlyph {
				pos  = Vec2{ctx.current_line.advance + x_offset, -height + y_offset},
				size = Vec2{g.width, g.height},
				uv   = Aabb{g.uv_min, g.uv_max},
			}
			UI_MEMORY.glyphs_len += 1
			ctx.current_line.glyphs_end_idx = UI_MEMORY.glyphs_len
			append(
				&ctx.last_non_whitespace_advances,
				XOffsetAndAdvance{offset = x_offset, advance = g.advance},
			)
		}
		ctx.current_line.advance += g.advance
	}
	text.glyphs_end_idx = UI_MEMORY.glyphs_len
}


layout_div_in_text_ctx :: proc(
	ctx: ^TextLayoutCtx,
	i: int,
	div: ^DivWithComputed,
) -> (
	skipped: int,
) {
	skipped = set_size_for_div(i, div, ctx.max_size)
	line_break_needed := ctx.current_line.advance + div.size.x > ctx.max_width
	if line_break_needed {
		break_line(ctx)
	}
	// assign the x part of the element relative position already, the relative y is assined later, when we know the fine heights of each line.
	div.pos.x = ctx.current_line.advance
	ctx.current_line.advance += div.size.x
	line_idx := len(ctx.lines)
	append(&ctx.divs_and_their_line_idxs, DivAndLineIdx{div_element_idx = i, line_idx = line_idx})
	// todo! maybe adjust the line height for the line this div is in 
	// ctx.current_line.metrics.ascent = max(ctx.current_line.metrics.ascent, f32(element_size.y))
	return
}

scale_line_metrics :: proc(line_metrics: LineMetrics, scale: f32) -> LineMetrics {

	return LineMetrics {
		ascent = line_metrics.ascent * scale,
		descent = line_metrics.descent * scale,
		line_gap = line_metrics.line_gap * scale,
		new_line_size = line_metrics.new_line_size * scale,
	}
}

merge_line_metrics_to_max :: proc(a: LineMetrics, b: LineMetrics) -> (res: LineMetrics) {
	res.ascent = max(a.ascent, b.ascent)
	res.descent = min(a.descent, b.descent)
	res.line_gap = max(a.line_gap, b.line_gap)
	res.new_line_size = res.ascent - res.descent + res.line_gap
	return
}

finalize_text_layout_ctx_and_return_size :: proc(ctx: ^TextLayoutCtx) -> (bounding_size: Vec2) {

	append(&ctx.lines, ctx.current_line)
	// calculate the y of the character baseline for each line and add it to the y position of each glyphs coordinates
	base_y: f32 = 0
	max_line_width: f32 = 0
	n_lines := len(ctx.lines)
	for i in 0 ..< n_lines {
		line := &ctx.lines[i]
		base_y += line.metrics.ascent
		line.baseline_y = base_y
		max_line_width = max(max_line_width, line.advance)
		for &g in UI_MEMORY.glyphs[line.glyphs_start_idx:line.glyphs_end_idx] {
			g.pos.y += base_y
		}
		base_y += -line.metrics.descent + line.metrics.line_gap
		if i < n_lines - 1 {
			base_y += ctx.additional_line_gap // can be configured by setting div.gap property.
		}
	}
	// if true {os.exit(1)}

	// go over all non-text child elements and set their position to the baseline - descent (so the total bottom of a line).
	for e in ctx.divs_and_their_line_idxs {
		line := &ctx.lines[e.line_idx]
		bottom_y := line.baseline_y - line.metrics.descent
		div := UI_MEMORY.elements[e.div_element_idx].(DivWithComputed)
		div.pos.y = bottom_y - div.size.y
	}
	// todo: add a mode for centered / end aligned text layout:
	//    How? Iterate over lines a second time, shift all glyphs and all elements of that line by some amount to the right, depending on the max_width of all lines.
	bounding_size = Vec2{max_line_width, base_y}
	return
}

XOffsetAndAdvance :: struct {
	offset:  f32,
	advance: f32,
}

LineRun :: struct {
	baseline_y:       f32,
	// current advance where to place the next glyph if still space
	advance:          f32,
	glyphs_start_idx: int,
	glyphs_end_idx:   int,
	metrics:          LineMetrics,
}


DivAndLineIdx :: struct {
	div_element_idx: int,
	line_idx:        int,
}

TextLayoutCtx :: struct {
	max_size:                     Vec2,
	max_width:                    f32,
	glyphs_start_idx:             int,
	glyphs_end_idx:               int,
	lines:                        [dynamic]LineRun,
	current_line:                 LineRun,
	current_font:                 ^Font,
	additional_line_gap:          f32,
	// save for the last few glyphs that are connected without whitespace in-between their adavances in x direction.
	last_non_whitespace_advances: [dynamic]XOffsetAndAdvance,
	divs_and_their_line_idxs:     [dynamic]DivAndLineIdx,
}


tmp_text_layout_ctx :: proc(max_size: Vec2, additional_line_gap: f32) -> TextLayoutCtx {
	return TextLayoutCtx {
		max_size = max_size,
		max_width = f32(max_size.x),
		additional_line_gap = additional_line_gap,
		glyphs_start_idx = UI_MEMORY.glyphs_len,
		glyphs_end_idx = UI_MEMORY.glyphs_len,
		lines = make([dynamic]LineRun, allocator = context.temp_allocator),
		current_line = {glyphs_start_idx = UI_MEMORY.glyphs_len},
		last_non_whitespace_advances = make(
			[dynamic]XOffsetAndAdvance,
			4,
			allocator = context.temp_allocator,
		),
		divs_and_their_line_idxs = make(
			[dynamic]DivAndLineIdx,
			allocator = context.temp_allocator,
		),
	}
}


set_position_for_div :: proc(i: int, div: ^DivWithComputed, pos: Vec2) -> (skipped: int) {
	skipped = 1
	div.pos = pos + div.offset

	if div.child_count == 0 {
		return
	}

	if DivFlag.LayoutAsText in div.flags {
		skipped = set_child_positions_for_div_with_text_layout(i, div)
	} else {
		skipped = set_child_positions_for_div(i, div)
	}

	return
}

set_child_positions_for_div_with_text_layout :: proc(
	i: int,
	div: ^DivWithComputed,
) -> (
	skipped: int,
) {
	print("divs with .LayoutAsText are not supported yet...")
	os.exit(1)
}

set_child_positions_for_div :: proc(i: int, div: ^DivWithComputed) -> (skipped: int) {
	skipped = 1
	pos := div.pos
	pad_x := div.padding.left + div.padding.right
	pad_y := div.padding.top + div.padding.bottom

	inner_size := Vec2{div.size.x - pad_x, div.size.y - pad_y}
	inner_pos := div.pos + Vec2{div.padding.left, div.padding.top}

	main_size: f32 = ---
	cross_size: f32 = ---
	main_content_size: f32 = ---
	axis_is_x := DivFlag.AxisX in div.flags
	if axis_is_x {
		main_size = inner_size.x
		cross_size = inner_size.y
		main_content_size = div.content_size.x
	} else {
		main_size = inner_size.y
		cross_size = inner_size.x
		main_content_size = div.content_size.y
	}

	main_offset: f32 = 0.0
	main_step: f32 = div.gap
	{
		m_content_size := main_content_size
		if div.child_count > 1 {
			m_content_size = main_content_size + f32(div.child_count - 1) * div.gap
		}
		if DivFlag.MainAlignCenter in div.flags {
			main_offset = (main_size - m_content_size) * 0.5
		} else if DivFlag.MainAlignEnd in div.flags {
			main_offset = main_size - m_content_size
		} else if DivFlag.MainAlignSpaceBetween in div.flags {
			if div.child_count == 1 {
				main_step = 0.0
			} else {
				main_step = (main_size - main_content_size) / f32(div.child_count - 1)
			}
		} else if DivFlag.MainAlignSpaceAround in div.flags {
			main_step = (main_size - main_content_size) / f32(div.child_count)
			main_offset = main_step / 2.0
		}
	}

	for _ in 0 ..< div.child_count {
		c_idx := i + skipped
		element := &UI_MEMORY.elements[c_idx]
		ch_size: Vec2 = ---
		switch &element in element {
		case DivWithComputed:
			ch_size = element.size
		case TextWithComputed:
			ch_size = element.size
		}

		ch_main_size: f32 = ---
		ch_cross_size: f32 = ---
		if axis_is_x {
			ch_main_size = ch_size.x
			ch_cross_size = ch_size.y
		} else {
			ch_main_size = ch_size.y
			ch_cross_size = ch_size.x
		}
		ch_cross_offset: f32 = 0.0
		if DivFlag.CrossAlignCenter in div.flags {
			ch_cross_offset = (cross_size - ch_cross_size) / 2.0
		} else if DivFlag.CrossAlignEnd in div.flags {
			ch_cross_offset = cross_size - ch_cross_size
		}

		ch_rel_pos: Vec2 = ---
		ch_element := &UI_MEMORY.elements[c_idx]
		if absolute_positioning(ch_element) {
			ch_rel_pos = (inner_size - ch_size) * ch_element.(DivWithComputed).absolute_unit_pos
		} else {
			if axis_is_x {
				ch_rel_pos = Vec2{main_offset, ch_cross_offset}
			} else {
				ch_rel_pos = Vec2{ch_cross_offset, main_offset}
			}
			main_offset += ch_main_size + main_step
		}
		ch_pos := ch_rel_pos + inner_pos
		ch_skip := set_position(c_idx, element, ch_pos)
		skipped += ch_skip
	}
	return
}

set_position_for_text :: proc(text: ^TextWithComputed, pos: Vec2) {
	pos := pos + text.offset
	text.pos = pos

	for &g in UI_MEMORY.glyphs[text.glyphs_start_idx:text.glyphs_end_idx] {
		g.pos.x += f32(pos.x)
		g.pos.y += f32(pos.y)
	}

	return
}


build_ui_batches :: proc(batches: ^UiBatches) {
	/////////////////////////////////
	// define helper functions:
	/////////////////////////////////

	element_batch_requirements :: #force_inline proc(
		element: ^UiElement,
	) -> (
		kind: UiBatchKind,
		texture: ^Texture,
	) {
		switch element in element {
		case DivWithComputed:
			kind = .Rect
			texture = element.texture.texture // can be nil for untextured ones...
		case TextWithComputed:
			kind = .Glyph
			texture = element.font.texture
		}
		return
	}

	new_batch :: #force_inline proc(
		kind: UiBatchKind,
		texture: ^Texture,
		batches: ^UiBatches,
	) -> (
		batch: UiBatch,
	) {
		switch kind {
		case .Rect:
			batch = UiBatch {
				start_idx  = len(batches.indices),
				end_idx    = -1,
				kind       = kind,
				texture    = texture,
				clipped_to = Aabb{},
			}
		case .Glyph:
			batch = UiBatch {
				start_idx  = len(batches.glyphs_instances),
				end_idx    = -1,
				kind       = .Glyph,
				texture    = texture,
				clipped_to = {},
			}
		}
		return
	}

	end_batch :: #force_inline proc(batch: ^UiBatch, batches: ^UiBatches) {
		switch batch.kind {
		case .Rect:
			batch.end_idx = len(batches.indices)
		case .Glyph:
			batch.end_idx = len(batches.glyphs_instances)
		}
		return
	}

	add_primitives :: #force_inline proc(element: ^UiElement, batches: ^UiBatches) {
		switch &e in element {
		case DivWithComputed:
			if e.color == {0, 0, 0, 0} || e.size.x == 0 || e.size.y == 0 {
				return
			}

			vertices := &batches.vertices
			indices := &batches.indices
			start_v := u32(len(vertices))

			flags_all: u32 = 0
			if e.texture.texture != nil {
				flags_all |= UI_VERTEX_FLAG_TEXTURED
			}

			min_border_radius := min(e.size.x, e.size.y) / 2.0
			if e.border_radius.top_left > min_border_radius {
				e.border_radius.top_left = min_border_radius
			}
			if e.border_radius.top_right > min_border_radius {
				e.border_radius.top_right = min_border_radius
			}
			if e.border_radius.bottom_right > min_border_radius {
				e.border_radius.bottom_right = min_border_radius
			}
			if e.border_radius.bottom_left > min_border_radius {
				e.border_radius.bottom_left = min_border_radius
			}

			vertex := UiVertex {
				pos           = e.pos,
				size          = e.size,
				uv            = e.texture.uv.min,
				color         = e.color,
				border_color  = e.border_color,
				border_radius = e.border_radius,
				border_width  = e.border_width,
				flags         = flags_all,
			}
			append(vertices, vertex)
			vertex.pos = {e.pos.x, e.pos.y + e.size.y}
			vertex.flags = flags_all | UI_VERTEX_FLAG_RIGHT_VERTEX
			append(vertices, vertex)
			vertex.pos = e.pos + e.size
			vertex.flags = flags_all | UI_VERTEX_FLAG_BOTTOM_VERTEX | UI_VERTEX_FLAG_RIGHT_VERTEX
			append(vertices, vertex)
			vertex.pos = {e.pos.x + e.size.x, e.pos.y}
			vertex.flags = flags_all | UI_VERTEX_FLAG_BOTTOM_VERTEX
			append(vertices, vertex)

			append(indices, start_v)
			append(indices, start_v + 1)
			append(indices, start_v + 2)
			append(indices, start_v)
			append(indices, start_v + 2)
			append(indices, start_v + 3)

		case TextWithComputed:
			for g in UI_MEMORY.glyphs[e.glyphs_start_idx:e.glyphs_end_idx] {
				append(
					&batches.glyphs_instances,
					UiGlyphInstance {
						pos = g.pos,
						size = g.size,
						uv = g.uv,
						color = e.color,
						shadow = e.shadow,
					},
				)
			}
		}
	}

	/////////////////////////////////
	// start actual execution:
	/////////////////////////////////
	clear_batches(batches)
	if UI_MEMORY.elements_len == 0 {
		return
	}
	first_kind, first_texture := element_batch_requirements(&UI_MEMORY.elements[0])
	current_batch := UiBatch {
		start_idx  = 0,
		end_idx    = -1,
		kind       = first_kind,
		texture    = first_texture,
		clipped_to = Aabb{},
	}
	for i in 0 ..< UI_MEMORY.elements_len {
		element := &UI_MEMORY.elements[i]

		kind, texture := element_batch_requirements(element)


		// in case where we are in a rect batch where the current elements all have nil texture, but this one has a texture,
		// we can still keep them in one batch, but update the batches texture pointer.
		// the information which rect should sample the texture and which should not is available per vertex via flag TEXTURED.
		switch &e in element {
		case DivWithComputed:
			if e.texture.texture != nil &&
			   current_batch.kind == .Rect &&
			   current_batch.texture == nil {
				current_batch.texture = e.texture.texture
			}
		case TextWithComputed:
		}

		// allow rects with nil texture and some texture in the same batch, specify if rect is textureless on a per-vertex basis.
		incompatible :=
			kind != current_batch.kind || (texture != nil && texture != current_batch.texture)

		if incompatible {
			end_batch(&current_batch, batches)
			// handle empty batches differently: 
			// if last batch before empty batch actually fits again, pop it and put it as current batch again
			// (the empty batch would otherwise create a hole between two matching batches)
			if current_batch.start_idx != current_batch.end_idx {
				// 99% normal case:
				append(&batches.batches, current_batch)
				current_batch = new_batch(kind, texture, batches)
			} else {
				// current batch is empty: 
				batches_len := len(batches.batches)
				if batches_len != 0 && batches.batches[batches_len - 1].kind == kind {
					current_batch = pop(&batches.batches)
				} else {
					current_batch = new_batch(kind, texture, batches)
				}
			}
		}
		add_primitives(element, batches)
	}
	end_batch(&current_batch, batches)
	if current_batch.start_idx != current_batch.end_idx {
		append(&batches.batches, current_batch)
	}
}

clear_batches :: proc(batches: ^UiBatches) {
	clear(&batches.vertices)
	clear(&batches.indices)
	clear(&batches.glyphs_instances)
	clear(&batches.batches)
}

UiRenderer :: struct {
	device:                wgpu.Device,
	queue:                 wgpu.Queue,
	rect_pipeline:         RenderPipeline,
	glyph_pipeline:        RenderPipeline,
	batches:               UiBatches,
	vertex_buffer:         DynamicBuffer(UiVertex),
	index_buffer:          DynamicBuffer(u32),
	glyph_instance_buffer: DynamicBuffer(UiGlyphInstance),
	cache:                 UiCache,
	white_px_texture:      Texture,
}

ui_renderer_render :: proc(
	rend: ^UiRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_bind_group: wgpu.BindGroup,
) {
	if len(rend.batches.batches) == 0 {
		return
	}
	last_kind := rend.batches.batches[0].kind
	pipeline: ^RenderPipeline = nil
	for &batch in rend.batches.batches {
		// print("     render batch: ", batch.kind)
		if batch.kind != last_kind || pipeline == nil {
			last_kind = batch.kind
			switch batch.kind {
			case .Rect:
				pipeline = &rend.rect_pipeline
			case .Glyph:
				pipeline = &rend.glyph_pipeline
			}
			// wgpu.RenderPassEncoderSetScissorRect()
			wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline.pipeline)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_bind_group)
			switch batch.kind {
			case .Rect:
				wgpu.RenderPassEncoderSetVertexBuffer(
					render_pass,
					0,
					rend.vertex_buffer.buffer,
					0,
					u64(rend.vertex_buffer.size),
				)

				wgpu.RenderPassEncoderSetIndexBuffer(
					render_pass,
					rend.index_buffer.buffer,
					.Uint32,
					0,
					u64(rend.index_buffer.size),
				)
			case .Glyph:
				wgpu.RenderPassEncoderSetVertexBuffer(
					render_pass,
					0,
					rend.glyph_instance_buffer.buffer,
					0,
					u64(rend.glyph_instance_buffer.size),
				)
			}
		}

		batch_texture := batch.texture
		if batch_texture == nil {
			batch_texture = &rend.white_px_texture
		}
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, batch_texture.bind_group)

		switch batch.kind {
		case .Rect:
			index_count := u32(batch.end_idx - batch.start_idx)
			wgpu.RenderPassEncoderDrawIndexed(
				render_pass,
				index_count,
				1,
				u32(batch.start_idx),
				0,
				0,
			)
		case .Glyph:
			instance_count := u32(batch.end_idx - batch.start_idx)
			wgpu.RenderPassEncoderDraw(render_pass, 4, instance_count, 0, u32(batch.start_idx))
		}
	}
}

ui_renderer_start_frame :: proc(rend: ^UiRenderer, screen_size: Vec2, input: ^Input) {
	cache := &rend.cache
	cache.mouse_buttons = input.mouse_buttons
	scale_factor := f32(SCREEN_REFERENCE_SIZE.y) / screen_size.y
	cache.layout_extent = Vec2 {
		f32(SCREEN_REFERENCE_SIZE.y) * screen_size.x / screen_size.y,
		f32(SCREEN_REFERENCE_SIZE.y),
	}
	cache.cursor_pos = Vec2 {
		f32(input.cursor_pos.x) * scale_factor,
		f32(input.cursor_pos.y) * scale_factor,
	}
	ui_start_frame(cache)
}

ui_renderer_end_frame_and_prepare_buffers :: proc(rend: ^UiRenderer, delta_secs: f32) {
	ui_end_frame(&rend.batches, rend.cache.layout_extent, delta_secs)
	dynamic_buffer_write(&rend.vertex_buffer, rend.batches.vertices[:], rend.device, rend.queue)
	dynamic_buffer_write(&rend.index_buffer, rend.batches.indices[:], rend.device, rend.queue)
	dynamic_buffer_write(
		&rend.glyph_instance_buffer,
		rend.batches.glyphs_instances[:],
		rend.device,
		rend.queue,
	)
}

ui_renderer_create :: proc(
	rend: ^UiRenderer,
	device: wgpu.Device,
	queue: wgpu.Queue,
	reg: ^ShaderRegistry,
	globals_layout: wgpu.BindGroupLayout,
	default_font_path: string,
	default_font_color: Color,
	default_font_size: f32,
) {
	if default_font_path == "" {
		panic("No default font specified in engine settings!")
	}
	rend.device = device
	rend.queue = queue
	rend.rect_pipeline.config = ui_rect_pipeline_config(device, globals_layout)
	render_pipeline_create_panic(&rend.rect_pipeline, device, reg)

	rend.glyph_pipeline.config = ui_glyph_pipeline_config(device, globals_layout)
	render_pipeline_create_panic(&rend.glyph_pipeline, device, reg)

	print(default_font_path)
	font, err := font_create(default_font_path, device, queue)
	if err != nil {
		fmt.panicf("Could not load font from: %s", default_font_path)
	}
	UI_MEMORY.default_font = font
	UI_MEMORY.default_font_color = default_font_color
	UI_MEMORY.default_font_size = default_font_size

	rend.vertex_buffer.usage = {.Vertex}
	rend.index_buffer.usage = {.Index}
	rend.glyph_instance_buffer.usage = {.Vertex}

	rend.white_px_texture = texture_create_1px_white(device, queue)

	return
}

ui_rect_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "ui_rect",
		vs_shader = "ui",
		vs_entry_point = "vs_rect",
		fs_shader = "ui",
		fs_entry_point = "fs_rect",
		topology = .TriangleList,
		vertex = {
			ty_id = UiVertex,
			attributes = {
				{format = .Float32x2, offset = offset_of(UiVertex, pos)},
				{format = .Float32x2, offset = offset_of(UiVertex, size)},
				{format = .Float32x2, offset = offset_of(UiVertex, uv)},
				{format = .Float32x4, offset = offset_of(UiVertex, color)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_color)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_radius)},
				{format = .Float32x4, offset = offset_of(UiVertex, border_width)},
				{format = .Uint32, offset = offset_of(UiVertex, flags)},
			},
		},
		instance = {},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
	}
}

ui_glyph_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "ui_glyph",
		vs_shader = "ui",
		vs_entry_point = "vs_glyph",
		fs_shader = "ui",
		fs_entry_point = "fs_glyph",
		topology = .TriangleStrip,
		vertex = {},
		instance = {
			ty_id = UiGlyphInstance,
			attributes = {
				{format = .Float32x2, offset = offset_of(UiGlyphInstance, pos)},
				{format = .Float32x2, offset = offset_of(UiGlyphInstance, size)},
				{format = .Float32x4, offset = offset_of(UiGlyphInstance, uv)},
				{format = .Float32x4, offset = offset_of(UiGlyphInstance, color)},
				{format = .Float32, offset = offset_of(UiGlyphInstance, shadow)},
			},
		},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
	}
}

ui_renderer_destroy :: proc(rend: ^UiRenderer) {
	ui_batches_destroy(&rend.batches)
	render_pipeline_destroy(&rend.rect_pipeline)
	render_pipeline_destroy(&rend.glyph_pipeline)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
	dynamic_buffer_destroy(&rend.glyph_instance_buffer)
	font_destroy(&UI_MEMORY.default_font)
}

ui_batches_destroy :: proc(batches: ^UiBatches) {
	delete(batches.vertices)
	delete(batches.indices)
	delete(batches.glyphs_instances)
	delete(batches.batches)
}
