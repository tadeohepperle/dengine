package dengine

import "core:math"
import "core:math/linalg"


ColliderMetadata :: [24]u8
NO_COLLIDER: ColliderMetadata = {}

Collider :: struct {
	metadata: ColliderMetadata,
	shape:    ColliderShape,
}

ColliderShape :: union {
	Sphere,
	Triangle,
	Quad,
}

// collider_roughly_in_aabb :: proc "contextless" (collider: ColliderShape, aabb: Aabb) -> bool {
// 	return false
// 	// todo()
// 	// switch c in collider {
// 	// case Circle:
// 	// 	return aabb_contains(aabb, c.pos)
// 	// case Aabb:
// 	// 	return aabb_intersects(aabb, c)
// 	// case Triangle:
// 	// 	center := (c.a + c.b + c.c) / 3
// 	// 	return aabb_contains(aabb, center)
// 	// case RotatedRect:
// 	// 	return aabb_contains(aabb, c.center)
// 	// }
// 	// return false
// }

ray_intersects_xy_plane :: proc "contextless" (
	ray: Ray,
) -> (
	dist: f32,
	hit_point_xy: Vec2,
	hit: bool,
) {
	if ray.direction.z == 0 {
		// Ray is parallel to the plane
		return {}, {}, false
	}
	dist = -ray.origin.z / ray.direction.z
	if dist < 0 {
		// Intersection is behind the ray origin
		return {}, {}, false
	}
	hit_point_xy = Vec2 {
		ray.origin.x + dist * ray.direction.x,
		ray.origin.y + dist * ray.direction.y,
	}
	return dist, hit_point_xy, true
}


ray_intersects_xz_plane :: proc "contextless" (
	ray: Ray,
) -> (
	dist: f32,
	hit_point_xz: Vec2,
	hit: bool,
) {
	if ray.direction.y == 0 {
		// Ray is parallel to the plane
		return {}, {}, false
	}
	dist = -ray.origin.y / ray.direction.y
	if dist < 0 {
		// Intersection is behind the ray origin
		return {}, {}, false
	}
	hit_point_xz = Vec2 {
		ray.origin.x + dist * ray.direction.x,
		ray.origin.z + dist * ray.direction.z,
	}
	return dist, hit_point_xz, true
}


ray_intersects_shape :: proc "contextless" (
	ray: Ray,
	shape: ColliderShape,
) -> (
	dist: f32,
	hit: bool,
) {
	switch s in shape {
	case Sphere:
		return ray_intersects_sphere(ray, s.center, s.radius)
	case Triangle:
		return ray_intersects_triangle(ray, s.a, s.b, s.c)
	case Quad:
		dist, hit = ray_intersects_triangle(ray, s.a, s.b, s.c)
		if !hit {
			dist, hit = ray_intersects_triangle(ray, s.a, s.c, s.d)
		}
		return dist, hit
	}
	return
}


Triangle :: struct {
	a: Vec3,
	b: Vec3,
	c: Vec3,
}

Quad :: struct {
	a: Vec3,
	b: Vec3,
	c: Vec3,
	d: Vec3,
}

Sphere :: struct {
	center: Vec3,
	radius: f32,
}

point_in_triangle :: #force_inline proc "contextless" (
	pt: Vec2,
	a: Vec2,
	b: Vec2,
	c: Vec2,
) -> bool {
	sign :: #force_inline proc "contextless" (p1: Vec2, p2: Vec2, p3: Vec2) -> f32 {
		return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
	}
	d1 := sign(pt, a, b)
	d2 := sign(pt, b, c)
	d3 := sign(pt, c, a)

	has_neg := (d1 < 0.0) || (d2 < 0.0) || (d3 < 0.0)
	has_pos := (d1 > 0.0) || (d2 > 0.0) || (d3 > 0.0)

	return !(has_neg && has_pos)
}


NOT_HIT_DIST :: max(f32)

// moller_trumbore_intersection 
// reference: https://en.wikipedia.org/wiki/M%C3%B6ller%E2%80%93Trumbore_intersection_algorithm#:~:text=The%20M%C3%B6ller%E2%80%93Trumbore%20ray%2Dtriangle,the%20plane%20containing%20the%20triangle.
// 
// returns: dist, is_hit
//        A
// 
// 
// 
//  B            C
// 
ray_intersects_triangle :: proc "contextless" (
	ray: Ray,
	a: Vec3,
	b: Vec3,
	c: Vec3,
) -> (
	f32,
	bool,
) {
	e1 := b - a
	e2 := c - a
	ray_cross_e2 := cross(ray.direction, e2)
	det := dot(e1, ray_cross_e2)
	if det < math.F32_EPSILON {
		return {}, false // This ray is parallel to this triangle or behind ray
	}
	inv_det := 1.0 / det
	s := ray.origin - a
	u := inv_det * dot(s, ray_cross_e2)
	if u < 0.0 || u > 1.0 {
		return {}, false
	}
	s_cross_e1 := cross(s, e1)
	v := inv_det * dot(ray.direction, s_cross_e1)
	if v < 0.0 || u + v > 1.0 {
		return {}, false
	}
	// At this stage we can compute t to find out where the intersection point is on the line.
	t := inv_det * dot(e2, s_cross_e1)
	if t < math.F32_EPSILON {
		// This means that there is a line intersection but not a ray intersection.
		return {}, false
	}
	return t, true
}


// reference: https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection.html
ray_intersects_sphere :: proc "contextless" (ray: Ray, center: Vec3, radius: f32) -> (f32, bool) {
	t0, t1: f32 // solutions for t if the ray intersects
	l: Vec3 = center - ray.origin
	tca: f32 = dot(l, ray.direction)
	// if (tca < 0) return false;
	d2: f32 = dot(l, l) - tca * tca
	if d2 > radius * radius {
		return {}, false
	}
	thc: f32 = sqrt(radius * radius - d2)
	t0 = tca - thc
	t1 = tca + thc

	if t0 > t1 {
		t1, t0 = t0, t1
	}

	if t0 < 0 {
		t0 = t1 // If t0 is negative, let's use t1 instead.
		if t0 < 0 {
			return {}, false // Both t0 and t1 are negative.
		}
	}
	return t0, true
}


// collider_overlaps_point :: proc "contextless" (collider: ^ColliderShape, pt: Vec2) -> bool {
// 	switch c in collider {
// 	case Circle:
// 		return linalg.length2(c.pos - pt) < c.radius * c.radius
// 	case Aabb:
// 		return pt.x >= c.min.x && pt.x <= c.max.x && pt.y >= c.min.y && pt.y <= c.max.y
// 	case Triangle:
// 		return point_in_triangle(pt, c.a, c.b, c.c)
// 	case RotatedRect:
// 		if linalg.length2(c.center - pt) > c.radius_sq {
// 			return false
// 		}
// 		return point_in_triangle(pt, c.a, c.b, c.c) || point_in_triangle(pt, c.a, c.c, c.d)
// 	}
// 	return false
// }
