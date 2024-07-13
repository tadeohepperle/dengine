package dengine

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import glfw "vendor:glfw"
import wgpu "vendor:wgpu"
import wgpu_glfw "vendor:wgpu/glfwglue"


HOT_RELOAD_SHADERS :: true
SURFACE_FORMAT := wgpu.TextureFormat.BGRA8UnormSrgb
HDR_FORMAT := wgpu.TextureFormat.RGBA16Float
HDR_SCREEN_TEXTURE_SETTINGS := TextureSettings {
	label        = "hdr_screen_texture",
	format       = HDR_FORMAT,
	address_mode = .ClampToEdge,
	mag_filter   = .Linear,
	min_filter   = .Nearest,
	usage        = {.RenderAttachment, .TextureBinding},
}

EngineSettings :: struct {
	title:        string,
	initial_size: [2]u32,
	tonemapping:  TonemappingMode,
	clear_color:  Color,
}

Engine :: struct {
	total_time:           f64,
	delta_time:           f64,
	input:                Input,
	settings:             EngineSettings,
	frame_size:           [2]u32,
	resized:              bool,
	should_close:         bool,
	window:               glfw.WindowHandle,
	surface_config:       wgpu.SurfaceConfiguration,
	surface:              wgpu.Surface,
	instance:             wgpu.Instance,
	adapter:              wgpu.Adapter,
	device:               wgpu.Device,
	queue:                wgpu.Queue,
	hdr_screen_texture:   Texture,
	shader_registry:      ShaderRegistry,
	globals_uniform:      UniformBuffer(Globals),
	tonemapping_pipeline: RenderPipeline,
	sprite_renderer:      SpriteRenderer,
	ui_renderer:          UiRenderer,
}


Globals :: struct {
	screen_size: Vec2,
	cursor_pos:  Vec2,
	camera_pos:  Vec2,
	camera_size: Vec2,
	time_secs:   f32,
	_pad:        f32,
}

engine_create :: proc(using engine: ^Engine, engine_settings: EngineSettings) {
	engine.settings = engine_settings
	_init_glfw_window(engine)
	_init_wgpu(engine)
	hdr_screen_texture = texture_create(device, frame_size, HDR_SCREEN_TEXTURE_SETTINGS)
	shader_registry = shader_registry_create(device)
	uniform_buffer_create(&globals_uniform, device)
	engine.tonemapping_pipeline.config = tonemapping_pipeline_config(device)
	render_pipeline_create_panic(&tonemapping_pipeline, device, &shader_registry)

	sprite_renderer_create(
		&sprite_renderer,
		device,
		queue,
		&shader_registry,
		globals_uniform.bind_group_layout,
	)
	// ui_renderer_create(
	// 	&engine.ui_renderer,
	// 	engine.device,
	// 	engine.queue,
	// 	&engine.shader_registry,
	// 	engine.globals_uniform.bind_group_layout,
	// )
}

engine_destroy :: proc(engine: ^Engine) {
	uniform_buffer_destroy(&engine.globals_uniform)
	sprite_renderer_destroy(&engine.sprite_renderer)
	ui_renderer_destroy(&engine.ui_renderer)
	wgpu.QueueRelease(engine.queue)
	wgpu.DeviceDestroy(engine.device)
	wgpu.InstanceRelease(engine.instance)
}

engine_start_frame :: proc(engine: ^Engine) -> bool {
	if engine.should_close {
		return false
	}

	time := glfw.GetTime()
	glfw.PollEvents()
	engine.delta_time = time - engine.total_time
	engine.total_time = time
	if glfw.WindowShouldClose(engine.window) || engine.input.keys[.ESCAPE] == .JustPressed {
		return false
	}

	when HOT_RELOAD_SHADERS {
		_engine_hot_reload_shaders(engine)
	}

	return true
}


