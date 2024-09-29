package dengine

import "core:math"
import "core:math/linalg"

Camera :: struct {
	eye_pos:    Vec3,
	focus_pos:  Vec3,
	z_near:     f32,
	z_far:      f32,
	fov_y:      f32, // only relevant for perspective
	height_y:   f32, // only relevant for orthographic
	projection: Projection,
}
DEFAULT_CAMERA :: Camera {
	focus_pos  = Vec3{0, 0, 0},
	eye_pos    = Vec3{0, 0, -20},
	z_far      = 100.0,
	z_near     = 1.0,
	projection = .Perspective,
	fov_y      = 1.4,
	height_y   = 30.0,
}
CameraRaw :: struct {
	view_proj: Mat4,
	view:      Mat4,
	proj:      Mat4,
	eye_pos:   Vec4,
}

Projection :: enum {
	Orthographic,
	Perspective,
}
camera_lerp :: proc(a: Camera, b: Camera, s: f32) -> Camera {
	res := b
	res.eye_pos = lerp(a.eye_pos, b.eye_pos, s)
	res.focus_pos = lerp(a.focus_pos, b.focus_pos, s)
	res.fov_y = lerp(a.fov_y, b.fov_y, s)
	res.height_y = lerp(a.height_y, b.height_y, s)
	return res
}
camera_direction :: proc "contextless" (self: Camera) -> Vec3 {
	return linalg.normalize(self.focus_pos - self.eye_pos)
}

camera_ray :: proc "contextless" (self: Camera) -> Ray {
	return Ray{self.eye_pos, camera_direction(self)}
}
camera_to_raw :: proc "contextless" (self: Camera, screen_size: Vec2) -> (raw: CameraRaw) {

	// linalg.matrix4_from_yaw_pitch_roll()
	view := matrix4_look_at_f32_left_handed(self.eye_pos, self.focus_pos) //   _look_to_rh(self.pos, camera_direction(self))
	aspect := screen_size.x / screen_size.y
	proj: Mat4
	switch self.projection {
	case .Orthographic:
		top := self.height_y * 0.5
		bottom := -top
		right := aspect * top
		left := -right
		proj = linalg.matrix_ortho3d_f32(left, right, bottom, top, self.z_near, self.z_far)
	case .Perspective:
		proj = linalg.matrix4_perspective_f32(self.fov_y, aspect, self.z_near, self.z_far)
	}
	raw.view_proj = proj * view
	raw.proj = proj
	raw.view = view
	raw.eye_pos = Vec4{self.eye_pos.x, self.eye_pos.y, self.eye_pos.z, 1.0}
	return raw
}

camera_ray_from_screen_pos :: proc(
	camera_raw: CameraRaw,
	screen_pos: Vec2,
	screen_size: Vec2,
) -> Ray {
	screen_pos := screen_pos
	screen_pos.y = screen_size.y - screen_pos.y

	ndc := screen_pos * 2.0 / screen_size - Vec2{1, 1}
	ndc_to_world :=
		linalg.matrix4x4_inverse(camera_raw.view) * linalg.matrix4x4_inverse(camera_raw.proj)
	world_far_plane_pt: Vec3 = project_point3(ndc_to_world, Vec3{ndc.x, ndc.y, 1.0})
	world_near_plane_pt: Vec3 = project_point3(ndc_to_world, Vec3{ndc.x, ndc.y, math.F32_EPSILON})
	direction := normalize(world_far_plane_pt - world_near_plane_pt)
	return Ray{world_near_plane_pt, direction}
}


project_point3 :: #force_inline proc(mat: Mat4, pt: Vec3) -> Vec3 {
	pt_4 := Vec4{pt.x, pt.y, pt.z, 1.0}
	res := mat * pt_4
	return res.xyz / res.w
}


normalize :: linalg.normalize
cross :: linalg.cross
sin :: math.sin
cos :: math.cos
PI :: math.PI
dot :: linalg.dot
sqrt :: math.sqrt

matrix4_look_at_f32_left_handed :: proc "contextless" (eye, focus_pos: Vec3) -> (m: Mat4) {
	up: Vec3 = Vec3{0, 1, 0}
	f := normalize(focus_pos - eye)
	s := normalize(cross(up, f))
	u := cross(f, s)

	return matrix[4, 4]f32{
		+s.x, +s.y, +s.z, -dot(s, eye), 
		+u.x, +u.y, +u.z, -dot(u, eye), 
		-f.x, -f.y, -f.z, dot(f, eye), 
		0, 0, 0, 1, 
	}
}
