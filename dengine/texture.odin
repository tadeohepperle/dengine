package dengine

import "core:fmt"
import "core:image"
import "core:image/png"
import wgpu "vendor:wgpu"

IMAGE_FORMAT :: wgpu.TextureFormat.RGBA8Unorm

DEFAULT_TEXTURESETTINGS :: TextureSettings {
	label        = "",
	format       = IMAGE_FORMAT,
	address_mode = .Repeat,
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
	path: string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	texture: Texture,
	error: image.Error,
) {
	img, img_error := image.load_from_file(path, options = image.Options{.alpha_add_if_missing})
	if img_error != nil {
		error = img_error
		return
	}
	defer {image.destroy(img)}
	texture = texture_from_image(device, queue, img, settings)
	return
}

COPY_BYTES_PER_ROW_ALIGNMENT: u32 : 256 // Buffer-Texture copies must have [`bytes_per_row`] aligned to this number.
texture_from_image :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	img: ^image.Image,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
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

texture_create_1px_white :: proc(device: wgpu.Device, queue: wgpu.Queue) -> Texture {
	texture := texture_create(device, {1, 1}, DEFAULT_TEXTURESETTINGS)
	block_size: u32 = 4
	image_copy := texture_as_image_copy(&texture)
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = 4,
		rowsPerImage = 1,
	}
	data := [4]u8{255, 255, 255, 255}
	wgpu.QueueWriteTexture(
		queue,
		&image_copy,
		&data,
		4,
		&data_layout,
		&wgpu.Extent3D{width = 1, height = 1, depthOrArrayLayers = 1},
	)
	return texture
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
	texture.size = size
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
	layout: wgpu.BindGroupLayout
	if layout == nil {
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


TextureTile :: struct {
	texture: ^Texture,
	uv:      Aabb,
}


TextureArray :: struct {
	settings:   TextureSettings,
	size:       UVec2,
	layers:     u32,
	texture:    wgpu.Texture,
	view:       wgpu.TextureView,
	sampler:    wgpu.Sampler,
	bind_group: wgpu.BindGroup,
}

rgba_texture_array_bind_group_layout_cached :: proc(device: wgpu.Device) -> wgpu.BindGroupLayout {
	@(static)
	layout: wgpu.BindGroupLayout
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

texture_array_create :: proc(
	device: wgpu.Device,
	size: UVec2,
	layers: u32,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	texture_array: TextureArray,
) {
	assert(wgpu.TextureUsage.TextureBinding in settings.usage)
	texture_array.settings = settings
	texture_array.size = size
	texture_array.layers = layers
	descriptor := wgpu.TextureDescriptor {
		usage = settings.usage,
		dimension = ._2D,
		size = wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = layers},
		format = settings.format,
		mipLevelCount = 1,
		sampleCount = 1,
		viewFormatCount = 1,
		viewFormats = &texture_array.settings.format,
	}
	texture_array.texture = wgpu.DeviceCreateTexture(device, &descriptor)
	texture_view_descriptor := wgpu.TextureViewDescriptor {
		format          = settings.format,
		dimension       = ._2DArray,
		baseMipLevel    = 0,
		mipLevelCount   = 1,
		baseArrayLayer  = 0,
		arrayLayerCount = layers,
		aspect          = .All,
	}
	texture_array.view = wgpu.TextureCreateView(texture_array.texture, &texture_view_descriptor)

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
	texture_array.sampler = wgpu.DeviceCreateSampler(device, &sampler_descriptor)

	bind_group_descriptor_entries := [?]wgpu.BindGroupEntry {
		wgpu.BindGroupEntry{binding = 0, textureView = texture_array.view},
		wgpu.BindGroupEntry{binding = 1, sampler = texture_array.sampler},
	}
	bind_group_descriptor := wgpu.BindGroupDescriptor {
		layout     = rgba_texture_array_bind_group_layout_cached(device),
		entryCount = uint(len(bind_group_descriptor_entries)),
		entries    = &bind_group_descriptor_entries[0],
	}
	texture_array.bind_group = wgpu.DeviceCreateBindGroup(device, &bind_group_descriptor)
	return
}


texture_array_destroy :: proc(texture_array: ^TextureArray) {
	wgpu.BindGroupRelease(texture_array.bind_group)
	wgpu.SamplerRelease(texture_array.sampler)
	wgpu.TextureViewRelease(texture_array.view)
	wgpu.TextureRelease(texture_array.texture)
}

texture_array_from_image_paths :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	paths: []string,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	texture_array: TextureArray,
	error: string,
) {
	images := make([dynamic]^image.Image)
	defer {delete(images)}
	defer {for img in images {
			image.destroy(img)
		}}
	width: int
	height: int
	for path, i in paths {
		img, img_error := image.load_from_file(
			path,
			options = image.Options{.alpha_add_if_missing},
		)
		if img_error != nil {
			error = fmt.aprint(img_error, allocator = context.temp_allocator)
			return
		}
		if i == 0 {
			width = img.width
			height = img.height
		} else {
			if img.width != width || img.height != height {
				error = fmt.aprintf(
					"Image at path %s has size %d,%d but it should be %d,%d",
					path,
					img.width,
					img.height,
					width,
					height,
				)
				return
			}
		}
		append(&images, img)
	}
	texture_array = texture_array_from_images(device, queue, images[:], settings)
	return
}


texture_array_from_images :: proc(
	device: wgpu.Device,
	queue: wgpu.Queue,
	images: []^image.Image,
	settings: TextureSettings = DEFAULT_TEXTURESETTINGS,
) -> (
	texture_array: TextureArray,
) {
	assert(len(images) > 0)

	width := images[0].width
	height := images[0].height
	for e in images {
		assert(e.width == width)
		assert(e.height == height)
	}
	size := UVec2{u32(width), u32(height)}
	layers := u32(len(images))
	texture_array = texture_array_create(device, size, layers, settings)

	assert(settings.format == IMAGE_FORMAT)
	block_size: u32 = 4
	bytes_per_row :=
		((size.x * block_size + COPY_BYTES_PER_ROW_ALIGNMENT - 1) &
			~(COPY_BYTES_PER_ROW_ALIGNMENT - 1))
	data_layout := wgpu.TextureDataLayout {
		offset       = 0,
		bytesPerRow  = bytes_per_row,
		rowsPerImage = size.y,
	}
	for img, i in images {
		image_copy := wgpu.ImageCopyTexture {
			texture  = texture_array.texture,
			mipLevel = 0,
			origin   = {0, 0, u32(i)},
			aspect   = .All,
		}
		wgpu.QueueWriteTexture(
			queue,
			&image_copy,
			raw_data(img.pixels.buf),
			uint(len(img.pixels.buf)),
			&data_layout,
			&wgpu.Extent3D{width = size.x, height = size.y, depthOrArrayLayers = 1},
		)
	}
	return
}