_engine_hot_reload_shaders :: proc(engine: ^Engine) {
	pipelines := [?]^RenderPipeline{&engine.sprite_renderer.pipeline}
	shader_registry_hot_reload(&engine.shader_registry, pipelines[:])
}

engine_end_frame :: proc(engine: ^Engine, scene: ^Scene) {
	if engine.resized {
		_engine_resize(engine)
	}
	_engine_prepare(engine, scene)
	input_end_of_frame(&engine.input)
	_engine_render(engine, scene)
	scene_clear(scene)

}

// Note: assumes that engine.frame_size already contains the new size from the gltf resize callback
_engine_resize :: proc(engine: ^Engine) {
	engine.resized = false
	print("resized:", engine.surface_config)
	engine.surface_config.width = engine.frame_size.x
	engine.surface_config.height = engine.frame_size.y
	wgpu.SurfaceConfigure(engine.surface, &engine.surface_config)

	texture_destroy(&engine.hdr_screen_texture)
	engine.hdr_screen_texture = texture_create(
		engine.device,
		engine.frame_size,
		HDR_SCREEN_TEXTURE_SETTINGS,
	)
}

_engine_prepare :: proc(engine: ^Engine, scene: ^Scene) {
	screen_size := Vec2{f32(engine.frame_size.x), f32(engine.frame_size.y)}
	camera_size := Vec2 {
		scene.camera.y_height / screen_size.y * screen_size.x,
		scene.camera.y_height,
	}
	cursor_pos := [2]f32{f32(engine.input.cursor_pos.x), f32(engine.input.cursor_pos.y)}
	globals := Globals {
		screen_size = screen_size,
		cursor_pos  = cursor_pos,
		camera_pos  = scene.camera.pos,
		camera_size = camera_size,
		time_secs   = f32(engine.total_time),
	}
	uniform_buffer_write(engine.queue, &engine.globals_uniform, &globals)
	sprite_renderer_prepare(&engine.sprite_renderer, scene.sprites[:])
}

_engine_render :: proc(engine: ^Engine, scene: ^Scene) {
	surface_texture := wgpu.SurfaceGetCurrentTexture(engine.surface)
	switch surface_texture.status {
	case .Success:
	// All good, could check for `surface_texture.suboptimal` here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		_engine_resize(engine)
		return
	case .OutOfMemory, .DeviceLost:
		// Fatal error
		fmt.panicf("Fatal error in wgpu.SurfaceGetCurrentTexture, status=", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)
	surface_view := wgpu.TextureCreateView(
		surface_texture.texture,
		&wgpu.TextureViewDescriptor {
			label = "surface view",
			format = SURFACE_FORMAT,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = wgpu.TextureAspect.All,
		},
	)
	defer wgpu.TextureViewRelease(surface_view)

	command_encoder := wgpu.DeviceCreateCommandEncoder(engine.device, nil)
	defer wgpu.CommandEncoderRelease(command_encoder)


	// /////////////////////////////////////////////////////////////////////////////
	// SECTION: HDR Rendering
	// /////////////////////////////////////////////////////////////////////////////


	hdr_pass := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "surface render pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = engine.hdr_screen_texture.view,
				resolveTarget = nil,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = color_to_wgpu(engine.settings.clear_color),
			},
			depthStencilAttachment = nil,
			occlusionQuerySet = nil,
			timestampWrites = nil,
		},
	)
	defer wgpu.RenderPassEncoderRelease(hdr_pass)
	sprite_renderer_render(&engine.sprite_renderer, hdr_pass, engine.globals_uniform.bind_group)
	wgpu.RenderPassEncoderEnd(hdr_pass)

	// /////////////////////////////////////////////////////////////////////////////
	// SECTION: Tonemapping
	// /////////////////////////////////////////////////////////////////////////////
	tonemap(
		command_encoder,
		engine.tonemapping_pipeline.pipeline,
		engine.hdr_screen_texture.bind_group,
		surface_view,
		engine.settings.tonemapping,
	)
	// /////////////////////////////////////////////////////////////////////////////
	// SECTION: Present
	// /////////////////////////////////////////////////////////////////////////////


	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(engine.queue, {command_buffer})
	wgpu.SurfacePresent(engine.surface)

}


