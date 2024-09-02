package example2

import "../dengine"
import "core:fmt"


Vec2 :: [2]f32
Color :: [4]f32

main :: proc() {
	dengine.init()
	// defer {dengine.deinit()}


	// for dengine.frame() {
	// 	dengine.start_window("Example Window")
	// 	dengine.button("Hello!", id = "nonowowowowowpowd")
	// }

}
