package dengine

import "core:math"
import wgpu "vendor:wgpu"

GizmosVertex :: struct {
	pos:   Vec3,
	color: Color,
}

GizmosRenderer :: struct {
	device:         wgpu.Device,
	queue:          wgpu.Queue,
	pipeline:       RenderPipeline,
	vertices:       [GizmosSpace][dynamic]GizmosVertex,
	vertex_buffers: [GizmosSpace]DynamicBuffer(GizmosVertex),
}

GizmosSpace :: enum u32 {
	WORLD_SPACE     = 0, // 
	UI_LAYOUT_SPACE = 1, // x scaled, such that y is always 1080.
}

GIZMOS_COLOR := Color{1, 0, 0, 1}

gizmos_renderer_create :: proc(rend: ^GizmosRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue
	for mode in GizmosSpace {
		rend.vertex_buffers[mode].usage = {.Vertex}
	}
	rend.pipeline.config = gizmos_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.pipeline, &platform.shader_registry)
}
gizmos_renderer_destroy :: proc(rend: ^GizmosRenderer) {
	for mode in GizmosSpace {
		delete(rend.vertices[mode])
		dynamic_buffer_destroy(&rend.vertex_buffers[mode])
	}
	render_pipeline_destroy(&rend.pipeline)
}
gizmos_renderer_prepare :: proc(rend: ^GizmosRenderer, sprites: []Sprite) {
	for mode in GizmosSpace {
		dynamic_buffer_write(
			&rend.vertex_buffers[mode],
			rend.vertices[mode][:],
			rend.device,
			rend.queue,
		)
		clear(&rend.vertices[mode])
	}
}
gizmos_renderer_render :: proc(
	rend: ^GizmosRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	mode: GizmosSpace,
) {
	vertex_buffer := &rend.vertex_buffers[mode]
	if vertex_buffer.length == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		vertex_buffer.buffer,
		0,
		vertex_buffer.size,
	)
	mode := mode
	wgpu.RenderPassEncoderSetPushConstants(render_pass, {.Vertex}, 0, size_of(GizmosSpace), &mode)
	wgpu.RenderPassEncoderDraw(render_pass, u32(vertex_buffer.length), 1, 0, 0)
}
gizmos_renderer_render_all_modes :: proc(
	rend: ^GizmosRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
) {
	bound_pipeline_and_bind_group := false
	for mode in GizmosSpace {
		mode := mode
		vertex_buffer := &rend.vertex_buffers[mode]
		if vertex_buffer.length == 0 {
			continue
		}
		if !bound_pipeline_and_bind_group {
			bound_pipeline_and_bind_group = true
			wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
		}
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass,
			0,
			vertex_buffer.buffer,
			0,
			vertex_buffer.size,
		)
		wgpu.RenderPassEncoderSetPushConstants(
			render_pass,
			{.Vertex},
			0,
			size_of(GizmosSpace),
			&mode,
		)
		wgpu.RenderPassEncoderDraw(render_pass, u32(vertex_buffer.length), 1, 0, 0)
	}
}

// todo: add .WORLD_SPACE / UI option
gizmos_renderer_add_circle :: #force_inline proc(
	rend: ^GizmosRenderer,
	center: Vec2,
	radius: f32,
	color := GIZMOS_COLOR,
	segments: int = 12,
	draw_inner_lines: bool = false,
	mode: Gizmos2dMode = {},
) {
	last_p: Vec2 = center + Vec2{radius, 0}
	for i in 1 ..= segments {
		angle := f32(i) / f32(segments) * math.PI * 2.0
		p := center + Vec2{math.cos(angle), math.sin(angle)} * radius
		gizmos_renderer_add_line_2d(rend, last_p, p, color, mode)
		if draw_inner_lines {
			gizmos_renderer_add_line_2d(rend, center, p, color, mode)
		}
		last_p = p
	}
}


// how a Vec2 should be mapped into a Vec3 when drawing 3d shapes
Gizmos2dMode :: enum {
	WORLD_XZ,
	WORLD_XY,
	UI,
}

gizmos_renderer_add_line_2d :: #force_inline proc(
	rend: ^GizmosRenderer,
	from: Vec2,
	to: Vec2,
	color := GIZMOS_COLOR,
	mode: Gizmos2dMode = {},
) {
	from_3d, to_3d: Vec3 = ---, ---
	space: GizmosSpace = ---
	switch mode {
	case .UI:
		space = .UI_LAYOUT_SPACE
		from_3d, to_3d = Vec3{from.x, from.y, 0}, Vec3{to.x, to.y, 0}
	case .WORLD_XY:
		space = .WORLD_SPACE
		from_3d, to_3d = Vec3{from.x, from.y, 0}, Vec3{to.x, to.y, 0}
	case .WORLD_XZ:
		space = .WORLD_SPACE
		from_3d, to_3d = Vec3{from.x, 0, from.y}, Vec3{to.x, 0, to.y}
	}
	gizmos_renderer_add_line_3d(rend, from_3d, to_3d, color, space)
}

