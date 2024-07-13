package dengine

import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"
import wgpu "vendor:wgpu"

// We only support sdf fonts created with https://github.com/tadeohepperle/assetpacker
//
// This type should be equivalent to the SdfFont struct in the assetpacker Rust crate (https://github.com/tadeohepperle/assetpacker/blob/main/src/font.rs).
Font :: struct {
	rasterization_size: int,
	line_metrics:       LineMetrics,
	name:               string,
	glyphs:             map[rune]Glyph,
	texture:            ^Texture,
}

LineMetrics :: struct {
	ascent:        f32,
	descent:       f32,
	line_gap:      f32,
	new_line_size: f32,
}

Glyph :: struct {
	xmin:           f32,
	ymin:           f32,
	width:          f32,
	height:         f32,
	advance:        f32,
	is_white_space: bool,
	uv_min:         Vec2,
	uv_max:         Vec2,
}


FontLoadError :: union {
	string,
	json.Unmarshal_Error,
	image.Error,
}


// this function expects to find a file at {path}.json and {path}.png, representing the fonts data and sdf glyphs
load_font :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	path: string,
) -> (
	font: Font,
	error: FontLoadError,
) {
	// read json:
	FontWithStringKeys :: struct {
		rasterization_size: int,
		line_metrics:       LineMetrics,
		name:               string,
		glyphs:             map[string]Glyph,
	}
	font_with_string_keys: FontWithStringKeys
	json_path := fmt.aprintf("%s.sdf_font.json", path, allocator = context.temp_allocator)
	json_bytes, ok := os.read_entire_file(json_path)
	if !ok {
		error = "could not read file"
		return
	}
	defer {delete(json_bytes)}
	json_err := json.unmarshal(json_bytes, &font_with_string_keys)
	if json_err != nil {
		error = json_err
		return
	}
	font.rasterization_size = font_with_string_keys.rasterization_size
	font.line_metrics = font_with_string_keys.line_metrics
	font.name = font_with_string_keys.name
	font.glyphs = make_map(map[rune]Glyph, len(font_with_string_keys.glyphs))
	for s, v in font_with_string_keys.glyphs {
		if len(s) != 1 {
			error = "Only single character strings allowed as glyph keys!"
			return
		}
		for r in s {
			font.glyphs[r] = v
			break
		}
	}
	delete(font_with_string_keys.glyphs)

	// read image: 


	png_path := fmt.aprintf("%s.sdf_font.png", path, allocator = context.temp_allocator)
	tex_err: image.Error
	font.texture = new(Texture)
	font.texture^, tex_err = texture_from_image_path(device, queue, path = png_path)
	if tex_err != nil {
		error = tex_err
		return
	}
	return
}
