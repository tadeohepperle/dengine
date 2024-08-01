package dengine

import "core:image"
import "core:math"
// This module contains some global state and exposes functions making it easy to interact with it.
// Mostly wrappers around functions targeting engine and scene.

ENGINE: Engine
SCENE: Scene

init :: proc(settings: EngineSettings = DEFAULT_ENGINE_SETTINGS) {
	engine_create(&ENGINE, settings)
	scene_create(&SCENE)
}

mouse_btn :: proc(btn: MouseButton = .Left) -> PressFlags {
	return ENGINE.input.mouse_buttons[btn]
}

just_left_pressed :: proc() -> bool {
	return .JustPressed in ENGINE.input.mouse_buttons[.Left]
}

just_left_released :: proc() -> bool {
	return .JustReleased in ENGINE.input.mouse_buttons[.Left]
}

deinit :: proc() {
	scene_destroy(&SCENE)
	engine_destroy(&ENGINE)
}

key_pressed :: #force_inline proc(key: Key) -> bool {
	return .Pressed in ENGINE.input.keys[key]
}

shift_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.input.keys[.LEFT_SHIFT]
}

ctrl_pressed :: #force_inline proc() -> bool {
	return .Pressed in ENGINE.input.keys[.LEFT_CONTROL]
}

hit_pos :: #force_inline proc() -> Vec2 {
	return ENGINE.hit_pos
}

frame :: proc() -> bool {
	@(static)
	LOOP_INITIALIZED := false

	if LOOP_INITIALIZED {
		engine_end_frame(&ENGINE, &SCENE)
	} else {
		LOOP_INITIALIZED = true
	}
	return engine_start_frame(&ENGINE, &SCENE)
}

load_texture_as_tile :: proc(
	path: string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	tile: TextureTile,
	error: image.Error,
) {
	texture := new(Texture)
	texture^, error = texture_from_image_path(ENGINE.device, ENGINE.queue, path, settings)
	if error != nil {
		return
	}

	tile = TextureTile {
		texture = texture,
		uv      = {{0, 0}, {1, 1}},
	}
	return
}

load_texture :: proc(
	path: string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	texture: Texture,
	error: image.Error,
) {
	return texture_from_image_path(ENGINE.device, ENGINE.queue, path, settings)
}

load_texture_array :: proc(
	paths: []string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	texture: TextureArray,
	error: string,
) {
	return texture_array_from_image_paths(ENGINE.device, ENGINE.queue, paths, settings)
}

draw_sprite :: #force_inline proc(sprite: Sprite) {
	append(&SCENE.sprites, sprite)
}

draw_terrain_mesh :: #force_inline proc(mesh: ^TerrainMesh) {
	append(&SCENE.terrain_meshes, mesh)
}

gizmos_aabb :: proc(aabb: Aabb, color := Color{1, 0, 0, 1}, mode := GizmosMode.WORLD_SPACE_2D) {
	gizmos_renderer_add_aabb(&ENGINE.gizmos_renderer, aabb, color, mode)
}

gizmos_rect :: proc(
	center: Vec2,
	size: Vec2,
	color := Color{1, 0, 0, 1},
	mode := GizmosMode.WORLD_SPACE_2D,
) {
	gizmos_renderer_add_rect(&ENGINE.gizmos_renderer, center, size, color, mode)
}

gizmos_line :: proc(
	from: Vec2,
	to: Vec2,
	color := Color{1, 0, 0, 1},
	mode := GizmosMode.WORLD_SPACE_2D,
) {
	gizmos_renderer_add_line(&ENGINE.gizmos_renderer, from, to, color, mode)
}

gizmos_circle :: proc(
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
color_mesh_write_buffers :: proc(
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

circle_collider :: proc(pos: Vec2, radius: f32, metadata: ColliderMetadata, z: int = 0) {
	append(
		&SCENE.colliders,
		Collider{shape = Circle{pos = pos, radius = radius}, metadata = metadata, z = z},
	)
}

aabb_collider :: proc(aabb: Aabb, metadata: ColliderMetadata, z: int = 0) {
	append(&SCENE.colliders, Collider{shape = aabb, metadata = metadata, z = z})
}

triangle_collider :: proc(a: Vec2, b: Vec2, c: Vec2, metadata: ColliderMetadata, z: int = 0) {
	append(&SCENE.colliders, Collider{shape = Triangle{a, b, c}, metadata = metadata, z = z})
}

rect_collider :: proc(
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
