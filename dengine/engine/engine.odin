package engine

// This shows a little engine implementation based on the dengine framework. 
// Please use this only for experimentation and develop your own engine with custom renderers
// and custom control from for each specific project. We do NOT attempt to make a one size fits all thing here.

import d "../"
import "core:math"
import wgpu "vendor:wgpu"

Vec2 :: d.Vec2
Vec3 :: d.Vec3
Color :: d.Color
print :: d.print

Renderers :: struct {
	bloom_renderer:      d.BloomRenderer,
	sprite_renderer:     d.SpriteRenderer,
	gizmos_renderer:     d.GizmosRenderer,
	ui_renderer:         d.UiRenderer,
	color_mesh_renderer: d.ColorMeshRenderer,
	terrain_renderer:    d.TerrainRenderer,
}

GIZMOS_COLOR := d.Color{1, 0, 0, 1}
DEFAULT_FONT_COLOR := d.Color_White
DEFAULT_FONT_SIZE: f32 = 16
_renderers_create :: proc(ren: ^Renderers, platform: ^d.Platform) {
	d.bloom_renderer_create(&ren.bloom_renderer, platform)
	d.sprite_renderer_create(&ren.sprite_renderer, platform)
	d.gizmos_renderer_create(&ren.gizmos_renderer, platform)
	d.ui_renderer_create(&ren.ui_renderer, platform, DEFAULT_FONT_COLOR, DEFAULT_FONT_SIZE)
	d.color_mesh_renderer_create(&ren.color_mesh_renderer, platform)
	d.terrain_renderer_create(&ren.terrain_renderer, platform)
}
_renderers_destroy :: proc(ren: ^Renderers) {
	d.bloom_renderer_destroy(&ren.bloom_renderer)
	d.sprite_renderer_destroy(&ren.sprite_renderer)
	d.gizmos_renderer_destroy(&ren.gizmos_renderer)
	d.ui_renderer_destroy(&ren.ui_renderer)
	d.color_mesh_renderer_destroy(&ren.color_mesh_renderer)
	d.terrain_renderer_destroy(&ren.terrain_renderer)
}

EngineSettings :: struct {
	using platform:        d.PlatformSettings,
	bloom_enabled:         bool,
	bloom_settings:        d.BloomSettings,
	debug_ui_gizmos:       bool,
	debug_collider_gizmos: bool,
}
ENGINE_SETTINGS_DEFAULT :: EngineSettings {
	platform              = d.PLATFORM_SETTINGS_DEFAULT,
	bloom_enabled         = true,
	bloom_settings        = d.BLOOM_SETTINGS_DEFAULT,
	debug_ui_gizmos       = false,
	debug_collider_gizmos = true,
}
Engine :: struct {
	settings:        EngineSettings,
	using renderers: Renderers,
	platform:        d.Platform,
	hit:             HitInfo,
	scene:           Scene,
}

Scene :: struct {
	camera:               d.Camera,
	sprites:              [dynamic]d.Sprite,
	terrain_meshes:       [dynamic]^d.TerrainMesh,
	terrain_textures:     d.TextureArrayHandle,
	colliders:            [dynamic]d.Collider,
	last_frame_colliders: [dynamic]d.Collider,
}

HitInfo :: struct {
	screen_ray:        d.Ray,
	hit_xy_plane:      bool,
	hit_xy_plane_pt:   Vec2,
	hit_xz_plane:      bool,
	hit_xz_plane_pt:   Vec2,
	hit_collider_idx:  int,
	hit_collider:      d.ColliderMetadata,
	hit_collider_dist: f32,
	is_on_ui:          bool,
}

_scene_create :: proc(scene: ^Scene) {
	scene.camera = d.DEFAULT_CAMERA
}

_scene_destroy :: proc(scene: ^Scene) {
	delete(scene.sprites)
}

