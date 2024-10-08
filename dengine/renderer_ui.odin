package dengine


import "core:fmt"
import "core:hash"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"
import wgpu "vendor:wgpu"

SCREEN_REFERENCE_SIZE :: [2]u32{1920, 1080}

NO_ID: UiId = 0
UiId :: u64

ui_id :: proc(str: string) -> UiId {
	return hash.crc64_xz(transmute([]byte)str)
}

derived_id :: proc(id: UiId) -> UiId {
	bytes := transmute([8]u8)id
	return hash.crc64_xz(bytes[:])
}

combined_id :: proc(a: UiId, b: UiId) -> UiId {
	bytes := transmute([16]u8)[2]UiId{a, b}
	return hash.crc64_xz(bytes[:])
}

InteractionState :: struct($ID: typeid) {
	hovered_id:        ID,
	pressed_id:        ID,
	focused_id:        ID,
	just_pressed_id:   ID,
	just_released_id:  ID,
	just_unfocused_id: ID,
}

update_interaction_state :: proc(
	using state: ^InteractionState($T),
	new_hovered_id: T,
	press: PressFlags,
) {
	// todo! just_hovered, just_unhovered...
	hovered_id = new_hovered_id
	state.just_pressed_id = {}
	state.just_released_id = {}
	state.just_unfocused_id = {}

	if pressed_id != {} && .JustReleased in press {
		if hovered_id == pressed_id {
			focused_id = pressed_id
			just_released_id = pressed_id
		}
		pressed_id = {}
	}

	if focused_id != {} && .JustPressed in press && hovered_id != focused_id {
		just_unfocused_id = focused_id
		focused_id = {}
	}

	if hovered_id != {} && .JustPressed in press {
		just_pressed_id = hovered_id
		pressed_id = hovered_id
	}
}

Interaction :: struct {
	hovered:        bool,
	pressed:        bool,
	focused:        bool,
	just_pressed:   bool,
	just_released:  bool,
	just_unfocused: bool,
}


interaction :: proc(id: $T, state: ^InteractionState(T)) -> Interaction {
	return Interaction {
		hovered = state.hovered_id == id,
		pressed = state.pressed_id == id,
		focused = state.focused_id == id,
		just_pressed = state.just_pressed_id == id,
		just_released = state.just_released_id == id,
		just_unfocused = state.just_unfocused_id == id,
	}
}

ui_interaction :: proc(id: UiId, cache: ^UiCache = UI_MEMORY.cache) -> Interaction {
	return interaction(id, &cache.state)
}

ActiveValue :: struct #raw_union {
	slider_value_start_drag: f32,
	window_pos_start_drag:   Vec2,
}

UiCache :: struct {
	cached:                 map[UiId]CachedElement,
	state:                  InteractionState(UiId),
	cursor_pos_start_press: Vec2,
	active_value:           ActiveValue,
	platform:               ^Platform,
	cursor_pos:             Vec2, // (scaled to reference cursor pos)
	layout_extent:          Vec2,
}

cache_any_pressed_or_focused :: proc(cache: ^UiCache, ids: []UiId) -> bool {
	for id in ids {
		if cache.state.pressed_id == id || cache.state.focused_id == id {
			return true
		}
	}
	return false
}

UiZIndex :: u32
CachedElement :: struct {
	pos:                  Vec2,
	size:                 Vec2,
	z:                    UiZIndex,
	i:                    int,
	generation:           int,
	pointer_pass_through: bool,
	data:                 CachedData,
}

CachedData :: struct #raw_union {
	div:  DivCached,
	ints: [8]int,
}

DivCached :: struct {
	color:        Color,
	border_color: Color,
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
	primitives: Primitives,
	batches:    [dynamic]UiBatch,
}

UiBatch :: struct {
	start_idx:  int,
	end_idx:    int,
	kind:       BatchKind,
	handle:     TextureOrFontHandle,
	clipped_to: Aabb,
}

TextureOrFontHandle :: distinct (u32)

BatchKind :: enum {
	Rect,
	Glyph,
}

PreBatch :: struct {
	end_idx: int,
	kind:    BatchKind,
	handle:  TextureOrFontHandle,
}