gizmos_renderer_add_sphere :: proc(
	rend: ^GizmosRenderer,
	center: Vec3,
	radius: f32,
	color := GIZMOS_COLOR,
) {
	pts, indices := __get_sphere_points_and_indices()
	vertices := &rend.vertices[.WORLD_SPACE]
	for idx in indices {
		pos := pts[idx] * radius + center
		append(vertices, GizmosVertex{pos, color})
	}
}

__get_sphere_points_and_indices :: proc() -> (pts: []Vec3, indices: []u32) {
	@(thread_local)
	SPHERE_POINTS: [dynamic]Vec3
	@(thread_local)
	SPHERE_INDICES: [dynamic]u32
	if SPHERE_POINTS != nil {
		return SPHERE_POINTS[:], SPHERE_INDICES[:]
	}

	SEGS :: 10
	for i in 1 ..< SEGS {
		pitch_angle := (f32(i) * PI / SEGS) - (PI / 2.0)
		off_y := sin(pitch_angle)
		for j in 0 ..< SEGS {
			rad_rangle := f32(j) * PI * 2.0 / SEGS
			off_x := sin(rad_rangle) * cos(pitch_angle)
			off_z := cos(rad_rangle) * cos(pitch_angle)
			append(&SPHERE_POINTS, Vec3{off_x, off_y, off_z})
		}
	}


	bottom_idx := u32(len(SPHERE_POINTS))
	append(&SPHERE_POINTS, Vec3{0, -1, 0})
	top_idx := u32(len(SPHERE_POINTS))
	append(&SPHERE_POINTS, Vec3{0, 1, 0})
	// add top and bottom triangles:
	for i in 0 ..< u32(SEGS) {
		j: u32 = ---
		if i == 0 {
			j = SEGS - 1
		} else {
			j = i - 1
		}
		append(&SPHERE_INDICES, i, j, bottom_idx)

		for level in 0 ..< u32(SEGS - 2) {
			i := i + level * SEGS
			j := j + level * SEGS
			i_above := i + SEGS
			j_above := j + SEGS
			append(&SPHERE_INDICES, j, i, i_above)
			append(&SPHERE_INDICES, j, i_above, j_above)

		}
		append(&SPHERE_INDICES, j + SEGS * (SEGS - 2), i + SEGS * (SEGS - 2), top_idx)
	}
	return SPHERE_POINTS[:], SPHERE_INDICES[:]
}

gizmos_renderer_add_line_3d :: #force_inline proc(
	rend: ^GizmosRenderer,
	from: Vec3,
	to: Vec3,
	color := GIZMOS_COLOR,
	space := GizmosSpace.WORLD_SPACE,
) {
	append(&rend.vertices[space], GizmosVertex{pos = from, color = color})
	append(&rend.vertices[space], GizmosVertex{pos = to, color = color})
}

gizmos_renderer_add_box_3d :: #force_inline proc(
	rend: ^GizmosRenderer,
	center: Vec3,
	size: Vec3,
	color := GIZMOS_COLOR,
) {
	todo()
}

gizmos_renderer_add_aabb :: proc(
	rend: ^GizmosRenderer,
	using aabb: Aabb,
	color := GIZMOS_COLOR,
	mode: Gizmos2dMode = {},
) {
	a := min
	b := Vec2{min.x, max.y}
	c := max
	d := Vec2{max.x, min.y}
	gizmos_renderer_add_line_2d(rend, a, b, color, mode)
	gizmos_renderer_add_line_2d(rend, b, c, color, mode)
	gizmos_renderer_add_line_2d(rend, c, d, color, mode)
	gizmos_renderer_add_line_2d(rend, d, a, color, mode)
}


gizmos_renderer_add_rect :: proc(
	rend: ^GizmosRenderer,
	center: Vec2,
	size: Vec2,
	color := GIZMOS_COLOR,
	mode: Gizmos2dMode = {},
) {
	h := size / 2
	a := center + Vec2{-h.x, h.y}
	b := center + Vec2{h.x, h.y}
	c := center + Vec2{h.x, -h.y}
	d := center + Vec2{-h.x, -h.y}
	gizmos_renderer_add_line_2d(rend, a, b, color, mode)
	gizmos_renderer_add_line_2d(rend, b, c, color, mode)
	gizmos_renderer_add_line_2d(rend, c, d, color, mode)
	gizmos_renderer_add_line_2d(rend, d, a, color, mode)
}


gizmos_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "gizmos",
		vs_shader = "gizmos",
		vs_entry_point = "vs_main",
		fs_shader = "gizmos",
		fs_entry_point = "fs_main",
		topology = .LineList,
		vertex = {
			ty_id = GizmosVertex,
			attributes = {
				{format = .Float32x3, offset = offset_of(GizmosVertex, pos)},
				{format = .Float32x4, offset = offset_of(GizmosVertex, color)},
			},
		},
		instance = {},
		bind_group_layouts = {globals_layout},
		push_constant_ranges = {
			wgpu.PushConstantRange{stages = {.Vertex}, start = 0, end = size_of(GizmosSpace)},
		},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
	}
}