_scene_clear :: proc(scene: ^Scene) {
	clear(&scene.sprites)
	clear(&scene.terrain_meshes)
	scene.last_frame_colliders, scene.colliders = scene.colliders, scene.last_frame_colliders
	clear(&scene.colliders)
}


ENGINE: Engine

_engine_create :: proc(engine: ^Engine, settings: EngineSettings) {
	engine.settings = settings
	d.platform_create(&engine.platform, settings.platform)
	_renderers_create(&engine.renderers, &engine.platform)
	_scene_create(&engine.scene)
}

_engine_destroy :: proc(engine: ^Engine) {
	d.platform_destroy(&engine.platform)
	_renderers_destroy(&engine.renderers)
	_scene_destroy(&engine.scene)
}


init :: proc(settings: EngineSettings = ENGINE_SETTINGS_DEFAULT) {
	_engine_create(&ENGINE, settings)
}

deinit :: proc() {
	_engine_destroy(&ENGINE)
}

next_frame :: proc() -> bool {
	@(static) LOOP_INITIALIZED := false

	if LOOP_INITIALIZED {
		_engine_end_frame(&ENGINE)
	} else {
		LOOP_INITIALIZED = true
	}
	return _engine_start_frame(&ENGINE)
}

_engine_start_frame :: proc(engine: ^Engine) -> bool {
	if !d.platform_start_frame(&engine.platform) {
		return false
	}
	_engine_recalculate_hit_info(engine)
	d.ui_renderer_start_frame(
		&engine.ui_renderer,
		engine.platform.screen_size_f32,
		&engine.platform,
	)
	return true
}

_engine_recalculate_hit_info :: proc(engine: ^Engine) {
	hit: HitInfo
	camera_raw := d.camera_to_raw(engine.scene.camera, engine.platform.screen_size_f32)
	hit.screen_ray = d.camera_ray_from_screen_pos(
		camera_raw,
		engine.platform.cursor_pos,
		engine.platform.screen_size_f32,
	)
	_, hit_xy_plane_pt, hit_xy_plane := d.ray_intersects_xy_plane(hit.screen_ray)
	_, hit_xz_plane_pt, hit_xz_plane := d.ray_intersects_xz_plane(hit.screen_ray)

	hit.hit_collider_dist = max(f32)
	hit.hit_collider = d.NO_COLLIDER
	hit.hit_collider_idx = -1
	for &e, i in engine.scene.last_frame_colliders {
		dist, is_hit := d.ray_intersects_shape(hit.screen_ray, e.shape)
		if is_hit {
			if dist < hit.hit_collider_dist {
				hit.hit_collider_dist = dist
				hit.hit_collider = e.metadata
				hit.hit_collider_idx = i
			}

		}
	}
	hit.is_on_ui = engine.ui_renderer.cache.state.hovered_id != 0
	engine.hit = hit
}

_engine_end_frame :: proc(engine: ^Engine) {
	// RESIZE AND END INPUT:
	if engine.platform.screen_resized {
		d.platform_resize(&engine.platform)
		d.bloom_renderer_resize(&engine.bloom_renderer, engine.platform.screen_size)
	}
	if engine.settings.debug_ui_gizmos {
		_engine_debug_ui_gizmos(engine)
	}
	if engine.settings.debug_collider_gizmos {
		_engine_debug_collider_gizmos(engine)
	}
	engine.platform.settings = engine.settings.platform
	d.platform_reset_input_at_end_of_frame(&engine.platform)
	// PREPARE
	_engine_prepare(engine)
	// RENDER
	_engine_render(engine)
	// CLEAR
	_scene_clear(&engine.scene)
	free_all(context.temp_allocator)
}

