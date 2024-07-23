package dengine


Scene :: struct {
	camera:  Camera,
	sprites: [dynamic]Sprite,
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
}
