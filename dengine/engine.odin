package dengine

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import glfw "vendor:glfw"
import wgpu "vendor:wgpu"
import wgpu_glfw "vendor:wgpu/glfwglue"


EngineSettings :: struct {
	title: string,
	size:  [2]u32,
}

SURFACE_FORMAT := wgpu.TextureFormat.BGRA8UnormSrgb

HOT_RELOAD_SHADERS :: true

Engine :: struct {
	total_time:      f64,
	delta_time:      f64,
	input:           Input,
	settings:        EngineSettings,
	frame_size:      [2]u32,
	resized:         bool,
	should_close:    bool,
	window:          glfw.WindowHandle,
	surface_config:  wgpu.SurfaceConfiguration,
	surface:         wgpu.Surface,
	instance:        wgpu.Instance,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	queue:           wgpu.Queue,
	shader_registry: ShaderRegistry,
	sprite_renderer: SpriteRenderer,
	globals_uniform: UniformBuffer(Globals),
}


Globals :: struct {
	screen_size: Vec2,
	cursor_pos:  Vec2,
	camera_pos:  Vec2,
	camera_size: Vec2,
	time_secs:   f32,
	_pad:        f32,
}

engine_create :: proc(engine: ^Engine, settings: EngineSettings) {
	engine.settings = settings
	_init_glfw_window(engine)
	_init_wgpu(engine)
	engine.shader_registry = shader_registry_create(engine.device)
	uniform_buffer_create(engine.device, &engine.globals_uniform)
	sprite_renderer_create(
		&engine.sprite_renderer,
		engine.device,
		engine.queue,
		&engine.shader_registry,
		engine.globals_uniform.bind_group_layout,
	)
}


engine_destroy :: proc(engine: ^Engine) {
	// todo! destroy uniforms
	// destroy render pipelines
	wgpu.DeviceDestroy(engine.device)

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
	// todo!
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

_engine_resize :: proc(engine: ^Engine) {
	engine.resized = false
	print("resized:", engine.surface_config)
	engine.surface_config.width = engine.frame_size.x
	engine.surface_config.height = engine.frame_size.y
	wgpu.SurfaceConfigure(engine.surface, &engine.surface_config)
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


	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		command_encoder,
		&wgpu.RenderPassDescriptor {
			label = "surface render pass",
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = surface_view,
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
	defer wgpu.RenderPassEncoderRelease(render_pass_encoder)

	sprite_renderer_render(
		&engine.sprite_renderer,
		render_pass_encoder,
		engine.globals_uniform.bind_group,
	)

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
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
		i32(engine.settings.size.x),
		i32(engine.settings.size.y),
		strings.clone_to_cstring(engine.settings.title),
		nil,
		nil,
	)
	w, h := glfw.GetFramebufferSize(engine.window)
	engine.frame_size = {u32(w), u32(h)}
	glfw.SetWindowUserPointer(engine.window, engine)
	// framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {

	// 	context = runtime.default_context()
	// 	print("resized:")

	// 	// engine: ^Engine = auto_cast glfw.GetWindowUserPointer(window)
	// 	// engine.resized = true

	// 	// engine.frame_size = {u32(width), u32(height)}

	// }
	// glfw.SetFramebufferSizeCallback(engine.window, framebuffer_size_callback)

	framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
		context = runtime.default_context()
		engine: ^Engine = auto_cast glfw.GetWindowUserPointer(window)
		engine.resized = true
		engine.frame_size = {u32(width), u32(height)}
		// os.write_entire_file("hello.txt", transmute([]u8)fmt.aprint("w,h = ", width, height))
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

// init_hdr_render_target :: pro

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


	// TODO:
	// required_features: config.features,
	// required_limits: wgpu::Limits {
	// 	max_push_constant_size: config.max_push_constant_size,
	// 	..Default::default()
	// },
	wgpu.AdapterRequestDevice(
		engine.adapter,
		&wgpu.DeviceDescriptor{},
		proc "c" (
			status: wgpu.RequestDeviceStatus,
			device: wgpu.Device,
			message: cstring,
			userdata: rawptr,
		) {

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