_engine_prepare :: proc(engine: ^Engine) {
	engine.platform.camera = engine.scene.camera
	d.platform_prepare(&engine.platform)
	d.sprite_renderer_prepare(&engine.sprite_renderer, engine.scene.sprites[:])
	d.color_mesh_renderer_prepare(&engine.color_mesh_renderer)
	d.gizmos_renderer_prepare(&engine.gizmos_renderer, engine.scene.sprites[:])
	d.ui_renderer_end_frame_and_prepare_buffers(
		&engine.ui_renderer,
		engine.platform.delta_secs,
		engine.platform.asset_manager,
	)
}

_engine_render :: proc(engine: ^Engine) {
	// acquire surface texture:
	surface_texture, surface_view, command_encoder := d.platform_start_render(&engine.platform)

	// hdr render pass:
	hdr_pass := d.platform_start_hdr_pass(engine.platform, command_encoder)
	global_bind_group := engine.platform.globals.bind_group
	asset_manager := engine.platform.asset_manager
	d.terrain_renderer_render(
		&engine.terrain_renderer,
		hdr_pass,
		global_bind_group,
		engine.scene.terrain_meshes[:],
		engine.scene.terrain_textures,
		asset_manager,
	)
	d.sprite_renderer_render(&engine.sprite_renderer, hdr_pass, global_bind_group, asset_manager)
	d.color_mesh_renderer_render(&engine.color_mesh_renderer, hdr_pass, global_bind_group)
	d.gizmos_renderer_render(&engine.gizmos_renderer, hdr_pass, global_bind_group, .WORLD_SPACE)
	d.ui_renderer_render(
		&engine.ui_renderer,
		hdr_pass,
		global_bind_group,
		engine.platform.screen_size,
		asset_manager,
	)
	d.gizmos_renderer_render(
		&engine.gizmos_renderer,
		hdr_pass,
		global_bind_group,
		.UI_LAYOUT_SPACE,
	)
	wgpu.RenderPassEncoderEnd(hdr_pass)
	wgpu.RenderPassEncoderRelease(hdr_pass)

	// bloom:
	if engine.settings.bloom_enabled {
		d.render_bloom(
			command_encoder,
			&engine.bloom_renderer,
			&engine.platform.hdr_screen_texture,
			global_bind_group,
			engine.settings.bloom_settings,
		)
	}

	d.platform_end_render(&engine.platform, surface_texture, surface_view, command_encoder)
}


@(private)
_engine_debug_ui_gizmos :: proc(engine: ^Engine) {
	cache := &engine.ui_renderer.cache
	state := &cache.state

	@(static) last_state: d.InteractionState(d.UiId)

	if state.hovered_id != last_state.hovered_id {
		print("  hovered_id:", last_state.hovered_id, "->", state.hovered_id)
	}
	if state.pressed_id != last_state.pressed_id {
		print("  pressed_id:", last_state.pressed_id, "->", state.pressed_id)
	}
	if state.focused_id != last_state.focused_id {
		print("  focused_id:", last_state.focused_id, "->", state.focused_id)
	}
	last_state = state^


	for k, v in cache.cached {
		color := d.Color_Light_Blue
		if state.hovered_id == k {
			color = d.Color_Yellow
		}
		if state.focused_id == k {
			color = d.Color_Violet
		}
		if state.pressed_id == k {
			color = d.Color_Red
		}
		d.gizmos_renderer_add_aabb(&engine.gizmos_renderer, {v.pos, v.pos + v.size}, color, .UI)
	}

	// for &e in UI_MEMORY_elements() {
	// 	color: Color = ---
	// 	switch &var in &e.variant {
	// 	case DivWithComputed:
	// 		color = Color_Red
	// 	case TextWithComputed:
	// 		color = Color_Yellow
	// 	case CustomUiElement:
	// 		color = Color_Green
	// 	}
	// 	
	// }
}


