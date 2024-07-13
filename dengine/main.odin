package dengine

import "core:fmt"
import "core:math"
import "core:strings"

import wgpu "vendor:wgpu"

print :: fmt.println
print_line :: proc(message: string = "") {
	if message != "" {
		fmt.printfln(
			"-------------------- %s ---------------------------------------------",
			message,
		)
	} else {
		fmt.println("------------------------------------------------------------------------")
	}

}

main :: proc() {
	engine: Engine
	engine_create(&engine, EngineSettings{title = "Hello", size = {800, 600}})
	defer {engine_destroy(&engine)}
	scene := scene_create()
	defer {scene_destroy(scene)}


	corn_tex, _ := texture_from_image_path(engine.device, engine.queue, path = "corn.png")
	corn := TextureTile {
		texture = &corn_tex,
		uv      = {{0, 0}, {1, 1}},
	}
	sprite_tex, err := texture_from_image_path(engine.device, engine.queue, path = "sprite.png")
	sprite := TextureTile {
		texture = &sprite_tex,
		uv      = {{0, 0}, {1, 1}},
	}
	if err != nil {
		print(err)
		panic("c")
	}


	player_pos := Vec2{0, 0}
	forest := [?]Vec2{{0, 0}, {2, 0}, {3, 0}, {5, 2}, {6, 3}}

	for engine_start_frame(&engine) {
		append(
			&scene.sprites,
			Sprite {
				texture = sprite,
				pos = player_pos,
				size = {1, 1},
				rotation = 0,
				color = Color_White,
			},
		)

		for pos, i in forest {
			append(
				&scene.sprites,
				Sprite {
					texture = corn,
					pos = pos,
					size = {1, 2},
					rotation = math.cos(f32(i) + f32(engine.total_time)),
					color = Color_White,
				},
			)
		}

		// append(
		// 	&scene.sprites,
		// 	Sprite{texture = corn, pos = {0, 0}, size = {1, 1}, rotation = 0, color = Color_Aqua},
		// )


		keys := [?]Key{.LEFT, .RIGHT, .UP, .DOWN}
		directions := [?]Vec2{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

		for k, i in keys {
			if engine.input.keys[k] == .Pressed {
				player_pos += directions[i] * 20 * f32(engine.delta_time)
			}
		}

		engine_end_frame(&engine, scene)
	}

}