Primitives :: struct {
	vertices:         [dynamic]UiVertex,
	indices:          [dynamic]u32,
	glyphs_instances: [dynamic]UiGlyphInstance,
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


@(private)
@(thread_local)
UI_MEMORY: UiMemory
MAX_UI_ELEMENTS :: 10000
MAX_GLYPHS :: 100000
MAX_PARENT_LEVELS :: 124
MAX_Z_REGIONS :: 1000
UiMemory :: struct {
	// todo!: possibly these could be GlyphInstances directly, such that we do not need to copy out of here again when creating the instance for UIBatches. 
	// For that, make this a dynamic array that is swapped to the ui_batches
	glyphs:                  [MAX_GLYPHS]ComputedGlyph,
	glyphs_len:              int,
	elements:                [MAX_UI_ELEMENTS]UiElement,
	elements_len:            int,
	parent_stack:            [MAX_PARENT_LEVELS]Parent, // the last item in this stack is the index of the current parent
	parent_stack_len:        int,
	default_font:            FontHandle,
	default_font_color:      Color,
	default_font_size:       f32,
	cache:                   ^UiCache,
	text_ids_to_tmp_layouts: map[UiId]^TextLayoutCtx, // (a little hacky), save the text layouts during the set_size step here, such that other custom elements can lookup a certain text_id in the set_position step and draw geometry based on the layouted lines.
}

UI_MEMORY_elements :: proc() -> []UiElement {
	return UI_MEMORY.elements[:UI_MEMORY.elements_len]
}

Parent :: struct {
	idx:         int,
	child_count: int, // number of direct children
}

UiElement :: struct {
	pos:     Vec2, // computed
	size:    Vec2, // computed
	z:       UiZIndex, // computed: parent.z + this.z_bias
	id:      UiId,
	variant: UiElementVariant,
}

UiElementVariant :: union {
	DivWithComputed,
	TextWithComputed,
	CustomUiElement,
}

CustomUiElement :: struct {
	set_size:       proc(data: rawptr, max_size: Vec2) -> (used_size: Vec2),
	add_primitives: proc(
		data: rawptr,
		pos: Vec2, // passed here, instead of having another function for set_position
		size: Vec2, // the size that is also returned in set_size().
		primitives: ^Primitives,
		pre_batches: ^[dynamic]PreBatch,
	),
	data:           CustomUiElementStorage,
}
CustomUiElementStorage :: [128]u8

e := fmt.println(size_of(CustomUiElement))

DivWithComputed :: struct {
	using div:    Div,
	content_size: Vec2, // computed
	child_count:  int, // direct children of this Div
	// number of elements in hierarchy below this, incl. self 
	// skipped = (1 + children + children of children + children of children of children + ...)
	// so the idx range  div.idx ..< div.idx+div.skipped is the entire ui subtree that this div is a parent of
	skipped:      int,
}

TextWithComputed :: struct {
	using text:          Text,
	glyphs_start_idx:    int,
	glyphs_end_idx:      int,
	tmp_text_layout_ctx: ^TextLayoutCtx,
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
	z_bias:            UiZIndex,
	texture:           TextureTile,
	border_radius:     BorderRadius,
	border_width:      BorderWidth,
	border_color:      Color,
	lerp_speed:        f32, //   (lerp speed)
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
	str:                  string,
	font:                 FontHandle,
	color:                Color,
	font_size:            f32,
	shadow:               f32,
	offset:               Vec2,
	line_break:           LineBreak,
	align:                TextAlign,
	pointer_pass_through: bool,
}

TextAlign :: enum {
	Left,
	Center,
	Right,
}

LineBreak :: enum {
	OnWord      = 0,
	OnCharacter = 1,
	Never       = 2,
}

DivFlags :: bit_set[DivFlag]
DivFlag :: enum u32 {
	WidthPx,
	WidthFraction,
	HeightPx,
	HeightFraction,
	AxisX, // as opposed to default = AxisY 
	MainAlignCenter,
	MainAlignEnd,
	MainAlignSpaceBetween,
	MainAlignSpaceAround,
	CrossAlignCenter,
	CrossAlignEnd,
	Absolute,
	LayoutAsText,
	LerpStyle,
	LerpTransform,
	ClipContent,
	PointerPassThrough, // divs with this are not considered when determinin which div is hovered. useful for divs that need ids to do animation but are on top of other divs that we want to interact with.
}

ui_start_frame :: proc(cache: ^UiCache) {
	rand.reset(42)
	clear_UI_MEMORY()
	UI_MEMORY.cache = cache
	// figure out if any ui element with an id is hovered. If many, select the one with highest z value
	hovered_id: UiId = 0
	highest_z := min(UiZIndex)
	highest_z_i := min(int)
	for id, cached in cache.cached {
		if cached.pointer_pass_through {
			continue
		}
		if cached.z > highest_z || cached.z == highest_z && cached.i > highest_z_i {
			cursor_in_bounds :=
				cache.cursor_pos.x >= cached.pos.x &&
				cache.cursor_pos.y >= cached.pos.y &&
				cache.cursor_pos.x <= cached.pos.x + cached.size.x &&
				cache.cursor_pos.y <= cached.pos.y + cached.size.y
			if cursor_in_bounds {
				highest_z = cached.z
				highest_z_i = cached.i
				hovered_id = id
			}

		}
	}

	// determine the rest of ids, i.e. 
	update_interaction_state(&cache.state, hovered_id, cache.platform.mouse_buttons[.Left])

	if cache.state.just_pressed_id != 0 {
		// print("just_pressed_id", cache.state.just_pressed_id)
		cache.cursor_pos_start_press = cache.cursor_pos
	}

}

clear_UI_MEMORY :: proc() {
	UI_MEMORY.elements_len = 0
	UI_MEMORY.glyphs_len = 0
	UI_MEMORY.parent_stack_len = 0
}

ui_end_frame :: proc(
	batches: ^UiBatches,
	max_size: Vec2,
	delta_secs: f32,
	asset_manager: AssetManager,
) {
	assert(UI_MEMORY.parent_stack_len == 0, "make sure to call end_div() for every start_div()!")

	if UI_MEMORY.cache == nil {
		panic("Cannot end frame when cache == nil")
	}

	layout(max_size, asset_manager)
	update_ui_cache(UI_MEMORY.cache, delta_secs)
	build_ui_batches(batches)
	return
}

DIV_DEFAULT_LERP_SPEED :: 5.0

/// Note: also modifies the Ui-Elements in the UI_Memory to achieve lerping from the last frame.
update_ui_cache :: proc(cache: ^UiCache, delta_secs: f32) {
	@(thread_local)
	generation: int
	@(thread_local)
	remove_queue: [dynamic]UiId

	clear(&remove_queue)
	generation += 1


	for i in 0 ..< UI_MEMORY.elements_len {
		el := &UI_MEMORY.elements[i]
		if el.id == 0 {
			continue
		}
		old_cached, has_old_cached := cache.cached[el.id]
		new_cached: CachedElement = CachedElement {
			pos        = el.pos,
			size       = el.size,
			z          = el.z,
			i          = i,
			generation = generation,
		}

		switch &var in el.variant {
		case DivWithComputed:
			new_cached.pointer_pass_through = .PointerPassThrough in var.flags
			if has_old_cached {
				lerp_style := .LerpStyle in var.flags
				lerp_transform := .LerpTransform in var.flags

				s: f32 = --- // lerp factor
				if lerp_style || lerp_transform {
					lerp_speed := var.lerp_speed
					if lerp_speed == 0 {
						lerp_speed = DIV_DEFAULT_LERP_SPEED
					}
					s = lerp_speed * delta_secs
				}

				cached_data: DivCached

				if lerp_style {
					new_cached.data.div.color = lerp(old_cached.data.div.color, var.color, s)
					var.color = new_cached.data.div.color

					new_cached.data.div.border_color = lerp(
						old_cached.data.div.border_color,
						var.border_color,
						s,
					)
					var.border_color = new_cached.data.div.border_color
				} else {
					new_cached.data.div = DivCached {
						color        = var.color,
						border_color = var.border_color,
					}
				}
				if lerp_transform {
					new_cached.pos = lerp(old_cached.pos, el.pos, s)
					el.pos = new_cached.pos
					new_cached.size = lerp(old_cached.size, el.size, s)
					el.size = new_cached.size
				}
			}
		case TextWithComputed:
			if var.pointer_pass_through {
				new_cached.pointer_pass_through = true
			}
		// todo! lerping text color!
		case CustomUiElement:
		// no lerping here yet
		}
		cache.cached[el.id] = new_cached
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

@(private)
_pre_add_ui_element :: #force_inline proc() {
	if UI_MEMORY.elements_len == MAX_UI_ELEMENTS {
		fmt.panicf("Too many Ui Elements (MAX_UI_ELEMENTS = %d)!", MAX_UI_ELEMENTS)
	}
	if UI_MEMORY.parent_stack_len != 0 {
		UI_MEMORY.parent_stack[UI_MEMORY.parent_stack_len - 1].child_count += 1
	}
}


custom_ui_element :: proc(
	data: $T,
	set_size: proc(data: ^T, max_size: Vec2) -> (used_size: Vec2),
	add_primitives: proc(
		data: ^T,
		pos: Vec2, // passed here, instead of having another function for set_position
		size: Vec2, // the size that is also returned in set_size().
		primitives: ^Primitives,
		pre_batches: ^[dynamic]PreBatch,
	),
	id: UiId = 0,
) where size_of(T) <= size_of(CustomUiElementStorage) {
	_pre_add_ui_element()
	custom_element := CustomUiElement {
		set_size       = auto_cast set_size,
		add_primitives = auto_cast add_primitives,
		data           = {},
	}
	data_dst: ^T = cast(^T)&custom_element.data
	data_dst^ = data
	UI_MEMORY.elements[UI_MEMORY.elements_len] = UiElement {
		variant = custom_element,
		id      = id,
	}
	UI_MEMORY.elements_len += 1

}

// only used for divs without children, otherwise use `start_div` and `end_div`
div :: proc(div: Div, id: UiId = 0) {
	_pre_add_ui_element()
	UI_MEMORY.elements[UI_MEMORY.elements_len] = UiElement {
		variant = DivWithComputed{div = div},
		id = id,
	}
	UI_MEMORY.elements_len += 1
}

// when called, make sure to call end_div later!
start_div :: proc(div: Div, id: UiId = 0) {
	_pre_add_ui_element()
	idx := UI_MEMORY.elements_len
	UI_MEMORY.elements[idx] = UiElement {
		variant = DivWithComputed{div = div},
		id = id,
	}
	UI_MEMORY.elements_len += 1
	UI_MEMORY.parent_stack[UI_MEMORY.parent_stack_len] = Parent {
		idx         = idx,
		child_count = 0,
	}
	UI_MEMORY.parent_stack_len += 1
}

end_div :: proc() {
	assert(UI_MEMORY.parent_stack_len > 0, "called end_div too often!")
	UI_MEMORY.parent_stack_len -= 1
	parent := UI_MEMORY.parent_stack[UI_MEMORY.parent_stack_len]
	switch &e in UI_MEMORY.elements[parent.idx].variant {
	case DivWithComputed:
		e.child_count = parent.child_count
	case TextWithComputed, CustomUiElement:
		panic(
			"There is an idx pointing to a non-div element in the parent stack. Text elements cannot be parents.",
		)
	}
}

text_from_struct :: proc(text: Text, id: UiId = 0) {
	_pre_add_ui_element()
	UI_MEMORY.elements[UI_MEMORY.elements_len] = UiElement {
		variant = TextWithComputed {
			text = text,
			glyphs_start_idx = UI_MEMORY.glyphs_len,
			glyphs_end_idx = 0,
			tmp_text_layout_ctx = nil,
		},
		id = id,
	}
	UI_MEMORY.elements_len += 1
}

text :: proc {
	text_from_string,
	text_from_struct,
	text_from_any,
}

text_from_string :: proc(text: string, id: UiId = 0) {
	text_from_struct(
		Text {
			str = text,
			font = DEFAULT_FONT,
			color = UI_MEMORY.default_font_color,
			font_size = UI_MEMORY.default_font_size,
			shadow = 0.0,
		},
		id,
	)
}

text_from_any :: proc(text: any, id: UiId = 0) {
	text_from_struct(
		Text {
			str = fmt.aprint(text, allocator = context.temp_allocator),
			font = DEFAULT_FONT,
			color = UI_MEMORY.default_font_color,
			font_size = UI_MEMORY.default_font_size,
			shadow = 0.0,
		},
		id,
	)
}

// layout pass over the UI_MEMORY, after this, for each element, 
// the elements_computed buffer should contain the correct values
@(private)
layout :: proc(max_size: Vec2, assets: AssetManager) {
	initial_pos := Vec2{0, 0}
	i: int = 0
	z: UiZIndex = 0
	for i < UI_MEMORY.elements_len {
		element := &UI_MEMORY.elements[i]
		skipped := set_size(i, element, max_size, z, assets)
		set_position(i, element, initial_pos)
		i += skipped
	}
}

@(private)
set_size :: proc(
	i: int,
	element: ^UiElement,
	max_size: Vec2,
	parent_z: UiZIndex,
	assets: AssetManager,
) -> (
	skipped: int,
) {
	element.z = parent_z
	switch &var in element.variant {
	case DivWithComputed:
		element.z += var.z_bias
		element.size, skipped = set_size_for_div(i, &var, max_size, element.z, assets)
	case TextWithComputed:
		element.size = set_size_for_text(&var, max_size, assets)
		skipped = 1
		if element.id != 0 {
			UI_MEMORY.text_ids_to_tmp_layouts[element.id] = var.tmp_text_layout_ctx
		}
	case CustomUiElement:
		element.size = var.set_size(raw_data(&var.data), max_size)
		skipped = 1
	}
	return
}

@(private)
set_position :: proc(i: int, element: ^UiElement, pos: Vec2) -> (skipped: int) {
	switch &var in element.variant {
	case DivWithComputed:
		element.pos, skipped = set_position_for_div(i, &var, element.size, pos)
	case TextWithComputed:
		element.pos = set_position_for_text(&var, pos)
		skipped = 1
	case CustomUiElement:
		element.pos = pos
		skipped = 1
	}
	return
}

@(private)
set_size_for_text :: proc(
	text: ^TextWithComputed,
	max_size: Vec2,
	assets: AssetManager,
) -> (
	text_size: Vec2,
) {
	// if text.str == "" {return Vec2{}}
	ctx := tmp_text_layout_ctx(max_size, 0.0, text.align)
	layout_text_in_text_ctx(ctx, text, assets)
	text_size = finalize_text_layout_ctx_and_return_size(ctx)
	text.tmp_text_layout_ctx = ctx
	return
}

@(private)
set_size_for_div :: proc(
	i: int,
	div: ^DivWithComputed,
	max_size: Vec2,
	z_of_div: UiZIndex,
	assets: AssetManager,
) -> (
	div_size: Vec2,
	skipped: int,
) {
	width_fixed := false
	if DivFlag.WidthPx in div.flags {
		width_fixed = true
		div_size.x = div.width
	} else if DivFlag.WidthFraction in div.flags {
		width_fixed = true
		div_size.x = div.width * max_size.x
	}
	height_fixed := false
	if DivFlag.HeightPx in div.flags {
		height_fixed = true
		div_size.y = div.height
	} else if DivFlag.HeightFraction in div.flags {
		height_fixed = true
		div_size.y = div.height * max_size.y
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
			max_size := div_size - Vec2{pad_x, pad_y}
			skipped = set_child_sizes_for_div(i, div, max_size, z_of_div, assets)
		} else {
			max_size := Vec2{div_size.x - pad_x, max_size.y}
			skipped = set_child_sizes_for_div(i, div, max_size, z_of_div, assets)
			div_size.y = div.content_size.y + pad_y
		}
	} else {
		if height_fixed {
			max_size := Vec2{max_size.x, div_size.y - pad_y}
			skipped = set_child_sizes_for_div(i, div, max_size, z_of_div, assets)
			div_size.x = div.content_size.x + pad_x
		} else {
			skipped = set_child_sizes_for_div(i, div, max_size, z_of_div, assets)
			div_size = Vec2{div.content_size.x + pad_x, div.content_size.y + pad_y}
		}
	}
	div.skipped = skipped
	return
}

@(private)
absolute_positioning :: proc(element: ^UiElement) -> bool {
	#partial switch &var in element.variant {
	case DivWithComputed:
		if DivFlag.Absolute in var.flags {
			return true
		}
	}
	return false
}

