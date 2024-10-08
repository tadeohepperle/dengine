package dengine

import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"
import wgpu "vendor:wgpu"

TextureHandle :: distinct u32
TextureArrayHandle :: distinct u32
FontHandle :: distinct u32

DEFAULT_FONT :: FontHandle(0)
DEFAULT_TEXTURE :: FontHandle(0)

TextureSlot :: struct #raw_union {
	texture:       Texture,
	next_free_idx: int,
}
#assert(size_of(Texture) == size_of(TextureSlot))

AssetManager :: struct {
	textures: SlotMap(Texture), // also contains texture arrays!
	fonts:    SlotMap(Font),
	device:   wgpu.Device,
	queue:    wgpu.Queue,
}
asset_manager_create :: proc(
	assets: ^AssetManager,
	default_font_path: string,
	device: wgpu.Device,
	queue: wgpu.Queue,
) {
	assets.device = device
	assets.queue = queue
	assets.textures = slotmap_create(Texture)
	assets.fonts = slotmap_create(Font)

	default_texture := _texture_create_1px_white(device, queue)
	default_texture_handle := slotmap_insert(&assets.textures, default_texture)
	assert(default_texture_handle == 0) // is the first one

	default_font_handle := assets_load_font(assets, default_font_path)
	assert(default_font_handle == 0) // is the first one
}
asset_manager_destroy :: proc(assets: ^AssetManager) {
	textures := slotmap_to_slice(assets.textures)
	for &texture in textures {
		texture_destroy(&texture)
	}
	fonts := slotmap_to_slice(assets.fonts)
	for &font in fonts {
		font_destroy(&font)
	}
}

assets_get_texture_array_bind_group :: proc(
	assets: AssetManager,
	handle: TextureArrayHandle,
) -> wgpu.BindGroup {
	texture := slotmap_get(assets.textures, u32(handle))
	return texture.bind_group
}
assets_get_texture_bind_group :: proc(
	assets: AssetManager,
	handle: TextureHandle,
) -> wgpu.BindGroup {
	texture := slotmap_get(assets.textures, u32(handle))
	return texture.bind_group
}

assets_get_font_texture_bind_group :: proc(
	assets: AssetManager,
	handle: FontHandle,
) -> wgpu.BindGroup {
	font := slotmap_get(assets.fonts, u32(handle))
	texture := slotmap_get(assets.textures, u32(font.texture))
	return texture.bind_group
}

assets_get_texture_info :: proc(assets: AssetManager, handle: TextureHandle) -> TextureInfo {
	texture := slotmap_get(assets.textures, u32(handle))
	return texture.info
}

assets_get_font :: proc(assets: AssetManager, handle: FontHandle) -> Font {
	return slotmap_get(assets.fonts, u32(handle))
}

assets_load_texture :: proc(
	assets: ^AssetManager,
	path: string,
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
) -> TextureHandle {
	texture, err := texture_from_image_path(assets.device, assets.queue, path, settings)
	if err != nil {
		print("error:", err)
		panic("Panic loading texture.")
	}
	texture_handle := TextureHandle(slotmap_insert(&assets.textures, texture))
	return texture_handle
}

assets_load_texture_array :: proc(
	assets: ^AssetManager,
	paths: []string,
	settings: TextureSettings = TEXTURE_SETTINGS_DEFAULT,
) -> TextureArrayHandle {
	texture, err := texture_array_from_image_paths(assets.device, assets.queue, paths, settings)
	if err != nil {
		print("error:", err)
		panic("Panic loading texture.")
	}
	texture_handle := TextureArrayHandle(slotmap_insert(&assets.textures, texture))
	return texture_handle
}

assets_load_font :: proc(assets: ^AssetManager, path: string) -> FontHandle {
	font, font_texture, err := _font_load_from_path(path, assets.device, assets.queue)
	if err != nil {
		print("error:", err)
		panic("Panic loading font.")
	}
	font_texture_handle := slotmap_insert(&assets.textures, font_texture)
	font.texture = TextureHandle(font_texture_handle)
	font_handle := FontHandle(slotmap_insert(&assets.fonts, font))
	return font_handle
}

assets_deregister_texture :: proc(assets: ^AssetManager, handle: TextureHandle) {
	texture := slotmap_remove(&assets.textures, u32(handle))
	texture_destroy(&texture)
}

assets_deregister_font :: proc(assets: ^AssetManager, handle: FontHandle) {
	font := slotmap_remove(&assets.fonts, u32(handle))
	font_destroy(&font)
	assets_deregister_texture(assets, font.texture)
}

/*

Todo: add a white texture with 1px that can always be used as a fallback for TextureHandle 0

*/


// font.texture = TextureHandle(slotmap_insert(&assets.textures, font_texture))
// 	font_handle = FontHandle(slotmap_insert(&assets.fonts, font))
