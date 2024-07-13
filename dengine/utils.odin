package dengine

import "base:runtime"
import "core:strings"
import wgpu "vendor:wgpu"

Aabb :: struct {
	min: Vec2,
	max: Vec2,
}

Camera :: struct {
	pos:      Vec2,
	y_height: f32,
}

DVec2 :: [2]f64
Vec2 :: [2]f32
UVec2 :: [2]u32
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
