package dengine

import "core:fmt"
import "core:slice"
import wgpu "vendor:wgpu"


SpriteZ :: enum {
	Background,
	DecoArea,
	PathIndicator,
	Path,
	NodeIndicator,
	Node,
	Default,
	BehindCharacter,
	CharacterIndicator,
	Character,
	CharacterUi,
	ItemOrBagOnMapIndicator,
	ItemOrBagOnMap,
	NpcDice,
	PlayerTakenDice,
	ItemInBagIndicator,
	ItemInBag,
	PlayerOpenDice,
	DescriptionCard,
	PossibleAction,
	BehindVeryTop,
	VeryTop,
}

Sprite :: struct {
	z:        SpriteZ,
	texture:  TextureTile,
	pos:      Vec2,
	size:     Vec2,
	rotation: f32,
	color:    Color,
}

SpriteInstance :: struct {
	pos:      Vec2,
	size:     Vec2,
	rotation: f32,
	color:    Color,
	uv:       Aabb,
}

SpriteBatch :: struct {
	texture:   ^Texture,
	start_idx: int,
	end_idx:   int,
	key:       u64,
}


_sort_and_batch_sprites :: proc(
	sprites: []Sprite,
	batches: ^[dynamic]SpriteBatch,
	instances: ^[dynamic]SpriteInstance,
) {
	clear(batches)
	clear(instances)
	if len(sprites) == 0 {
		return
	}

	slice.sort_by(sprites, proc(a, b: Sprite) -> bool {
		if a.z < b.z {
			return true
		} else if a.z == b.z {
			return a.pos.y > b.pos.y
		} else {
			return false
		}
	})

	append(
		batches,
		SpriteBatch {
			start_idx = 0,
			end_idx = 0,
			texture = sprites[0].texture.texture,
			key = _sprite_batch_key(&sprites[0]),
		},
	)
	for &sprite in sprites {
		last_batch := &batches[len(batches) - 1]
		sprite_key := _sprite_batch_key(&sprite)
		if last_batch.key != sprite_key {
			last_batch.end_idx = len(instances)
			append(
				batches,
				SpriteBatch {
					start_idx = len(instances),
					end_idx = 0,
					texture = sprite.texture.texture,
					key = sprite_key,
				},
			)
		}
		append(
			instances,
			SpriteInstance {
				pos = sprite.pos,
				size = sprite.size,
				color = sprite.color,
				uv = sprite.texture.uv,
				rotation = sprite.rotation,
			},
		)
	}
	batches[len(batches) - 1].end_idx = len(instances)
}

_sprite_batch_key :: #force_inline proc(sprite: ^Sprite) -> u64 {
	return u64(uintptr(sprite.texture.texture))
}

SpriteRenderer :: struct {
	device:          wgpu.Device,
	queue:           wgpu.Queue,
	pipeline:        RenderPipeline,
	batches:         [dynamic]SpriteBatch,
	instances:       [dynamic]SpriteInstance,
	instance_buffer: DynamicBuffer(SpriteInstance),
}

sprite_renderer_prepare :: proc(rend: ^SpriteRenderer, sprites: []Sprite) {
	_sort_and_batch_sprites(sprites, &rend.batches, &rend.instances)
	dynamic_buffer_write(&rend.instance_buffer, rend.instances[:], rend.device, rend.queue)
}

sprite_renderer_render :: proc(
	rend: ^SpriteRenderer,
	render_pass: wgpu.RenderPassEncoder,
	globals_uniform_bind_group: wgpu.BindGroup,
) {

	if len(rend.batches) == 0 {
		return
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, rend.pipeline.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, globals_uniform_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		rend.instance_buffer.buffer,
		0,
		rend.instance_buffer.size,
	)
	for batch in rend.batches {
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, batch.texture.bind_group)
		wgpu.RenderPassEncoderDraw(
			render_pass,
			4,
			u32(batch.end_idx - batch.start_idx),
			0,
			u32(batch.start_idx),
		)
	}
}


