package dengine


Scene :: struct {
	camera:               Camera,
	sprites:              [dynamic]Sprite,
	terrain_meshes:       [dynamic]^TerrainMesh,
	terrain_textures:     TextureArrayHandle,
	colliders:            [dynamic]Collider,
	last_frame_colliders: [dynamic]Collider,
}

scene_create :: proc(scene: ^Scene) {
	scene.camera = DEFAULT_CAMERA
}

scene_destroy :: proc(scene: ^Scene) {
	delete(scene.sprites)
}

scene_clear :: proc(scene: ^Scene) {
	clear(&scene.sprites)
	clear(&scene.terrain_meshes)
	scene.last_frame_colliders, scene.colliders = scene.colliders, scene.last_frame_colliders
	clear(&scene.colliders)
}
