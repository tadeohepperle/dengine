package dengine

import "core:image"
import "core:math"
import "core:time"
// This module exposes a simple interface relying on some global state. 
ENGINE: Engine
SCENE: Scene

init :: proc(settings: EngineSettings = DEFAULT_ENGINE_SETTINGS) {
	engine_create(&ENGINE, settings)
	scene_create(&SCENE)
}
deinit :: proc() {
	scene_destroy(&SCENE)
	engine_destroy(&ENGINE)
}

next_frame :: proc() -> bool {
	@(static)LOOP_INITIALIZED := false

	if LOOP_INITIALIZED {
		engine_end_frame(&ENGINE, &SCENE)
	} else {
		LOOP_INITIALIZED = true
	}
	return engine_start_frame(&ENGINE, &SCENE)
}

get_mouse_btn :: proc(btn: MouseButton = .Left) -> PressFlags {
	return ENGINE.input.mouse_buttons[btn]
}
get_scroll :: proc() -> f32 {
	return ENGINE.input.scroll
}
get_hit_pos :: #force_inline proc() -> Vec2 {
	return ENGINE.hit_pos
}

/// with left mouse button
is_double_clicked :: proc() -> bool {
	return ENGINE.input.double_clicked
}
is_just_left_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.input.mouse_buttons[.Left]
}
is_just_left_released :: proc() -> bool {
	return .JustReleased in ENGINE.input.mouse_buttons[.Left]
}
is_key_pressed :: #force_inline proc(key: Key) -> bool {
	return .Pressed in ENGINE.input.keys[key]
}
is_shift_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.input.keys[.LEFT_SHIFT]
}
is_ctrl_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.input.keys[.LEFT_CONTROL]
}
load_texture :: proc(
	path: string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> TextureHandle {
	return assets_load_texture(&ENGINE.assets, path, settings)
}
load_texture_tile :: proc(
	path: string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> TextureTile {
	return TextureTile{load_texture(path, settings), UNIT_AABB}
}
load_texture_array :: proc(
	paths: []string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> TextureArrayHandle {
	return assets_load_texture_array(&ENGINE.assets, paths, settings)
}
load_font :: proc(path: string) -> FontHandle {
	return assets_load_font(&ENGINE.assets, path)
}
draw_sprite :: #force_inline proc(sprite: Sprite) {
	append(&SCENE.sprites, sprite)
}
draw_terrain_mesh :: #force_inline proc(mesh: ^TerrainMesh) {
	append(&SCENE.terrain_meshes, mesh)
}
draw_gizmos_aabb :: proc(
	aabb: Aabb,
	color := Color{1, 0, 0, 1},
	mode := GizmosMode.WORLD_SPACE_2D,
) {
	gizmos_renderer_add_aabb(&ENGINE.gizmos_renderer, aabb, color, mode)
}
draw_gizmos_rect :: proc(
	center: Vec2,
	size: Vec2,
	color := Color{1, 0, 0, 1},
	mode := GizmosMode.WORLD_SPACE_2D,
) {
	gizmos_renderer_add_rect(&ENGINE.gizmos_renderer, center, size, color, mode)
}
draw_gizmos_line :: proc(
	from: Vec2,
	to: Vec2,
	color := Color{1, 0, 0, 1},
	mode := GizmosMode.WORLD_SPACE_2D,
) {
	gizmos_renderer_add_line(&ENGINE.gizmos_renderer, from, to, color, mode)
}
draw_gizmos_circle :: proc(
	center: Vec2,
	radius: f32,
	color: Color = Color_Red,
	segments: int = 12,
	draw_inner_lines: bool = false,
) {
	gizmos_renderer_add_circle(
		&ENGINE.gizmos_renderer,
		center,
		radius,
		color,
		segments,
		draw_inner_lines,
	)
}
// Can write directly into these, instead of using one of the `draw_color_mesh` procs.
access_color_mesh_write_buffers :: proc(
) -> (
	vertices: ^[dynamic]ColorMeshVertex,
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
draw_color_mesh_vertices_single_color :: proc(positions: []Vec2, color := Color_Red) {
	color_mesh_add_vertices_single_color(&ENGINE.color_mesh_renderer, positions, color)
}
draw_color_mesh_vertices :: proc(vertices: []ColorMeshVertex) {
	color_mesh_add_vertices(&ENGINE.color_mesh_renderer, vertices)
}
draw_color_mesh_indexed :: proc(vertices: []ColorMeshVertex, indices: []u32) {
	color_mesh_add_indexed(&ENGINE.color_mesh_renderer, vertices, indices)
}
draw_color_mesh_indexed_single_color :: proc(
	positions: []Vec2,
	indices: []u32,
	color := Color_Red,
) {
	color_mesh_add_indexed_single_color(&ENGINE.color_mesh_renderer, positions, indices, color)
}
add_circle_collider :: proc(pos: Vec2, radius: f32, metadata: ColliderMetadata, z: int = 0) {
	append(
		&SCENE.colliders,
		Collider{shape = Circle{pos = pos, radius = radius}, metadata = metadata, z = z},
	)
}
add_aabb_collider :: proc(aabb: Aabb, metadata: ColliderMetadata, z: int = 0) {
	append(&SCENE.colliders, Collider{shape = aabb, metadata = metadata, z = z})
}
add_triangle_collider :: proc(a: Vec2, b: Vec2, c: Vec2, metadata: ColliderMetadata, z: int = 0) {
	append(&SCENE.colliders, Collider{shape = Triangle{a, b, c}, metadata = metadata, z = z})
}
add_rect_collider :: proc(
	center: Vec2,
	size: Vec2,
	rotation: f32,
	metadata: ColliderMetadata,
	z: int = 0,
) {
	append(
		&SCENE.colliders,
		Collider{shape = rotated_rect(center, size, rotation), metadata = metadata, z = z},
	)
}