_init_glfw_window :: proc(engine: ^Engine) {
	glfw.Init()
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, 1)
	engine.window = glfw.CreateWindow(
		i32(engine.settings.initial_size.x),
		i32(engine.settings.initial_size.y),
		strings.clone_to_cstring(engine.settings.title),
		nil,
		nil,
	)
	w, h := glfw.GetFramebufferSize(engine.window)
	engine.frame_size = {u32(w), u32(h)}
	glfw.SetWindowUserPointer(engine.window, engine)

	framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()
		engine: ^Engine = auto_cast glfw.GetWindowUserPointer(window)
		engine.resized = true
		engine.frame_size = {u32(width), u32(height)}
	}
	glfw.SetFramebufferSizeCallback(engine.window, framebuffer_size_callback)

	key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, _mods: i32) {
		context = runtime.default_context()
		engine: ^Engine = auto_cast glfw.GetWindowUserPointer(window)
		input_receive_glfw_key_event(&engine.input, key, action)
	}
	glfw.SetKeyCallback(engine.window, key_callback)

	mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, _mods: i32) {
		context = runtime.default_context()
		engine: ^Engine = auto_cast glfw.GetWindowUserPointer(window)
		input_receive_glfw_mouse_btn_event(&engine.input, button, action)
	}
	glfw.SetMouseButtonCallback(engine.window, mouse_button_callback)
}

_init_wgpu :: proc(engine: ^Engine) {
	instance_extras := wgpu.InstanceExtras {
		chain = {next = nil, sType = wgpu.SType.InstanceExtras},
		backends = wgpu.InstanceBackendFlags_All,
	}
	engine.instance = wgpu.CreateInstance(
		&wgpu.InstanceDescriptor{nextInChain = &instance_extras.chain},
	)
	engine.surface = wgpu_glfw.GetSurface(engine.instance, engine.window)

	AwaitStatus :: enum {
		Awaiting,
		Success,
		Error,
	}

	AdapterResponse :: struct {
		adapter: wgpu.Adapter,
		status:  wgpu.RequestAdapterStatus,
		message: cstring,
	}
	adapter_res: AdapterResponse
	wgpu.InstanceRequestAdapter(
		engine.instance,
		&wgpu.RequestAdapterOptions {
			powerPreference = wgpu.PowerPreference.HighPerformance,
			compatibleSurface = engine.surface,
		},
		proc "c" (
			status: wgpu.RequestAdapterStatus,
			adapter: wgpu.Adapter,
			message: cstring,
			userdata: rawptr,
		) {
			adapter_res: ^AdapterResponse = auto_cast userdata
			adapter_res.status = status
			adapter_res.adapter = adapter
			adapter_res.message = message
		},
		&adapter_res,
	)
	if adapter_res.status != .Success {
		fmt.panicf("Failed to get wgpu adapter: %s", adapter_res.message)
	}
	assert(adapter_res.adapter != nil)
	engine.adapter = adapter_res.adapter

	print("Created adapter successfully")


	DeviceRes :: struct {
		status:  wgpu.RequestDeviceStatus,
		device:  wgpu.Device,
		message: cstring,
	}
	device_res: DeviceRes


	required_features := [?]wgpu.FeatureName{.PushConstants}
	required_limits_extras := wgpu.RequiredLimitsExtras {
		chain = {sType = .RequiredLimitsExtras},
		limits = wgpu.NativeLimits{maxPushConstantSize = 128, maxNonSamplerBindings = 1_000_000},
	}
	required_limits := wgpu.RequiredLimits {
		nextInChain = &required_limits_extras.chain,
		limits      = WGPU_DEFAULT_LIMITS,
	}
	wgpu.AdapterRequestDevice(
		engine.adapter,
		&wgpu.DeviceDescriptor {
			requiredFeatureCount = uint(len(required_features)),
			requiredFeatures = &required_features[0],
			requiredLimits = &required_limits,
		},
		proc "c" (
			status: wgpu.RequestDeviceStatus,
			device: wgpu.Device,
			message: cstring,
			userdata: rawptr,
		) {
			context = runtime.default_context()
			print("Err: ", message)
			device_res: ^DeviceRes = auto_cast userdata
			device_res.status = status
			device_res.device = device
			device_res.message = message
		},
		&device_res,
	)
	if device_res.status != .Success {
		fmt.panicf("Failed to get wgpu device: %s", device_res.message)
	}
	assert(device_res.device != nil)
	engine.device = device_res.device
	print("Created device successfully")

	engine.queue = wgpu.DeviceGetQueue(engine.device)
	assert(engine.queue != nil)

	engine.surface_config = wgpu.SurfaceConfiguration {
		device          = engine.device,
		format          = SURFACE_FORMAT,
		usage           = {.RenderAttachment},
		viewFormatCount = 1,
		viewFormats     = &SURFACE_FORMAT,
		alphaMode       = .Opaque,
		width           = engine.frame_size.x,
		height          = engine.frame_size.y,
		presentMode     = .Immediate,
	}

	// wgpu_error_callback :: proc "c" (type: wgpu.ErrorType, message: cstring, userdata: rawptr) {
	// 	context = runtime.default_context()
	// 	print("-----------------------------")
	// 	print("ERROR CAUGHT: ", type, message)
	// 	print("-----------------------------")
	// }
	// wgpu.DeviceSetUncapturedErrorCallback(engine.device, wgpu_error_callback, nil)

	wgpu.SurfaceConfigure(engine.surface, &engine.surface_config)

}