@(private)
set_child_sizes_for_div :: proc(
	i: int,
	div: ^DivWithComputed,
	max_size: Vec2,
	z_of_div: UiZIndex,
	assets: AssetManager,
) -> (
	skipped: int,
) {
	skipped = 1
	axis_is_x := DivFlag.AxisX in div.flags

	if DivFlag.LayoutAsText in div.flags {
		// perform a text layout with all children:
		ctx := tmp_text_layout_ctx(max_size, f32(div.gap), .Left) // todo! .Left not necessarily correct here, maybe use divs CrossAlign converted to text align or something.
		for _ in 0 ..< div.child_count {
			c_idx := i + skipped
			element := &UI_MEMORY.elements[c_idx]
			ch_skip := layout_element_in_text_ctx(ctx, c_idx, element, z_of_div, assets)
			skipped += ch_skip
		}
		div.content_size = finalize_text_layout_ctx_and_return_size(ctx)
	} else {
		// perform normal layout:
		div.content_size = Vec2{0, 0}
		for _ in 0 ..< div.child_count {
			c_idx := i + skipped
			ch := &UI_MEMORY.elements[c_idx]
			ch_skip := set_size(c_idx, ch, max_size, z_of_div, assets)
			skipped += ch_skip
			if !absolute_positioning(ch) {
				if axis_is_x {
					div.content_size.x += ch.size.x
					div.content_size.y = max(div.content_size.y, ch.size.y)
				} else {
					div.content_size.x = max(div.content_size.x, ch.size.x)
					div.content_size.y += ch.size.y
				}
			}
		}
	}


	return
}

