package dengine

import "core:image"
// This module contains some global state and exposes functions making it easy to interact with it.
// Mostly wrappers around functions targeting engine and scene.

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


key_pressed :: #force_inline proc(key: Key) -> bool {
	return .Pressed in ENGINE.input.keys[key]
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