@(private)
_engine_debug_collider_gizmos :: proc(engine: ^Engine) {
	add_collider_gizmos :: #force_inline proc(
		rend: ^d.GizmosRenderer,
		shape: d.ColliderShape,
		color: d.Color,
	) {
		switch s in shape {
		case d.Sphere:
			panic("not implemented yet")
		case d.Triangle:
			d.gizmos_renderer_add_line_3d(rend, s.a, s.b, color, .WORLD_SPACE)
			d.gizmos_renderer_add_line_3d(rend, s.b, s.c, color, .WORLD_SPACE)
			d.gizmos_renderer_add_line_3d(rend, s.c, s.a, color, .WORLD_SPACE)
		case d.Quad:
			d.gizmos_renderer_add_line_3d(rend, s.a, s.b, color, .WORLD_SPACE)
			d.gizmos_renderer_add_line_3d(rend, s.b, s.c, color, .WORLD_SPACE)
			d.gizmos_renderer_add_line_3d(rend, s.c, s.d, color, .WORLD_SPACE)
			d.gizmos_renderer_add_line_3d(rend, s.d, s.a, color, .WORLD_SPACE)
		}
	}


	for collider, i in engine.scene.colliders {
		color := d.Color_Yellow if i == engine.hit.hit_collider_idx else d.Color_Light_Blue
		add_collider_gizmos(&engine.gizmos_renderer, collider.shape, color)
	}
}