break_line :: proc(ctx: ^TextLayoutCtx) {
	ctx.current_line.glyphs_end_idx = UI_MEMORY.glyphs_len
	ctx.current_line.byte_end_idx = ctx.last_byte_idx
	append(&ctx.lines, ctx.current_line)
	// note: we keep the metrics of the line before
	ctx.current_line.advance = 0
	ctx.current_line.glyphs_start_idx = UI_MEMORY.glyphs_len
}

layout_element_in_text_ctx :: proc(
	ctx: ^TextLayoutCtx,
	i: int,
	element: ^UiElement,
	parent_z: UiZIndex,
	assets: AssetManager,
) -> (
	skipped: int,
) {
	element.z = parent_z
	switch &var in element.variant {
	case DivWithComputed:
		element.z += var.z_bias
		element.size, element.pos, skipped = layout_div_in_text_ctx(
			ctx,
			i,
			&var,
			element.z,
			assets,
		)
	case TextWithComputed:
		layout_text_in_text_ctx(ctx, &var, assets)
		skipped = 1
	case CustomUiElement:
		panic("Custom Ui elements in text not allowed yet.")
	}

	return
}

layout_text_in_text_ctx :: proc(
	ctx: ^TextLayoutCtx,
	text: ^TextWithComputed,
	assets: AssetManager,
) {


	font := assets_get_font(assets, text.font)
	font_size := text.font_size
	scale := font_size / f32(font.rasterization_size)
	ctx.current_line.metrics = merge_line_metrics_to_max(
		ctx.current_line.metrics,
		scale_line_metrics(font.line_metrics, scale),
	)
	text.glyphs_start_idx = UI_MEMORY.glyphs_len
	resize(&ctx.byte_advances, len(ctx.byte_advances) + len(text.str))
	for ch, ch_byte_idx in text.str {
		ctx.last_byte_idx = ch_byte_idx
		g, ok := font.glyphs[ch]
		if !ok {
			fmt.panicf("Character %s not rastierized yet!", ch)
		}
		g.advance *= scale
		g.xmin *= scale
		g.ymin *= scale
		g.width *= scale
		g.height *= scale
		if ch == '\n' {
			ctx.byte_advances[ch_byte_idx] = ctx.current_line.advance
			break_line(ctx)
			continue
		}
		needs_line_break :=
			text.line_break != .Never && ctx.current_line.advance + g.advance > ctx.max_width
		if needs_line_break {
			break_line(ctx)
			if g.is_white_space {
				// just break, note: the whitespace here is omitted and does not add extra space.
				// (we do not want to have extra white space at the end of a line or at the start of a line unintentionally.)
				clear(&ctx.last_non_whitespace_advances)
				ctx.last_whitespace_byte_idx = ch_byte_idx
				continue
			}

			if text.line_break == .OnWord {
				// now move all letters that have been part of this word before onto the next line:
				move_n_to_next_line := len(ctx.last_non_whitespace_advances)
				last_line: ^LineRun = &ctx.lines[len(ctx.lines) - 1]
				last_line.glyphs_end_idx -= move_n_to_next_line
				last_line.byte_end_idx = ctx.last_whitespace_byte_idx + 1 // assuming all whitespace is one byte ?
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
		ctx.byte_advances[ch_byte_idx] = ctx.current_line.advance
	}
	text.glyphs_end_idx = UI_MEMORY.glyphs_len
}


layout_div_in_text_ctx :: proc(
	ctx: ^TextLayoutCtx,
	i: int,
	div: ^DivWithComputed,
	z_of_div: UiZIndex,
	assets: AssetManager,
) -> (
	div_size: Vec2,
	div_pos: Vec2,
	skipped: int,
) {
	div_size, skipped = set_size_for_div(i, div, ctx.max_size, z_of_div, assets)
	line_break_needed := ctx.current_line.advance + div_size.x > ctx.max_width
	if line_break_needed {
		break_line(ctx)
	}
	// assign the x part of the element relative position already, the relative y is assined later, when we know the fine heights of each line.
	div_pos.x = ctx.current_line.advance
	ctx.current_line.advance += div_size.x
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

finalize_text_layout_ctx_and_return_size :: proc(ctx: ^TextLayoutCtx) -> (used_size: Vec2) {
	ctx.current_line.byte_end_idx = ctx.last_byte_idx
	ctx.current_line.glyphs_end_idx = UI_MEMORY.glyphs_len
	append(&ctx.lines, ctx.current_line)
	// calculate the y of the character baseline for each line and add it to the y position of each glyphs coordinates
	base_y: f32 = 0
	max_line_width: f32 = 0
	n_lines := len(ctx.lines)
	for &line, i in ctx.lines {
		base_y += line.metrics.ascent
		line.baseline_y = base_y
		max_line_width = max(max_line_width, line.advance) // TODO! technically line.advance is not the correct end of the line, instead the last glyphs width should be the cutoff value. The advance could be wider of less wide than the width.
		// todo! there is a bug here, if the width of the container is too small to hold a single word, the application crashes.
		// todo! crashes when line.glyphs_end_idx is 0 for whatever reason
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
		div := UI_MEMORY.elements[e.div_element_idx]
		div.pos.y = bottom_y - div.size.y
	} // Todo: Test this, I think I just ported this over from Rust but not sure if divs in text layout are supported yet.


	max_size := ctx.max_size
	if ctx.align == .Left {
		used_size = Vec2{min(max_size.x, max_line_width), min(max_size.y, base_y)}
	} else {
		used_size = Vec2{max_size.x, min(max_size.y, base_y)}
		byte_start_idx: int = 0
		for &line in ctx.lines {
			offset: f32 = ---
			line_width := line.advance
			switch ctx.align {
			case .Left:
				unreachable()
			case .Center:
				offset = (max_size.x - line_width) / 2
			case .Right:
				offset = max_size.x - line_width
			}
			if offset == 0 {
				continue
			}
			for &g in UI_MEMORY.glyphs[line.glyphs_start_idx:line.glyphs_end_idx] {
				g.pos.x += offset
			}
			line.advance += offset
			line.x_offset = offset
			byte_start_idx = line.byte_end_idx
		}
	}

	return
}

XOffsetAndAdvance :: struct {
	offset:  f32,
	advance: f32,
}

LineRun :: struct {
	baseline_y:       f32,
	x_offset:         f32, // starting x pos of line (while advance is ending x pos)
	// current advance where to place the next glyph if still space
	advance:          f32,
	// TODO! add width and use instead of advance. width:            f32, // almost the same as advance, but could be slightly different: the last glyph is 
	glyphs_start_idx: int,
	glyphs_end_idx:   int,
	metrics:          LineMetrics,
	byte_end_idx:     int, // inclusive!
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
	additional_line_gap:          f32,
	// save for the last few glyphs that are connected without whitespace in-between their adavances in x direction.
	last_non_whitespace_advances: [dynamic]XOffsetAndAdvance,
	divs_and_their_line_idxs:     [dynamic]DivAndLineIdx,
	align:                        TextAlign,
	byte_advances:                [dynamic]f32,
	last_whitespace_byte_idx:     int,
	last_byte_idx:                int,
}

tmp_text_layout_ctx :: proc(
	max_size: Vec2,
	additional_line_gap: f32,
	align: TextAlign,
) -> ^TextLayoutCtx {
	ctx := new(TextLayoutCtx, allocator = context.temp_allocator)
	ctx^ = TextLayoutCtx {
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
		align = align,
		byte_advances = make([dynamic]f32, allocator = context.temp_allocator),
	}
	return ctx
}


set_position_for_div :: proc(
	i: int,
	div: ^DivWithComputed,
	div_size: Vec2,
	pos: Vec2,
) -> (
	div_pos: Vec2,
	skipped: int,
) {
	skipped = 1
	div_pos = pos + div.offset

	if div.child_count == 0 {
		return
	}

	if DivFlag.LayoutAsText in div.flags {
		skipped = set_child_positions_for_div_with_text_layout(i, div, div_pos)
	} else {
		skipped = set_child_positions_for_div(i, div, div_size, div_pos)
	}

	return
}

set_child_positions_for_div_with_text_layout :: proc(
	i: int,
	div: ^DivWithComputed,
	div_pos: Vec2,
) -> (
	skipped: int,
) {
	/// WARNING: THIS IS STILL EXPERIMENTAL AND SHOULD PROBABLY NOT BE USED!!! MANY CASES NOT HANDLED, LAYOUT ATTRIBUTES ON PARENT DIV IGNORED.
	skipped = 1
	for _ in 0 ..< div.child_count {
		c_idx := i + skipped
		child := &UI_MEMORY.elements[c_idx]
		switch &var in &child.variant {
		case DivWithComputed:
			_, add_skipped := set_position_for_div(c_idx, &var, child.size, child.pos + div_pos)
			skipped += add_skipped
		case TextWithComputed:
			set_position_for_text(&var, child.pos + div_pos)
			skipped += 1
		case CustomUiElement:
			panic("Custom Ui elements in text not supported.")
		}
	}
	return skipped
}

set_child_positions_for_div :: proc(
	i: int,
	div: ^DivWithComputed,
	div_size: Vec2,
	div_pos: Vec2,
) -> (
	skipped: int,
) {
	skipped = 1
	pos := div_pos
	pad_x := div.padding.left + div.padding.right
	pad_y := div.padding.top + div.padding.bottom

	inner_size := Vec2{div_size.x - pad_x, div_size.y - pad_y}
	inner_pos := div_pos + Vec2{div.padding.left, div.padding.top}

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
		ch_size: Vec2 = element.size

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
			ch_rel_pos =
				(inner_size - ch_size) * ch_element.variant.(DivWithComputed).absolute_unit_pos
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

set_position_for_text :: proc(text: ^TextWithComputed, pos: Vec2) -> (text_pos: Vec2) {
	pos := pos + text.offset
	text_pos = pos
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

	is_compatible :: #force_inline proc(
		batch: ^UiBatch,
		pre: ^PreBatch,
		current_clipping_rect: Aabb,
	) -> bool {
		return(
			batch.kind == pre.kind &&
			(batch.handle == 0 || pre.handle == 0 || pre.handle == batch.handle) &&
			(batch.clipped_to == current_clipping_rect) \
		)
	}

	set_rect_batch_texture_if_nil_before :: #force_inline proc(batch: ^UiBatch, pre: ^PreBatch) {
		if batch.kind == .Rect && pre.kind == .Rect && batch.handle == 0 {
			batch.handle = pre.handle
		}
	}

	/////////////////////////////////
	// start actual execution:
	/////////////////////////////////

	clear_batches(batches)
	if UI_MEMORY.elements_len == 0 {
		return
	}

	Clipping :: struct {
		end_idx: int,
		rect:    Aabb,
	}
	current_clipping := Clipping {
		end_idx = UI_MEMORY.elements_len,
		rect    = {Vec2{0, 0}, Vec2{0, 0}},
	}
	clipping_stack: [8]Clipping
	clipping_stack_len := 0

	current_batch: UiBatch // zero-initialized
	pre_batches := make([dynamic]PreBatch, allocator = context.temp_allocator)

	ZRange :: struct {
		z:         UiZIndex,
		start_idx: int,
		end_idx:   int,
	}
	// z_ranges is a list of ranges of elements that is always sorted after z, start_idx.
	// first, we see all elements as one range, but whenever we encounter an element that has a higher z 
	// value than the current range we operate on, we create a new range for the entire subtree of that
	// element. This entire subtree is only handled after the original element range is done.
	// of course this subtree can contain other ranges again and so on, and so on.
	// Every UI element is still only visited once or max. twice (if opens a new z_range).
	// 
	// Current limitation: only positive z-index and z-bias work, we can only raise the level of elements, not lower them.
	z_ranges := make([dynamic]ZRange, allocator = context.temp_allocator)
	append(&z_ranges, ZRange{start_idx = 0, end_idx = UI_MEMORY.elements_len, z = 0})

	n_indices := 0
	n_glyphs := 0

	for len(z_ranges) > 0 {
		z_range := pop(&z_ranges)
		for i := z_range.start_idx; i < z_range.end_idx; i += 1 {
			element := &UI_MEMORY.elements[i]
			if element.z > z_range.z {
				new_range := ZRange {
					start_idx = i,
					end_idx   = i + 1,
					z         = element.z,
				}
				#partial switch var in element.variant {
				case DivWithComputed:
					new_range.end_idx = i + var.skipped
					i += var.skipped - 1 // skip over entire subtree and handle this subtree after all other elements have been handled.
				}

				// find position in ranges to insert this z section: z_ranges should be sorted after z and start_idx
				insert_idx := -1
				for r, i in z_ranges {
					if r.z >= new_range.z && r.start_idx > new_range.start_idx {
						insert_idx := i
						break
					}
				}
				if insert_idx != -1 {
					inject_at(&z_ranges, insert_idx, new_range)
				} else {
					append(&z_ranges, new_range)
				}
				continue
			}


			add_primitives(element, &batches.primitives, &pre_batches)

			// pop last element off clipping stack, if we reach end_idx. Can be multiple times if multiple clipping hierarchies end on same idx.
			for {
				if i == current_clipping.end_idx {
					assert(clipping_stack_len > 0)
					clipping_stack_len -= 1
					current_clipping = clipping_stack[clipping_stack_len]
				} else {
					break
				}
			}

			for &next in pre_batches {
				// in case where we are in a rect batch where the current elements all have nil texture, but this one has a texture,
				// we can still keep them in one batch, but update the batches texture pointer.
				// the information which rect should sample the texture and which should not is available per vertex via flag TEXTURED.

				if is_compatible(&current_batch, &next, current_clipping.rect) {
					set_rect_batch_texture_if_nil_before(&current_batch, &next)
				} else {
					switch current_batch.kind {
					case .Rect:
						current_batch.end_idx = n_indices
					case .Glyph:
						current_batch.end_idx = n_glyphs
					}

					// add the current batch to batches if not empty:
					next_batch_can_be_batch_before_current := false
					if current_batch.end_idx == current_batch.start_idx {
						batches_len := len(batches.batches)
						if batches_len != 0 {
							last_batch := &batches.batches[batches_len - 1]
							if is_compatible(last_batch, &next, current_clipping.rect) {
								next_batch_can_be_batch_before_current = true
							}
						}
					} else {
						append(&batches.batches, current_batch)
					}

					if next_batch_can_be_batch_before_current {
						current_batch = pop(&batches.batches)
					} else {
						start_idx: int = ---
						switch next.kind {
						case .Rect:
							start_idx = n_indices
						case .Glyph:
							start_idx = n_glyphs
						}

						current_batch = UiBatch {
							start_idx  = start_idx,
							end_idx    = start_idx,
							kind       = next.kind,
							handle     = next.handle,
							clipped_to = current_clipping.rect,
						}
					}
				}
				switch next.kind {
				case .Rect:
					n_indices = next.end_idx
				case .Glyph:
					n_glyphs = next.end_idx
				}

			}
			clear(&pre_batches)

			// if this div clips its contents, set the clipping rect:
			#partial switch &e in element.variant {
			case DivWithComputed:
				if .ClipContent in e.flags {
					clipping_stack[clipping_stack_len] = current_clipping
					clipping_stack_len += 1
					current_clipping = Clipping {
						end_idx = i + e.skipped,
						rect    = Aabb{element.pos, element.pos + element.size},
					}
				}
			}
		}
	}


	// end the last batch and append it if not empty:
	switch current_batch.kind {
	case .Rect:
		current_batch.end_idx = n_indices
	case .Glyph:
		current_batch.end_idx = n_glyphs
	}
	if current_batch.start_idx != current_batch.end_idx {
		append(&batches.batches, current_batch)
	}


	// os.write_entire_file("batches.txt", transmute([]u8)fmt.aprint(batches))
	// panic("Done")
}


