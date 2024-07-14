package dengine

import "core:image"
import "core:image/png"
import wgpu "vendor:wgpu"

IMAGE_FORMAT :: wgpu.TextureFormat.RGBA8Unorm

DEFAULT_TEXTURESETTINGS :: TextureSettings {
	label        = "",
	format       = IMAGE_FORMAT,
	address_mode = .ClampToEdge,
	mag_filter   = .Linear,
	min_filter   = .Nearest,
	usage        = {.TextureBinding, .CopyDst},
}

TextureSettings :: struct {
	label:        string,
	format:       wgpu.TextureFormat,
	address_mode: wgpu.AddressMode,
	mag_filter:   wgpu.FilterMode,
	min_filter:   wgpu.FilterMode,
	usage:        wgpu.TextureUsageFlags,
}

Texture :: struct {
	settings:   TextureSettings,
	size:       UVec2,
	texture:    wgpu.Texture,
	view:       wgpu.TextureView,
	sampler:    wgpu.Sampler,
	bind_group: wgpu.BindGroup,
}


texture_from_image_path :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
	path: string,
) -> (
	texture: Texture,
	error: image.Error,
) {
	img, img_error := image.load_from_file(path)
	if img_error != nil {
		error = img_error
		return
	}
	defer {image.destroy(img)}
	texture = texture_from_image(device, queue, settings, img)
	return
}

COPY_BYTES_PER_ROW_ALIGNMENT: u32 : 256 // Buffer-Texture copies must have [`bytes_per_row`] aligned to this number.
texture_from_image :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
	img: ^image.Image,
) -> (
	texture: Texture,
) {

	size := UVec2{u32(img.width), u32(img.height)}
	texture = texture_create(device, size, settings)

	assert(settings.format == IMAGE_FORMAT)
	block_size: u32 = 4
	bytes_per_row :=
		((size.x * block_size + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &
			~(COPY_BYTES_PER_ROW_ALIGNMENT - 1))
	image_copy := texture_as_image_copy(&texture)
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = size.y,
	}
	wgpu.QueueWriteTexture(
		queue,
		&image_copy,
		raw_data(img.pixels.buf),
		uint(len(img.pixels.buf)),
		&data_layout,
		&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
	)
	return
}


texture_as_image_copy :: proc(texture: ^Texture) -> wgpu.ImageCopyTexture {
	return wgpu.ImageCopyTexture {
		texture = texture.texture,
		mipLevel = 0,
		origin = {0, 0, 0},
		aspect = .All,
	}
}

texture_create :: proc(
	device: wgpu.Device,
	size: UVec2,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	texture: Texture,
) {
	assert(wgpu.TextureUsage.TextureBinding in settings.usage)
	texture.settings = settings
	descriptor := wgpu.TextureDescriptor {
		usage = settings.usage,
		dimension = ._2D,
		size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
		format = settings.format,
		mipLevelCount = 1,
		sampleCount = 1,
		viewFormatCount = 1,
		viewFormats = &texture.settings.format,
	}
	texture.texture = wgpu.DeviceCreateTexture(device, &descriptor)

	texture_view_descriptor := wgpu.TextureViewDescriptor {
		format          = settings.format,
		dimension       = ._2D,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = 1,
		aspect          = .All,
	}
	texture.view = wgpu.TextureCreateView(texture.texture, &texture_view_descriptor)

	sampler_descriptor := wgpu.SamplerDescriptor {
		addressModeU  = settings.address_mode,
		addressModeV  = settings.address_mode,
		addressModeW  = settings.address_mode,
		magFilter     = settings.mag_filter,
		minFilter     = settings.min_filter,
		mipmapFilter  = .Nearest,
		maxAnisotropy = 1,
		// ...
	}
	texture.sampler = wgpu.DeviceCreateSampler(device, &sampler_descriptor)

	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = texture.view},
		wgpu.BindGroupEntry{binding = 1, sampler = texture.sampler},
	}
	bind_group_descriptor := wgpu.BindGroupDescriptor {
		layout     = rgba_bind_group_layout_cached(device),
		entryCount = uint(len(bind_group_descriptor_entries)),
		entries    = &bind_group_descriptor_entries[0],
	}
	texture.bind_group = wgpu.DeviceCreateBindGroup(device, &bind_group_descriptor)
	return
}


texture_destroy :: proc(texture: ^Texture) {
	wgpu.BindGroupRelease(texture.bind_group)
	wgpu.SamplerRelease(texture.sampler)
	wgpu.TextureViewRelease(texture.view)
	wgpu.TextureRelease(texture.texture)
}

rgba_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static)
	rgba_bind_group_layout: wgpu.BindGroupLayout
	if rgba_bind_group_layout == nil {
		entries := [?]wgpu.BindGroupLayoutEntry {
			wgpu.BindGroupLayoutEntry {
				binding = 0,
				visibility = {.Fragment},
				texture = wgpu.TextureBindingLayout {
					sampleType = .Float,
					viewDimension = ._2D,
					multisampled = false,
				},
			},
			wgpu.BindGroupLayoutEntry {
				binding = 1,
				visibility = {.Fragment},
				sampler = wgpu.SamplerBindingLayout{type = .Filtering},
			},
		}
		rgba_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
			device,
			&wgpu.BindGroupLayoutDescriptor {
				entryCount = uint(len(entries)),
				entries = &entries[0],
			},
		)
	}
	return rgba_bind_group_layout
}

TextureTile :: struct {
	texture: ^Texture,
	uv:      Aabb,
}
