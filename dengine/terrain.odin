package dengine

import wgpu "vendor:wgpu"

TerrainVertex :: struct {
	pos:       Vec2, // per vertex
	indices:   UVec3, // per triangle (same for all vertices in each triangle)
	weights:   Vec3, // per vertex
	direction: Vec3, // per vertex (3 dimensions for seamless interpolation at triangles between 3 hexes)
}

// Explanation of TerrainVertex.directions:
// We can assign a 3-dimensional direction to each vertex in the hex grid:
// now point A can have direction (1,0,0) because pointing into the triangle is x direction.
// point B would have direction (0,-1,0) because it is pointing in the opposite of y direction.
//                                                             
//                 -\------------ B-                              --       
//               -/  -\         -/  -\                          -/  -\     
//             -/      -\     -/      -\                      -/      -\   
//           -/          -  -/          -\                  -/          -\ 
//          /            /--\             --\            --/            ---
//        -/           /-    -\         ^    -\        -/    ^        -/   
//      -/           /-        --\       \     -\    -/     /      --/     
//    -/           /-             -\      Z      -A/      Y     -/        
//  -/           /-                 -\           /-           --/          
// /--         /-                     --\      /-  \       --/             
//    \-     /-                          -\  /-     \-   -/                
//      \- --                              -----------\-/                  
//         |                                |        |                     
//         |                                |    X   |                     
//         |                                |    |   |                     
//         |                                |    V   |                     
//         |                                |        |                     
//         |                                |        |                     
//         |                                |        |                     
//         -\                             ------------                     
//           -\                         -/                                 
//             --\                   --/                                   
//                -\              --/                                      
//                  --\         -/                                         
//                     -\    --/                                           
//                       ---/                                              
// 

TerrainMesh :: struct {
	vertices:      [dynamic]TerrainVertex,
	vertex_buffer: DynamicBuffer(TerrainVertex),
}

terrain_mesh_create :: proc(
	vertices: [dynamic]TerrainVertex,
	device: wgpu.Device,
	queue: wgpu.Queue,
) -> (
	mesh: TerrainMesh,
) {
	mesh.vertices = vertices
	mesh.vertex_buffer.usage = {.Vertex}
	dynamic_buffer_write(&mesh.vertex_buffer, vertices[:], device, queue)
	return mesh
}

terrain_mesh_destroy :: proc(terrain_mesh: ^TerrainMesh) {
	delete(terrain_mesh.vertices)
	dynamic_buffer_destroy(&terrain_mesh.vertex_buffer)
}

TerrainRenderer :: struct {
	device:   wgpu.Device,
	queue:    wgpu.Queue,
	pipeline: RenderPipeline,
}

terrain_renderer_create :: proc(
	rend: ^TerrainRenderer,
	device: wgpu.Device,
	queue: wgpu.Queue,
	reg: ^ShaderRegistry,
	globals_layout: wgpu.BindGroupLayout,
) {
	rend.device = device
	rend.queue = queue
	rend.pipeline.config = terrain_pipeline_config(
		device,
		globals_layout,
		rgba_texture_array_bind_group_layout_cached(device),
	)
	render_pipeline_create_panic(&rend.pipeline, device, reg)
}

terrain_renderer_destroy :: proc(rend: ^TerrainRenderer) {
	render_pipeline_destroy(&rend.pipeline)
}

terrain_renderer_render :: proc(
	rend: ^TerrainRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
	meshes: []^TerrainMesh,
	texture_array: ^TextureArray,
) {
	if len(meshes) == 0 || texture_array == nil {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, texture_array.bind_group)
	for mesh in meshes {
		wgpu.RenderPassEncoderSetVertexBuffer(
			render_pass,
			0,
			mesh.vertex_buffer.buffer,
			0,
			mesh.vertex_buffer.size,
		)
		wgpu.RenderPassEncoderDraw(render_pass, u32(mesh.vertex_buffer.length), 1, 0, 0)
	}
}

terrain_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
	terrain_textures_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "terrain",
		vs_shader = "terrain",
		vs_entry_point = "vs_main",
		fs_shader = "terrain",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {
			ty_id = TerrainVertex,
			attributes = {
				{format = .Float32x2, offset = offset_of(TerrainVertex, pos)},
				{format = .Uint32x3, offset = offset_of(TerrainVertex, indices)},
				{format = .Float32x3, offset = offset_of(TerrainVertex, weights)},
				{format = .Float32x3, offset = offset_of(TerrainVertex, direction)},
			},
		},
		instance = {},
		bind_group_layouts = {globals_layout, terrain_textures_layout},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
	}
}


terrain_textures_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static)layout: wgpu.BindGroupLayout
	if layout == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2DArray,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering},
			},
		}
		layout = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor {
				entryCount = uint(len(entries)),
				entries = &entries[0],
			},
		)
	}
	return layout
}