add_rect :: #force_inline proc(
	primitives: ^Primitives,
	pre_batches: ^[dynamic]PreBatch,
	pos: Vec2,
	size: Vec2,
	color: Color,
	border_color: Color,
	border_width: BorderWidth,
	border_radius: BorderRadius,
	texture: TextureTile,
) {

	vertices := &primitives.vertices
	indices := &primitives.indices
	start_v := u32(len(vertices))

	flags_all: u32 = 0
	if texture.handle != 0 {
		flags_all |= UI_VERTEX_FLAG_TEXTURED
	}


	vertex := UiVertex {
		pos           = pos,
		size          = size,
		uv            = texture.uv.min,
		color         = color,
		border_color  = border_color,
		border_radius = border_radius,
		border_width  = border_width,
		flags         = flags_all,
	}
	append(vertices, vertex)
	vertex.pos = {pos.x, pos.y + size.y}
	vertex.flags = flags_all | UI_VERTEX_FLAG_BOTTOM_VERTEX
	vertex.uv = {texture.uv.min.x, texture.uv.max.y}
	append(vertices, vertex)
	vertex.pos = pos + size
	vertex.flags = flags_all | UI_VERTEX_FLAG_BOTTOM_VERTEX | UI_VERTEX_FLAG_RIGHT_VERTEX
	vertex.uv = {texture.uv.max.x, texture.uv.max.y}
	append(vertices, vertex)
	vertex.pos = {pos.x + size.x, pos.y}
	vertex.flags = flags_all | UI_VERTEX_FLAG_RIGHT_VERTEX
	vertex.uv = {texture.uv.max.x, texture.uv.min.y}
	append(vertices, vertex)

	append(indices, start_v)
	append(indices, start_v + 1)
	append(indices, start_v + 2)
	append(indices, start_v)
	append(indices, start_v + 2)
	append(indices, start_v + 3)

	append(
		pre_batches,
		PreBatch {
			end_idx = len(primitives.indices),
			kind = .Rect,
			handle = TextureOrFontHandle(texture.handle),
		},
	)
}