tonemapping_pipeline_config :: proc(device: wgpu.Device) -> RenderPipelineConfig {
	return RenderPipelineConfig {
		debug_name = "tonemapping",
		vs_shader = "screen",
		vs_entry_point = "vs_main",
		fs_shader = "tonemapping",
		fs_entry_point = "fs_main",
		topology = .TriangleList,
		vertex = {},
		instance = {},
		bind_group_layouts = {rgba_bind_group_layout_cached(device)},
		push_constant_ranges = {
			wgpu.PushConstantRange {
				stages = {.Fragment},
				start = 0,
				end = size_of(TonemappingMode),
			},
		},
		blend = ALPHA_BLENDING,
		format = SURFACE_FORMAT,
	}
}

TonemappingMode :: enum u32 {
	Disabled = 0,
	Aces     = 1,
}

tonemap :: proc(
	command_encoder: wgpu.CommandEncoder,
	tonemapping_pipeline: wgpu.RenderPipeline,
	hdr_texture_bind_group: wgpu.BindGroup,
	sdr_texture_view: wgpu.TextureView,
	mode: TonemappingMode,
) {
	tonemap_pass := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "surface render pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = sdr_texture_view,
				resolveTarget = nil,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = wgpu.Color{0.2, 0.3, 0.4, 1.0},
			},
			depthStencilAttachment = nil,
			occlusionQuerySet = nil,
			timestampWrites = nil,
		},
	)
	defer wgpu.RenderPassEncoderRelease(tonemap_pass)

	wgpu.RenderPassEncoderSetPipeline(tonemap_pass, tonemapping_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(tonemap_pass, 0, hdr_texture_bind_group)
	push_constants := mode
	wgpu.RenderPassEncoderSetPushConstants(
		tonemap_pass,
		{.Fragment},
		0,
		size_of(TonemappingMode),
		&push_constants,
	)
	wgpu.RenderPassEncoderDraw(tonemap_pass, 3, 1, 0, 0)

	wgpu.RenderPassEncoderEnd(tonemap_pass)
}
