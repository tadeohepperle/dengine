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
get_hit :: #force_inline proc() -> HitInfo {
	return ENGINE.hit
}

/// with left mouse button
is_double_clicked :: proc() -> bool {
	return ENGINE.input.double_clicked
}
is_left_just_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.input.mouse_buttons[.Left]
}
is_left_pressed :: proc() -> bool {
	return .Pressed in ENGINE.input.mouse_buttons[.Left]
}
is_left_just_released :: proc() -> bool {
	return .JustReleased in ENGINE.input.mouse_buttons[.Left]
}
is_right_just_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.input.mouse_buttons[.Right]
}
is_right_pressed :: proc() -> bool {
	return .Pressed in ENGINE.input.mouse_buttons[.Right]
}
is_right_just_released :: proc() -> bool {
	return .JustReleased in ENGINE.input.mouse_buttons[.Right]
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
draw_gizmos_box :: proc(center: Vec3, size: Vec3, color := GIZMOS_COLOR) {
	gizmos_renderer_add_box_3d(&ENGINE.gizmos_renderer, center, size, color)
}
draw_gizmos_sphere :: proc(center: Vec3, radius: f32, color := GIZMOS_COLOR) {
	gizmos_renderer_add_sphere(&ENGINE.gizmos_renderer, center, radius, color)
}
draw_gizmos_line :: proc(from: Vec3, to: Vec3, color := GIZMOS_COLOR) {
	gizmos_renderer_add_line_3d(&ENGINE.gizmos_renderer, from, to, color, .WORLD_SPACE)
}
draw_gizmos_circle_xy :: proc(
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
		.WORLD_XY,
	)
}
draw_gizmos_circle_xz :: proc(
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
		.WORLD_XZ,
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
add_sphere_collider :: proc(metadata: ColliderMetadata, center: Vec3, radius: f32) {
	append(&SCENE.colliders, Collider{shape = Sphere{center, radius}, metadata = metadata})
}
add_quad_collider :: proc(quad: Quad, metadata: ColliderMetadata) {
	append(&SCENE.colliders, Collider{shape = quad, metadata = metadata})
}
add_triangle_collider :: proc(triangle: Triangle, metadata: ColliderMetadata) {
	append(&SCENE.colliders, Collider{shape = triangle, metadata = metadata})
}