add_primitives :: #force_inline proc(
	element: ^UiElement,
	primitives: ^Primitives,
	pre_batches: ^[dynamic]PreBatch, // append only!
) {
	switch &e in element.variant {
	case DivWithComputed:
		if e.color == {0, 0, 0, 0} || element.size.x == 0 || element.size.y == 0 {
			return
		}

		vertices := &primitives.vertices
		indices := &primitives.indices
		start_v := u32(len(vertices))

		flags_all: u32 = 0
		if e.texture.handle != 0 {
			flags_all |= UI_VERTEX_FLAG_TEXTURED
		}

		max_border_radius := min(element.size.x, element.size.y) / 2.0
		if e.border_radius.top_left > max_border_radius {
			e.border_radius.top_left = max_border_radius
		}
		if e.border_radius.top_right > max_border_radius {
			e.border_radius.top_right = max_border_radius
		}
		if e.border_radius.bottom_right > max_border_radius {
			e.border_radius.bottom_right = max_border_radius
		}
		if e.border_radius.bottom_left > max_border_radius {
			e.border_radius.bottom_left = max_border_radius
		}

		add_rect(
			primitives,
			pre_batches,
			element.pos,
			element.size,
			e.color,
			e.border_color,
			e.border_width,
			e.border_radius,
			e.texture,
		)

	case TextWithComputed:
		// todo! seems like we could swap UI_MEMORY.glyphs over to batches directly.
		for g in UI_MEMORY.glyphs[e.glyphs_start_idx:e.glyphs_end_idx] {
			append(
				&primitives.glyphs_instances,
				UiGlyphInstance {
					pos = g.pos,
					size = g.size,
					uv = g.uv,
					color = e.color,
					shadow = e.shadow,
				},
			)
		}
		append(
			pre_batches,
			PreBatch {
				end_idx = len(primitives.glyphs_instances),
				kind = .Glyph,
				handle = TextureOrFontHandle(e.font),
			},
		)
	case CustomUiElement:
		e.add_primitives(&e.data, element.pos, element.size, primitives, pre_batches)
	}
}

