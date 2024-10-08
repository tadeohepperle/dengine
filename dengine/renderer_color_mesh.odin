package dengine
import wgpu "vendor:wgpu"

ColorMeshVertex :: struct {
	pos:   Vec3,
	color: Color,
}

ColorMeshRenderer :: struct {
	device:        wgpu.Device,
	queue:         wgpu.Queue,
	pipeline:      RenderPipeline,
	vertices:      [dynamic]ColorMeshVertex,
	vertex_buffer: DynamicBuffer(ColorMeshVertex),
	indices:       [dynamic]u32,
	index_buffer:  DynamicBuffer(u32),
}

color_mesh_renderer_create :: proc(rend: ^ColorMeshRenderer, platform: ^Platform) {
	rend.device = platform.device
	rend.queue = platform.queue
	rend.vertex_buffer.usage = {.Vertex}
	rend.index_buffer.usage = {.Index}
	rend.pipeline.config = color_mesh_pipeline_config(
		platform.device,
		platform.globals.bind_group_layout,
	)
	render_pipeline_create_panic(&rend.pipeline, &platform.shader_registry)
}

color_mesh_renderer_destroy :: proc(rend: ^ColorMeshRenderer) {
	delete(rend.vertices)
	delete(rend.indices)
	dynamic_buffer_destroy(&rend.vertex_buffer)
	dynamic_buffer_destroy(&rend.index_buffer)
	render_pipeline_destroy(&rend.pipeline)
}

color_mesh_renderer_prepare :: proc(rend: ^ColorMeshRenderer) {
	dynamic_buffer_write(&rend.vertex_buffer, rend.vertices[:], rend.device, rend.queue)
	dynamic_buffer_write(&rend.index_buffer, rend.indices[:], rend.device, rend.queue)
	clear(&rend.vertices)
	clear(&rend.indices)
}

color_mesh_renderer_render :: proc(
	rend: ^ColorMeshRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
) {

	if rend.index_buffer.length == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)

	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		rend.vertex_buffer.buffer,
		0,
		rend.vertex_buffer.size,
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		render_pass,
		rend.index_buffer.buffer,
		.Uint32,
		0,
		rend.index_buffer.size,
	)
	wgpu.RenderPassEncoderDrawIndexed(render_pass, u32(rend.index_buffer.length), 1, 0, 0, 0)
}

color_mesh_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "color_mesh",
		vs_shader = "color_mesh",
		vs_entry_point = "vs_main",
		fs_shader = "color_mesh",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = ColorMeshVertex,
			attributes = {
				{format = .Float32x3, offset = offset_of(ColorMeshVertex, pos)},
				{format = .Float32x4, offset = offset_of(ColorMeshVertex, color)},
			},
		},
		instance = {},
		bind_group_layouts = {globals_layout},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
	}
}

color_mesh_add :: proc {
	color_mesh_add_vertices_single_color,
	color_mesh_add_vertices,
	color_mesh_add_indexed_single_color,
	color_mesh_add_indexed,
}


color_mesh_add_vertices_single_color :: proc(
	rend: ^ColorMeshRenderer,
	positions: []Vec3,
	color := Color_Red,
) {
	v_count_before := u32(len(rend.vertices))

	for pos, i in positions {
		append(&rend.vertices, ColorMeshVertex{pos = pos, color = color})
		append(&rend.indices, v_count_before + u32(i))
	}
}


color_mesh_add_vertices :: proc(rend: ^ColorMeshRenderer, vertices: []ColorMeshVertex) {
	v_count_before := u32(len(rend.vertices))
	append(&rend.vertices, ..vertices)
	for i in 0 ..< len(vertices) {
		append(&rend.indices, v_count_before + u32(i))
	}
}

color_mesh_add_indexed :: proc(
	rend: ^ColorMeshRenderer,
	vertices: []ColorMeshVertex,
	indices: []u32,
) {
	v_count_before := u32(len(rend.vertices))
	append(&rend.vertices, ..vertices)
	for i in indices {
		append(&rend.indices, v_count_before + i)
	}
}

color_mesh_add_indexed_single_color :: proc(
	rend: ^ColorMeshRenderer,
	positions: []Vec3,
	indices: []u32,
	color := Color_Red,
) {
	v_count_before := u32(len(rend.vertices))
	for pos in positions {
		append(&rend.vertices, ColorMeshVertex{pos = pos, color = color})
	}
	for i in indices {
		append(&rend.indices, v_count_before + i)
	}
}
