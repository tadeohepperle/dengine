package dengine

import "base:runtime"
import "core:fmt"
import "core:strings"
import wgpu "vendor:wgpu"

Aabb :: struct {
	min: Vec2,
	max: Vec2,
}

// ensures that both x and y of the max are >= than the min
aabb_standard_form :: proc "contextless" (aabb: Aabb) -> Aabb {
	r := aabb
	if r.max.x < r.min.x {
		r.min.x, r.max.x = r.max.x, r.min.x
	}
	if r.max.y < r.min.y {
		r.min.y, r.max.y = r.max.y, r.min.y
	}
	return r
}

aabb_contains :: proc "contextless" (aabb: Aabb, pt: Vec2) -> bool {
	return pt.x >= aabb.min.x && pt.y >= aabb.min.y && pt.x <= aabb.max.x && pt.y <= aabb.max.y
}

aabb_intersects :: proc "contextless" (a: Aabb, b: Aabb) -> bool {
	return(
		min(a.max.x, b.max.x) >= max(a.min.x, b.min.x) &&
		min(a.max.y, b.max.y) >= max(a.min.y, b.min.y) \
	)
}


Camera :: struct {
	pos:      Vec2,
	y_height: f32,
}

DVec2 :: [2]f64
Vec2 :: [2]f32
Vec3 :: [3]f32
UVec2 :: [2]u32
UVec3 :: [3]u32
IVec2 :: [2]i32

next_pow2_number :: proc(n: int) -> int {
	next: int = 2
	for {
		if next >= n {
			return next
		}
		next *= 2
	}
}
lerp :: proc(a: $T, b: T, s: f32) -> T {
	return a + (b - a) * s
}

Empty :: struct {}

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


lorem :: proc(letters := 300) -> string {
	LOREM := "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet.   "
	letters := min(letters, len(LOREM))
	return LOREM[0:letters]
}