clear_batches :: proc(batches: ^UiBatches) {
	clear(&batches.primitives.vertices)
	clear(&batches.primitives.indices)
	clear(&batches.primitives.glyphs_instances)
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
}

ui_renderer_render :: proc(
	rend: ^UiRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_bind_group: wgpu.BindGroup,
	screen_size: UVec2,
	assets: AssetManager,
) {
	screen_size_f32 := Vec2{f32(screen_size.x), f32(screen_size.y)}
	NO_CLIPPING_RECT :: Aabb{{0, 0}, {0, 0}}
	if len(rend.batches.batches) == 0 {
		return
	}
	last_kind := rend.batches.batches[0].kind
	pipeline: ^RenderPipeline = nil
	for &batch in rend.batches.batches {
		if batch.kind != last_kind || pipeline == nil {
			last_kind = batch.kind
			switch batch.kind {
			case .Rect:
				pipeline = &rend.rect_pipeline
			case .Glyph:
				pipeline = &rend.glyph_pipeline
			}

			if batch.clipped_to != NO_CLIPPING_RECT {
				// convert clipping rect from layout to screen space and then set it:
				min_f32 := layout_to_screen_space(batch.clipped_to.min, screen_size_f32)
				max_f32 := layout_to_screen_space(batch.clipped_to.max, screen_size_f32)
				min_x := u32(min_f32.x)
				min_y := u32(min_f32.y)
				width_x := u32(max_f32.x) - min_x
				width_y := u32(max_f32.y) - min_y
				wgpu.RenderPassEncoderSetScissorRect(render_pass, min_x, min_y, width_x, width_y)
			} else {
				wgpu.RenderPassEncoderSetScissorRect(
					render_pass,
					0,
					0,
					screen_size.x,
					screen_size.y,
				)
			}
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


		switch batch.kind {
		case .Rect:
			if batch.handle != 0 {
				texture_bind_group := assets_get_texture_bind_group(
					assets,
					TextureHandle(batch.handle),
				)
				wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_bind_group)
			}
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
			font_texture_bind_group := assets_get_font_texture_bind_group(
				assets,
				FontHandle(batch.handle),
			)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, font_texture_bind_group)
			instance_count := u32(batch.end_idx - batch.start_idx)
			wgpu.RenderPassEncoderDraw(render_pass, 4, instance_count, 0, u32(batch.start_idx))
		}
	}
}