sprite_renderer_destroy :: proc(rend: ^SpriteRenderer) {
	delete(rend.batches)
	delete(rend.instances)
	render_pipeline_destroy(&rend.pipeline)
	dynamic_buffer_destroy(&rend.instance_buffer)
}

sprite_renderer_create :: proc(
	rend: ^SpriteRenderer,
	device: wgpu.Device,
	queue: wgpu.Queue,
	reg: ^ShaderRegistry,
	globals_layout: wgpu.BindGroupLayout,
) {
	rend.device = device
	rend.queue = queue
	rend.instance_buffer.usage = {.Vertex}
	rend.pipeline.config = sprite_pipeline_config(device, globals_layout)
	render_pipeline_create_panic(&rend.pipeline, device, reg)
}

sprite_pipeline_config :: proc(
	device: wgpu.Device,
	globals_layout: wgpu.BindGroupLayout,
) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "sprite_standard",
		vs_shader = "sprite",
		vs_entry_point = "vs_main",
		fs_shader = "sprite",
		fs_entry_point = "fs_main",
		topology = .TriangleStrip,
		vertex = {},
		instance = {
			ty_id = SpriteInstance,
			attributes = {
				{format = .Float32x2, offset = offset_of(SpriteInstance, pos)},
				{format = .Float32x2, offset = offset_of(SpriteInstance, size)},
				{format = .Float32, offset = offset_of(SpriteInstance, rotation)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, color)},
				{format = .Float32x4, offset = offset_of(SpriteInstance, uv)},
			},
		},
		bind_group_layouts = {globals_layout, rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {},
		blend = ALPHA_BLENDING,
		format = HDR_FORMAT,
	}
}

// create_sprite_render_pipeline :: proc(
// 	device: wgpu.Device,
// 	reg: ^ShaderRegistry,
// 	pipeline: ^RenderPipeline,
// ) {

// 	pipeline.fs_shader = "todo"
// 	pipeline.vs_shader = "todo"
// 	vs_shader_module := shader_registry_get(reg, vs_shader)

// 	shader = shader_registry_get()

// 	pipeline.fs_shader = "todo"
// 	pipeline.vs_shader = "todo"
// 	if pipeline.layout != nil {
// 		wgpu.PipelineLayoutRelease(pipeline.layout)
// 	}
// 	if pipeline.pipeline != nil {
// 		wgpu.RenderPipelineRelease(pipeline.pipeline)
// 	}

// 	// wgpu.Create
// 	shader :: `
// 	@vertex
// 	fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4<f32> {
// 		let x = f32(i32(in_vertex_index) - 1);
// 		let y = f32(i32(in_vertex_index & 1u) * 2 - 1);
// 		return vec4<f32>(x, y, 0.0, 1.0);
// 	}

// 	@fragment
// 	fn fs_main() -> @location(0) vec4<f32> {
// 		return vec4<f32>(1.0, 0.0, 0.0, 1.0);
// 	}`

// 	shader_module := wgpu.DeviceCreateShaderModule(
// 		device,
// 		&{
// 			nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
// 				sType = .ShaderModuleWGSLDescriptor,
// 				code = shader,
// 			},
// 		},
// 	)
// 	pipeline.layout = wgpu.DeviceCreatePipelineLayout(device, &{})
// 	pipeline.pipeline = wgpu.DeviceCreateRenderPipeline(
// 		device,
// 		&{
// 			layout = pipeline.layout,
// 			vertex = {module = shader_module, entryPoint = "vs_main"},
// 			fragment = &{
// 				module = shader_module,
// 				entryPoint = "fs_main",
// 				targetCount = 1,
// 				targets = &wgpu.ColorTargetState {
// 					format = SURFACE_FORMAT,
// 					writeMask = wgpu.ColorWriteMaskFlags_All,
// 				},
// 			},
// 			primitive = {topology = .TriangleList},
// 			multisample = {count = 1, mask = 0xFFFFFFFF},
// 		},
// 	)
// }