get_mouse_btn :: proc(btn: d.MouseButton = .Left) -> d.PressFlags {
	return ENGINE.platform.mouse_buttons[btn]
}
get_scroll :: proc() -> f32 {
	return ENGINE.platform.scroll
}
get_hit :: #force_inline proc() -> HitInfo {
	return ENGINE.hit
}
get_delta_secs :: proc() -> f32 {
	return ENGINE.platform.delta_secs
}
get_total_secs :: proc() -> f32 {
	return ENGINE.platform.total_secs
}
get_osc :: proc(speed: f32 = 1, phase: f32 = 0, amplitude: f32 = 1, bias: f32 = 0) -> f32 {
	return math.sin_f32(ENGINE.platform.total_secs * speed + phase) * amplitude + bias
}
is_double_clicked :: proc() -> bool {
	return ENGINE.platform.double_clicked
}
is_left_just_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.platform.mouse_buttons[.Left]
}
is_left_pressed :: proc() -> bool {
	return .Pressed in ENGINE.platform.mouse_buttons[.Left]
}
is_left_just_released :: proc() -> bool {
	return .JustReleased in ENGINE.platform.mouse_buttons[.Left]
}
is_right_just_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.platform.mouse_buttons[.Right]
}
is_right_pressed :: proc() -> bool {
	return .Pressed in ENGINE.platform.mouse_buttons[.Right]
}
is_right_just_released :: proc() -> bool {
	return .JustReleased in ENGINE.platform.mouse_buttons[.Right]
}
is_key_pressed :: #force_inline proc(key: d.Key) -> bool {
	return .Pressed in ENGINE.platform.keys[key]
}
is_shift_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.platform.keys[.LEFT_SHIFT]
}
is_ctrl_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.platform.keys[.LEFT_CONTROL]
}
load_texture :: proc(
	path: string,
	settings: d.TextureSettings = d.TEXTURE_SETTINGS_DEFAULT,
) -> d.TextureHandle {
	return d.assets_load_texture(&ENGINE.platform.asset_manager, path, settings)
}
load_texture_tile :: proc(
	path: string,
	settings: d.TextureSettings = d.TEXTURE_SETTINGS_DEFAULT,
) -> d.TextureTile {
	return d.TextureTile{load_texture(path, settings), d.UNIT_AABB}
}
load_texture_array :: proc(
	paths: []string,
	settings: d.TextureSettings = d.TEXTURE_SETTINGS_DEFAULT,
) -> d.TextureArrayHandle {
	return d.assets_load_texture_array(&ENGINE.platform.asset_manager, paths, settings)
}
load_font :: proc(path: string) -> d.FontHandle {
	return d.assets_load_font(&ENGINE.platform.asset_manager, path)
}
draw_sprite :: #force_inline proc(sprite: d.Sprite) {
	append(&ENGINE.scene.sprites, sprite)
}
draw_terrain_mesh :: #force_inline proc(mesh: ^d.TerrainMesh) {
	append(&ENGINE.scene.terrain_meshes, mesh)
}
draw_gizmos_box :: proc(center: Vec3, size: Vec3, color := GIZMOS_COLOR) {
	d.gizmos_renderer_add_box_3d(&ENGINE.gizmos_renderer, center, size, color)
}
draw_gizmos_sphere :: proc(center: Vec3, radius: f32, color := GIZMOS_COLOR) {
	d.gizmos_renderer_add_sphere(&ENGINE.gizmos_renderer, center, radius, color)
}
draw_gizmos_line :: proc(from: Vec3, to: Vec3, color := GIZMOS_COLOR) {
	d.gizmos_renderer_add_line_3d(&ENGINE.gizmos_renderer, from, to, color, .WORLD_SPACE)
}
draw_gizmos_circle_xy :: proc(
	center: Vec2,
	radius: f32,
	color: Color = d.Color_Red,
	segments: int = 12,
	draw_inner_lines: bool = false,
) {
	d.gizmos_renderer_add_circle(
		&ENGINE.gizmos_renderer,
		center,
		radius,
		color,
		segments,
		draw_inner_lines,
		.WORLD_XY,
	)
}
draw_gizmos_circle_xz :: proc(
	center: Vec2,
	radius: f32,
	color: Color = d.Color_Red,
	segments: int = 12,
	draw_inner_lines: bool = false,
) {
	d.gizmos_renderer_add_circle(
		&ENGINE.gizmos_renderer,
		center,
		radius,
		color,
		segments,
		draw_inner_lines,
		.WORLD_XZ,
	)
}
// Can write directly into these, instead of using one of the `draw_color_mesh` procs.
access_color_mesh_write_buffers :: proc(
) -> (
	vertices: ^[dynamic]d.ColorMeshVertex,
	indices: ^[dynamic]u32,
) {
	indices = &ENGINE.color_mesh_renderer.indices
	vertices = &ENGINE.color_mesh_renderer.vertices
	return
}
draw_color_mesh :: proc {
	draw_color_mesh_vertices_single_color,
	draw_color_mesh_vertices,
	draw_color_mesh_indexed_single_color,
	draw_color_mesh_indexed,
}
draw_color_mesh_vertices_single_color :: proc(positions: []Vec3, color := Color{1, 0, 0, 1}) {
	d.color_mesh_add_vertices_single_color(&ENGINE.color_mesh_renderer, positions, color)
}
draw_color_mesh_vertices :: proc(vertices: []d.ColorMeshVertex) {
	d.color_mesh_add_vertices(&ENGINE.color_mesh_renderer, vertices)
}
draw_color_mesh_indexed :: proc(vertices: []d.ColorMeshVertex, indices: []u32) {
	d.color_mesh_add_indexed(&ENGINE.color_mesh_renderer, vertices, indices)
}
draw_color_mesh_indexed_single_color :: proc(
	positions: []Vec3,
	indices: []u32,
	color := Color{1, 0, 0, 1},
) {
	d.color_mesh_add_indexed_single_color(&ENGINE.color_mesh_renderer, positions, indices, color)
}
add_sphere_collider :: proc(metadata: d.ColliderMetadata, center: Vec3, radius: f32) {
	append(
		&ENGINE.scene.colliders,
		d.Collider{shape = d.Sphere{center, radius}, metadata = metadata},
	)
}
add_quad_collider :: proc(quad: d.Quad, metadata: d.ColliderMetadata) {
	append(&ENGINE.scene.colliders, d.Collider{shape = quad, metadata = metadata})
}
add_triangle_collider :: proc(triangle: d.Triangle, metadata: d.ColliderMetadata) {
	append(&ENGINE.scene.colliders, d.Collider{shape = triangle, metadata = metadata})
}