screen_to_layout_space :: proc(pt: Vec2, screen_size: Vec2) -> Vec2 {
	return pt * (f32(SCREEN_REFERENCE_SIZE.y) / screen_size.y)
}

layout_to_screen_space :: proc(pt: Vec2, screen_size: Vec2) -> Vec2 {
	return pt * (screen_size.y / f32(SCREEN_REFERENCE_SIZE.y))
}

ui_renderer_start_frame :: proc(rend: ^UiRenderer, screen_size: Vec2, platform: ^Platform) {
	cache := &rend.cache
	cache.platform = platform
	cache.layout_extent = Vec2 {
		f32(SCREEN_REFERENCE_SIZE.y) * screen_size.x / screen_size.y,
		f32(SCREEN_REFERENCE_SIZE.y),
	}
	cache.cursor_pos = screen_to_layout_space(platform.cursor_pos, screen_size)
	ui_start_frame(cache)
}

ui_renderer_end_frame_and_prepare_buffers :: proc(
	rend: ^UiRenderer,
	delta_secs: f32,
	asset_manager: AssetManager,
) {
	ui_end_frame(&rend.batches, rend.cache.layout_extent, delta_secs, asset_manager)
	dynamic_buffer_write(
		&rend.vertex_buffer,
		rend.batches.primitives.vertices[:],
		rend.device,
		rend.queue,
	)
	dynamic_buffer_write(
		&rend.index_buffer,
		rend.batches.primitives.indices[:],
		rend.device,
		rend.queue,
	)
	dynamic_buffer_write(
		&rend.glyph_instance_buffer,
		rend.batches.primitives.glyphs_instances[:],
		rend.device,
		rend.queue,
	)
}

ui_renderer_create :: proc(
	rend: ^UiRenderer,
	platform: ^Platform,
	default_font_color: Color,
	default_font_size: f32,
) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.rect_pipeline.config = ui_rect_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.rect_pipeline, &platform.shader_registry)
	rend.glyph_pipeline.config = ui_glyph_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.glyph_pipeline, &platform.shader_registry)
	UI_MEMORY.default_font = 0
	UI_MEMORY.default_font_color = default_font_color
	UI_MEMORY.default_font_size = default_font_size

	rend.vertex_buffer.usage = {.Vertex}
	rend.index_buffer.usage = {.Index}
	rend.glyph_instance_buffer.usage = {.Vertex}

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
}

ui_batches_destroy :: proc(batches: ^UiBatches) {
	delete(batches.primitives.vertices)
	delete(batches.primitives.indices)
	delete(batches.primitives.glyphs_instances)
	delete(batches.batches)
}
