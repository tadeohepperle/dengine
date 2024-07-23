package dengine


Scene :: struct {
	camera:           Camera,
	sprites:          [dynamic]Sprite,
	terrain_meshes:   [dynamic]^TerrainMesh,
	terrain_textures: ^TextureArray,
}

scene_create :: proc(scene: ^Scene) {
	scene.camera = Camera {
		pos      = {0, 0},
		y_height = 10,
	}
}

scene_destroy :: proc(scene: ^Scene) {
	delete(scene.sprites)
	free(scene)
}

scene_clear :: proc(scene: ^Scene) {
	clear(&scene.sprites)
	clear(&scene.terrain_meshes)
}
