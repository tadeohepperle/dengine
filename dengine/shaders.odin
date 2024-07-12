package dengine

import "core:fmt"
import "core:os"
import "core:strings"
import wgpu "vendor:wgpu"

ShaderRegistry :: struct {
	shaders_dir_path:                 string,
	changed_shaders_since_last_watch: [dynamic]string,
	device:                           wgpu.Device,
	shaders:                          map[string]Shader,
}

Shader :: struct {
	src_path:             string,
	src_last_write_time:  os.File_Time,
	src_wgsl_code:        string,
	composited_wgsl_code: StringAndCString, // resolved imports 
	shader_imports:       [dynamic]string,
	shader_module:        wgpu.ShaderModule, // nullable, only shaders with entry points create modules, not some wgsl snippets.
}

/// Both pointing to the same backing storage
StringAndCString :: struct {
	c_str: cstring,
	str:   string,
}

shader_registry_create :: proc(device: wgpu.Device) -> ShaderRegistry {
	return ShaderRegistry{device = device, shaders_dir_path = "./shaders"}
}

shader_registry_get :: proc(reg: ^ShaderRegistry, shader_name: string) -> wgpu.ShaderModule {
	shader, err := get_or_load_shader(reg, shader_name)
	if shader.shader_module == nil {
		err = create_shader_module(reg.device, shader)
	}
	if err != "" {
		fmt.panicf("shader_registry_get should not panic (at least not on hot-reload): %s", err)
	}

	return shader.shader_module
}

// Note: does not create shader module
get_or_load_shader :: proc(
	reg: ^ShaderRegistry,
	shader_name: string,
) -> (
	shader: ^Shader,
	err: string,
) {
	if shader_name not_in reg.shaders {
		loaded_shader: Shader
		loaded_shader, err = load_shader(reg, shader_name)
		if err != "" {
			return
		}
		reg.shaders[shader_name] = loaded_shader
	}
	shader = &reg.shaders[shader_name]
	return
}

// Note: does not create shader module
create_shader_module :: proc(device: wgpu.Device, shader: ^Shader) -> (err: string) {
	wgpu.DevicePushErrorScope(device, .Validation)
	shader.shader_module = wgpu.DeviceCreateShaderModule(
		device,
		&wgpu.ShaderModuleDescriptor {
			label = strings.clone_to_cstring(shader.src_path),
			nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
				sType = .ShaderModuleWGSLDescriptor,
				code = shader.composited_wgsl_code.c_str,
			},
		},
	)
	switch create_shader_err in wgpu_pop_error_scope(device) {
	case WgpuError:
		err = create_shader_err.message
	case:
	}
	return
}

load_shader :: proc(reg: ^ShaderRegistry, shader_name: string) -> (shader: Shader, err: string) {
	shader.src_path = fmt.aprintf("%s/%s.wgsl", reg.shaders_dir_path, shader_name)
	src_time, src_err := os.last_write_time_by_name(shader.src_path)
	if src_err != 0 {
		err = fmt.aprint("file does not exist:", shader.src_path)
		return
	}
	shader.src_last_write_time = src_time
	content, _ := os.read_entire_file(shader.src_path)
	shader.src_wgsl_code = string(content)

	// replace the #import statements in the code with contents of that shader.
	lines := strings.split_lines(shader.src_wgsl_code, context.temp_allocator)
	composited: strings.Builder
	for line in lines {
		if strings.has_prefix(line, "#import ") {
			if !strings.has_suffix(line, ".wgsl") {
				err = strings.clone(line)
				return
			}
			import_shader_name := strings.trim_space(line[7:len(line) - 5])
			import_shader: ^Shader
			import_shader, err = get_or_load_shader(reg, import_shader_name)
			if err != "" {
				return
			}
			append(&shader.shader_imports, import_shader_name)
			// replace the import line by the wgsl code in the imported file:
			strings.write_string(&composited, import_shader.composited_wgsl_code.str)
		} else {
			strings.write_string(&composited, line)
			strings.write_rune(&composited, '\n')
		}
	}
	shader.composited_wgsl_code = StringAndCString {
		c_str = strings.to_cstring(&composited),
		str   = strings.to_string(composited),
	}
	return
}


// load_


// load_shader_wgsl


// // Note: only reads in the shader source code files, does not 
// read_shader_source(shader_name: string )

// read_shader -> &Shader


// load_shader :: proc(   name: string) -> (shader: Shader) {
// 	shader.src_path = fmt.aprint()
// }

// shader_registry_get :: proc(shader_registry: ^ShaderRegistry, key: ShaderKey) -> vk.ShaderModule {
// 	shader, ok := shader_registry.shaders[key]
// 	if ok {
// 		return shader.shader_module
// 	}

// 	loaded_shader, err := load_shader(shader_registry.device, key)
// 	if err != nil {
// 		fmt.printfln("Could not load the shader module for %s, error: %s", key, err)
// 		os.exit(1)
// 	}
// 	shader_registry.shaders[key] = loaded_shader
// 	return loaded_shader.shader_module
// }
