-- RE:LÖVisual
-- Copyright (C) 2018 MikuAuahDark
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <https://www.gnu.org/licenses/>.

local love = require("love")
local bit = require("bit")
local ffi = require("ffi")
local fftw = require("fftw3")
local relyz = {
	-- Uses livesim2 version convention
	VERSION_NUMBER = 01000000,
	VERSION = "1.0.0",
}

-- We need to use many strategies to take account of Linux & macOS
-- Damn this is one of reason why Linux sucks.
-- For Windows, the first pattern should match it. Feel yourself as VIP citizens.
local function loadLibAV(libname, ver)
	-- 1. name-ver
	local s, out = pcall(ffi.load, libname.."-"..ver)
	if s then return out end

	-- 2. name.ver
	s, out = pcall(ffi.load, libname.."."..ver)
	if s then return out end

	-- 3. libname-ver.so
	s, out = pcall(ffi.load, "lib"..libname.."-"..ver..".so")
	if s then return out end

	-- 3. libname.ver.so
	s, out = pcall(ffi.load, "lib"..libname.."."..ver..".so")
	if s then return out end

	-- 4. libname.so.ver
	s, out = pcall(ffi.load, "lib"..libname..".so."..ver)
	if s then return out end

	-- 5. libname-ver.dylib
	s, out = pcall(ffi.load, "lib"..libname.."-"..ver..".dylib")
	if s then return out end

	-- 6. libname.ver.dylib
	s, out = pcall(ffi.load, "lib"..libname.."."..ver..".dylib")
	if s then return out end

	-- 7. libname.dylib.ver
	s, out = pcall(ffi.load, "lib"..libname..".dylib."..ver)
	if s then return out end

	return nil
end

local function avVersion(int)
	return bit.rshift(int, 16), bit.rshift(bit.band(int, 0xFF00), 8), bit.band(int, 0xFF)
end

-- libav table
local libav = {}
relyz.libav = libav
libav.avutil = loadLibAV("avutil", 55)
libav.swresample = loadLibAV("swresample", 2)
libav.avcodec = loadLibAV("avcodec", 57)
libav.avformat = loadLibAV("avformat", 57)
libav.swscale = loadLibAV("swscale", 4)

-- We really need this, but Linux is making this harder :)
-- Windows users: feel yourself as VIP citizens (again)!
assert(
	libav.avutil and
	libav.swresample and
	libav.avcodec and
	libav.avformat and
	libav.swscale,
	"Cannot load libav library. Make sure FFmpeg v3.x are installed!"
)

-- Please, we need FFmpeg v3.x
-- This version check should be satisfied if your system is not evil enough.
ffi.cdef [[
unsigned avcodec_version(void);
unsigned avformat_version(void);
unsigned avutil_version(void);
]]
assert(
	select(1, avVersion(libav.avcodec.avcodec_version())) >= 57 and
	select(1, avVersion(libav.avformat.avformat_version())) >= 57 and
	select(1, avVersion(libav.avutil.avutil_version())) >= 55,
	"LibAV version is not satisfied!"
)

-- Load include.
-- The include file is compressed with DEFLATE algorithm and with gzip header.
do
	local header = love.data.decompress("string", "gzip", love.filesystem.read("relyz_ffx.h.gz"))
	ffi.cdef(header)
end

-- Initialize
libav.avformat.av_register_all()
libav.avcodec.avcodec_register_all()

-- Helper function to free AVFrame
local function deleteFrame(frame)
	local x = ffi.new("AVFrame*[1]")
	x[0] = frame libav.avutil.av_frame_free(x)
end

-- Helper function to free AVCodecContext
local function deleteCodecContext(ctx)
	local x = ffi.new("AVCodecContext*[1]")
	x[0] = ctx libav.avcodec.avcodec_free_context(x)
end

--- Load audio from system-dependent path
-- This function uses FFmpeg API (libav) to load audio.
-- @tparam string path Audio path
-- @treturn SoundData Audio sound data
-- @treturn table Audio metadata (audio cover can be accessed in `coverArt` field)
function relyz.loadAudio(path)
	-- This is metadata output
	local output = {}
	local tempfmtctx = ffi.new("AVFormatContext*[1]")

	-- Open input file
	if libav.avformat.avformat_open_input(tempfmtctx, path, nil, nil) < 0 then
		error("Failed to load audio: failed to load file "..path, 2)
	end

	-- Find stream info
	if libav.avformat.avformat_find_stream_info(tempfmtctx[0], nil) < 0 then
		libav.avformat.avformat_close_input(tempfmtctx)
		error("Failed to load audio: avformat_find_stream_info failed", 2)
	end

	-- We use "video" for cover art.
	local vididx, audioidx
	for i = 1, tempfmtctx[0].nb_streams do
		local codec_type = tempfmtctx[0].streams[i - 1].codec.codec_type

		if codec_type == "AVMEDIA_TYPE_AUDIO" and not(audioidx) then
			audioidx = i - 1
		elseif codec_type == "AVMEDIA_TYPE_VIDEO" and not(vididx) then
			vididx = i - 1
		end

		if audioidx and vididx then break end
	end

	if not(audioidx) then
		libav.avformat.avformat_close_input(tempfmtctx)
		error("Failed to load audio: audio stream not found", 2)
	end

	-- Read tags (metadata)
	do
		local tag = nil
		tag = libav.avutil.av_dict_get(tempfmtctx[0].metadata, "", tag, 2)

		while tag ~= nil do
			local k, v = ffi.string(tag.key):lower(), ffi.string(tag.value)
			output[k] = v
			tag = libav.avutil.av_dict_get(tempfmtctx[0].metadata, "", tag, 2)
		end
	end

	local audiostream = tempfmtctx[0].streams[audioidx]
	local acodec, acctx, aframe, SwrCtx
	local videostream, vcodec, vcctx, vframe, vframergb, vimgdt, SwsCtx

	acodec = libav.avcodec.avcodec_find_decoder(audiostream.codec.codec_id)
	if acodec == nil then
		libav.avformat.avformat_close_input(tempfmtctx)
		error("Failed to load audio: no suitable codec found", 2)
	end

	acctx = libav.avcodec.avcodec_alloc_context3(acodec)
	if libav.avcodec.avcodec_copy_context(acctx, audiostream.codec) < 0 then
		deleteCodecContext(acctx)
		libav.avformat.avformat_close_input(tempfmtctx)
		error("Failed to load audio: avcodec_copy_context failed", 2)
	end

	if libav.avcodec.avcodec_open2(acctx, acodec, nil) < 0 then
		deleteCodecContext(acctx)
		libav.avformat.avformat_close_input(tempfmtctx)
		error("Failed to load audio: avcodec_open2 failed", 2)
	end

	SwrCtx = ffi.new("SwrContext*[1]")
	SwrCtx[0] = libav.swresample.swr_alloc_set_opts(nil,
		3,
		"AV_SAMPLE_FMT_S16",
		44100,
		audiostream.codec.channel_layout,
		audiostream.codec.sample_fmt,
		audiostream.codec.sample_rate,
		0, nil
	)

	if libav.swresample.swr_init(SwrCtx[0]) < 0 then
		deleteCodecContext(acctx)
		libav.avformat.avformat_close_input(tempfmtctx)
		error("Failed to load audio: swresample init failed", 2)
	end

	aframe = libav.avutil.av_frame_alloc()
	-- If there's video stream that means there's cover art
	if vididx then
		videostream = tempfmtctx[0].streams[vididx]
		vcodec = libav.avcodec.avcodec_find_decoder(videostream.codec.codec_id)

		if vcodec then
			vcctx = libav.avcodec.avcodec_alloc_context3(vcodec)

			if libav.avcodec.avcodec_copy_context(vcctx, videostream.codec) >= 0 then
				if libav.avcodec.avcodec_open2(vcctx, vcodec, nil) >= 0 then
					-- Allocate image
					vframe = libav.avutil.av_frame_alloc()
					vframergb = libav.avutil.av_frame_alloc()
					vimgdt = love.image.newImageData(vcctx.width, vcctx.height)

					libav.avutil.av_image_fill_arrays(
						vframergb.data,
						vframergb.linesize,
						ffi.cast("uint8_t*", vimgdt:getPointer()), -- Use LOVE ImageData directly
						"AV_PIX_FMT_RGBA",
						vcctx.width,
						vcctx.height, 1
					)
					SwsCtx = libav.swscale.sws_getContext(
						vcctx.width,
						vcctx.height,
						vcctx.pix_fmt,
						vcctx.width,
						vcctx.height,
						"AV_PIX_FMT_RGBA",		-- Don't forget that ImageData expects RGBA values
						2, 						-- SWS_BILINEAR
						nil, nil, nil
					)
				else
					-- Cannot open codec. Just ignore it.
					deleteCodecContext(vcctx)
					vididx = nil
				end
			else
				-- Cannot copy context. Just ignore it.
				deleteCodecContext(vcctx)
				vididx = nil
			end
		end
	end

	-- Init SoundData
	local samplecount_love = math.ceil((tonumber(tempfmtctx[0].duration) / 1000000 + 1) * 44100)
	local sounddata = love.sound.newSoundData(samplecount_love, 44100, 16, 2)

	local framefinished = ffi.new("int[1]")
	local packet = ffi.new("AVPacket[1]")
	local outbuf = ffi.new("uint8_t*[2]")
	local out_size = samplecount_love
	outbuf[0] = ffi.cast("uint8_t*", sounddata:getPointer())

	-- Decode audio and cover art image
	local readframe = libav.avformat.av_read_frame(tempfmtctx[0], packet)
	while readframe >= 0 do
		if packet[0].stream_index == audioidx then
			local decodelen = libav.avcodec.avcodec_decode_audio4(acctx, aframe, framefinished, packet)

			if decodelen < 0 then
				deleteFrame(aframe)
				libav.avcodec.av_free_packet(packet)
				libav.swresample.swr_free(SwrCtx)
				deleteCodecContext(acctx)

				if vididx then
					libav.swscale.sws_freeContext(SwsCtx)
					deleteFrame(vframe)
					deleteFrame(vframergb)
					deleteCodecContext(vcodec)
				end

				libav.avformat.avformat_close_input(tempfmtctx)
				error("Failed to load audio: decoding error", 2)
			end

			if framefinished[0] > 0 then
				local samples = libav.swresample.swr_convert(SwrCtx[0],
					outbuf, aframe.nb_samples,
					ffi.cast("const uint8_t**", aframe.extended_data),
					aframe.nb_samples
				)

				if samples < 0 then
					deleteFrame(aframe)
					libav.avcodec.av_free_packet(packet)
					libav.swresample.swr_free(SwrCtx)
					deleteCodecContext(acctx)

					if vididx then
						libav.swscale.sws_freeContext(SwsCtx)
						deleteFrame(vframe)
						deleteFrame(vframergb)
						deleteCodecContext(vcctx)
					end

					libav.avformat.avformat_close_input(tempfmtctx)
					error("Failed to load audio: resample error", 2)
				end

				outbuf[0] = outbuf[0] + samples * 4
				out_size = out_size - samples
			end
		elseif vididx and packet[0].stream_index == vididx then
			libav.avcodec.avcodec_decode_video2(vcctx, vframe, framefinished, packet)

			if framefinished[0] > 0 then
				-- Cover art decoded
				libav.swscale.sws_scale(SwsCtx,
					ffi.cast("const uint8_t *const *", vframe.data),
					vframe.linesize, 0, vcctx.height,
					vframergb.data, vframergb.linesize
				)

				-- Cannot use `love.graphics.newImage` directly here
				-- Because `love.window` is not loaded yet when the audio is loaded
				output.coverArt = vimgdt
				libav.swscale.sws_freeContext(SwsCtx)
				deleteFrame(vframe)
				deleteFrame(vframergb)
				deleteCodecContext(vcctx)
				vididx = nil
			end
		end

		libav.avcodec.av_free_packet(packet)
		readframe = libav.avformat.av_read_frame(tempfmtctx[0], packet)
	end

	-- Flush buffer
	libav.swresample.swr_convert(SwrCtx[0], outbuf, out_size, nil, 0)

	-- Free
	deleteFrame(aframe)
	libav.avcodec.av_free_packet(packet)
	libav.swresample.swr_free(SwrCtx)
	deleteCodecContext(acctx)
	libav.avformat.avformat_close_input(tempfmtctx)

	return sounddata, output
end

--[[
RE:LÖVisual visualizer script is Lua script placed in the visualizer folder
with name "init.lua". Little example about RE:LÖVisual visualizer script:
local asset = require("asset")
local visualizer = {
	relyz = 01000000 -- Minimum RE:LÖVisual version needed for this visualizer
}

function visualizer.init(arg, metadata, render)
	-- Argument passed from command-line can be fetched from `arg`
	-- The key is the argument option.
	-- Initialize your visualizer here. All LOVE functions can be used.
	-- "metadata" is the song metadata, processed by libavformat.
	-- Note that the fields inside the table can be nil.
	-- Example, metadata.artist is the artist name.
	-- Example, metadata.coverArt is the "ImageData" of the cover art!
	-- "render" is true if the visualizer is being rendered to video file.
	return {
		-- Samples needed for this visualizer ("pot")
		-- Defaults to 1024 if none specified
		samples = 1024,
		-- Is FFT data needed for this visualizer?
		-- Defaults to false
		fft = false or true,
	}
end

function visualizer.update(dt, data)
	-- Update your visualizer data here.
	-- "dt" is the time elapsed between frame.
	-- "data" is the visualizer data. Note that this is FFI struct
	-- so "nil" checking must be done with `if value ~= nil then`
	-- instead of simple `if value then`.
	-- Data struct definition in C is:
	struct visualizerData
	{
		// Waveform data. Normalized in range of -1...1
		// It's in waveform[channel][sample];
		// Where channel = 1 for left, channel = 2 for right.
		// Never be null
		const double waveform[2][samples];
		// Spectrum data (magnitude of FFT result).
		// Normalized in range of -1...1
		// Can be null depending on "fft" setting above in
		// visualizer.load
		const double fft[samples/2];
	} data;
	-- Despite beig FFI data, you still use 1-based indexing
	-- to the data, be careful!
end

function visualizer.draw()
	-- Draw your visualizer here.
	-- Visualizer is drawn in 3840x2160 canvas, but uses
	-- 1280x720 logical resolution. The window size is
	-- 1216x684.
	-- It's your responsibility not to mess up the LOVE graphics state
	-- (example unbalanced push/pop)
end

return visualizer -- This is important!
]]

--- Load RE:LÖVisualizer with specified name
-- @tparam string name Visualizer name.
-- @tparam table arg Program argument.
function relyz.loadVisualizer(name, arg)
	-- Visualizer is stored in `relyz` folder in the save directory
	-- When visualizer is loaded, the window is assumed has been created
	-- so `love.graphics` module can be used (and must be available)
	local path = "relyz/"..name.."/"
	if love.filesystem.getInfo(path, "directory") and love.filesystem.getInfo(path.."init.lua", "file") then
		-- Preload asset loader
		package.preload.asset = function()
			return {
				-- Return LOVE Image object
				loadImage = function(a, ...)
					return love.graphics.newImage(path..a, ...)
				end,
				-- Return LOVE Image object
				loadUserImage = function(a, ...)
					local x = assert(io.open(a, "rb"))
					local img = love.graphics.newImage(
						love.filesystem.newFileData(x:read("*a"), a),
						...
					)
					x:close()
					return img
				end,
				-- Return LOVE File object
				loadFile = function(a, ...)
					return love.filesystem.newFile(path..a, ...)
				end,
				-- Return LOVE Font object
				loadFont = function(a, size)
					return love.graphics.newFont(path..a, size)
				end,
				-- Return Lua chunk (but not running yet)
				loadScript = function(a)
					return love.filesystem.load(path..a)
				end,
				-- Return the file content as string
				readFile = function(a)
					return love.filesystem.read(path..a)
				end,
				-- Return the file content as string
				readUserFile = function(a)
					local x = assert(io.open(a, "rb"))
					local y = x:read("*a") x:close()
					return y
				end
			}
		end
		-- Load visualizer
		relyz.visualizer = assert(love.filesystem.load(path.."init.lua"))()
		assert(
			relyz.visualizer.relyz and relyz.visualizer.relyz >= relyz.VERSION_NUMBER or not(relyz.visualizer.relyz),
			"Visualizer version not satisfied"
		)
		local data = relyz.visualizer.init(arg, relyz.songMetadata, relyz.isRender)
		-- Set information & allocate data
		relyz.neededSamples = data.samples or 1024
		-- Needed samples must be pot
		assert(relyz.neededSamples > 0, "Needed samples must be greater than 0")
		assert(bit.band(relyz.neededSamples, relyz.neededSamples - 1) == 0, "Needed samples must be pot")
		relyz.waveformLeft = ffi.new("double[?]", relyz.neededSamples + 1)
		relyz.waveformRight = ffi.new("double[?]", relyz.neededSamples + 1)
		relyz.waveform = ffi.new("double*[3]")
		relyz.waveform[1] = relyz.waveformLeft
		relyz.waveform[2] = relyz.waveformRight
		-- If FFT is set, then allocate needed data
		if data.fft then
			-- Initialize FFTW needed data and FFTW plan
			relyz.fftSignal = ffi.new("fftw_complex[?]", relyz.neededSamples)
			relyz.fftResult = ffi.new("fftw_complex[?]", relyz.neededSamples)
			relyz.fftPlan = fftw.plan_dft_1d(
				relyz.neededSamples,
				relyz.fftSignal,
				relyz.fftResult,
				fftw.FORWARD,
				fftw.ESTIMATE
			)
			relyz.fftAmplitude = ffi.new("double[?]", 0.5 * relyz.neededSamples + 1)
			-- Calculate window coefficients
			relyz.window = ffi.new("double[?]", relyz.neededSamples)
			for i = 1, relyz.neededSamples do
				local j = i - 1
				relyz.window[j] = 0.5 * (1.0 - math.cos(2*math.pi * j / (relyz.neededSamples-1)))
			end
		end
	else
		error("Failed to load visualizer: "..name, 2)
	end
end

relyz.visualizerData = ffi.new([[struct {
	const double *waveform[3];
	const double *fft;
}]])
local Sqrt2 = math.sqrt(2)
function relyz.updateVisualizer(dt, sound, pos)
	local smpLen = sound:getSampleCount()
	local maxSmp = math.min(pos + relyz.neededSamples, smpLen) - 1

	-- Reinitialize struct
	relyz.visualizerData.waveform[1] = nil
	relyz.visualizerData.waveform[2] = nil
	relyz.visualizerData.fft = nil
	-- Copy samples
	local j = 0
	for i = pos, maxSmp do
		local l, r = sound:getSample(i, 1), sound:getSample(i, 2)
		local fin = (l + r) * 0.5 * relyz.window[j]
		relyz.waveformLeft[j + 1] = l
		relyz.waveformRight[j + 1] = r
		relyz.fftSignal[j][0], relyz.fftSignal[j][1] = fin, fin
		j = j + 1
	end
	-- Zero rest
	for _ = maxSmp + 1, pos + relyz.neededSamples - 1 do
		relyz.waveformLeft[j + 1], relyz.waveformRight[j + 1] = 0, 0
		relyz.fftSignal[j][0], relyz.fftSignal[j][1] = 0, 0
		j = j + 1
	end
	-- Set data
	relyz.visualizerData.waveform[1] = relyz.waveformLeft
	relyz.visualizerData.waveform[2] = relyz.waveformRight

	-- If FFT is set, calculate FFT
	if relyz.fftPlan ~= nil then
		fftw.execute(relyz.fftPlan)
		for i = 1, relyz.neededSamples * 0.5 do
			local d = relyz.fftResult[i - 1]
			-- The last division is "normalizing" part
			relyz.fftAmplitude[i] = math.sqrt(d[0] * d[0] + d[1] * d[1]) / ((relyz.neededSamples * 0.5) / Sqrt2)
		end
		-- Set struct data
		relyz.visualizerData.fft = relyz.fftAmplitude
	end

	-- Send update data to visualizer
	return relyz.visualizer.update(dt, relyz.visualizerData)
end

--- Verifies the existence of encoder.
-- @treturn string Error message (or nil if libav is satisfied)
function relyz.verifyEncoder()
	local oc = ffi.new("AVFormatContext*[1]")

	-- Check matroska muxer
	local v = libav.avformat.avformat_alloc_output_context2(oc, nil, "matroska", nil)
	if v >= 0 then
		libav.avformat.avformat_free_context(oc[0])
		oc[0] = nil
	else
		return "Matroska muxer cannot be initialized!"
	end

	-- Check AAC encoder
	--[[
	local test = libav.avcodec.avcodec_find_encoder("AV_CODEC_ID_AAC")
	if test == nil then
		return "No AAC encoder. Make sure to build FFmpeg with at least native AAC encoder!"
	end
	]]

	-- Check libx264
	local test = libav.avcodec.avcodec_find_encoder_by_name("libx264")
	if test == nil then
		return "libx264 encoder not found. Make sure to build FFmpeg with libx264 support!"
	end

	return nil
end

-- Internal function to set AVRational
local function toAVRational(v, n, d)
	v.num, v.den = n, d
end

function relyz.initializeEncoder(output)
	-- Encoder table
	relyz.enc = {frameCount = 0}

	-- Alloc new format context
	relyz.enc.formatContextP = ffi.new("AVFormatContext*[1]")
	if libav.avformat.avformat_alloc_output_context2(relyz.enc.formatContextP, nil, "matroska", output) < 0 then
		error("Cannot alloc output context", 2)
	end
	local enc = relyz.enc.formatContextP[0]
	do
		local pbref = ffi.new("AVIOContext*[1]")
		pbref[0] = enc.pb
        if libav.avformat.avio_open(pbref, output, 2) < 0 then
            error("Could not open output file", 2)
		end
    end

	-- Add x264 encoder
	local x264encoder = libav.avcodec.avcodec_find_encoder_by_name("libx264")
	relyz.enc.stream = libav.avformat.avformat_new_stream(enc, x264encoder)
	toAVRational(relyz.enc.stream.time_base, 1, 60) -- 60 FPS
	-- Codec context setup
	--relyz.enc.codecContext = libav.avcodec.avcodec_alloc_context3(x264encoder)
	relyz.enc.codecContext = relyz.enc.stream.codec
	--libav.avutil.av_opt_set_defaults(relyz.enc.codecContext)
	relyz.enc.codecContext.width = relyz.canvasWidth
	relyz.enc.codecContext.height = relyz.canvasHeight
	relyz.enc.codecContext.gop_size = 60
	relyz.enc.codecContext.pix_fmt = "AV_PIX_FMT_YUV444P"
	toAVRational(relyz.enc.codecContext.time_base, 1, 60) -- 60 FPS
	libav.avutil.av_opt_set_int(relyz.enc.codecContext, "crf", 0, 1)
	libav.avutil.av_opt_set(relyz.enc.codecContext, "preset", "medium", 1)

	-- Open codec & initialize codec context
	if libav.avcodec.avcodec_open2(relyz.enc.codecContext, x264encoder, nil) < 0 then
		--deleteCodecContext(relyz.enc.codecContext)
		libav.avformat.avformat_free_context(relyz.enc.formatContextP)
		error("Cannot open codec", 2)
	end

	-- Create new frame
	relyz.enc.frame = libav.avutil.av_frame_alloc()
	relyz.enc.frame.width = relyz.canvasWidth
	relyz.enc.frame.height = relyz.canvasHeight
	relyz.enc.frame.format = ffi.cast("int", relyz.enc.codecContext.pix_fmt)
	libav.avutil.av_image_alloc(
		relyz.enc.frame.data,
		relyz.enc.frame.linesize,
		relyz.canvasWidth,
		relyz.canvasWidth,
		relyz.enc.codecContext.pix_fmt, 32
	)

	-- Create sws context
	relyz.enc.swsCtx = libav.swscale.sws_getContext(
		relyz.canvasWidth,
		relyz.canvasWidth,
		"AV_PIX_FMT_RGBA",
		relyz.canvasWidth,
		relyz.canvasWidth,
		relyz.enc.codecContext.pix_fmt,
		2, 						-- SWS_BILINEAR
		nil, nil, nil
	)
	if relyz.enc.swsCtx == nil then
		libav.avutil.av_freep(relyz.enc.frame.data)
		deleteFrame(relyz.enc.frame)
		--deleteCodecContext(relyz.enc.codecContext)
		libav.avformat.avformat_free_context(relyz.enc.formatContextP)
		error("swscale init failed", 2)
	end

	-- Create packet
	relyz.enc.packet = ffi.new("AVPacket[1]")

	-- Write header. Call init output
	local ret = libav.avformat.avformat_init_output(enc, nil)
	if ret == 0 then
		-- Initialize in header. Call write header
		ret = libav.avformat.avformat_write_header(enc, nil)
	end
	if ret < 0 then
		-- Error
		libav.avutil.av_freep(relyz.enc.frame.data)
		deleteFrame(relyz.enc.frame)
		--deleteCodecContext(relyz.enc.codecContext)
		libav.avformat.avformat_free_context(relyz.enc.formatContextP)
		error("Header write failed", 2)
	end
	libav.avformat.av_dump_format(enc, 0, output, 1)

	relyz.enc.tempData = ffi.new("__declspec(align(32)) struct {uint8_t *data[8]; int linesize[8];}")
	relyz.enc.tempData.linesize[0] = relyz.canvasHeight * 4
end

-- This function must be called for encoding
function relyz.supplyEncoder(imagePointer)
	local gotImg = ffi.new("int[1]")
	-- Colorspace conversion
	relyz.enc.tempData.data[0] = ffi.cast("uint8_t*", imagePointer)
	libav.swscale.sws_scale(relyz.enc.swsCtx,
		ffi.cast("const uint8_t *const *", relyz.enc.tempData.data),
		relyz.enc.tempData.linesize, 0, relyz.canvasHeight,
		relyz.enc.frame.data, relyz.enc.frame.linesize
	)
	-- Init packet
	libav.avcodec.av_init_packet(relyz.enc.packet)
	relyz.enc.packet[0].data = nil
	relyz.enc.packet[0].size = 0
	relyz.enc.frame.pts = relyz.enc.frameCount

	-- Encode video
	if libav.avcodec.avcodec_encode_video2(relyz.enc.codecContext, relyz.enc.packet, relyz.enc.frame, gotImg) < 0 then
		-- Error
		libav.avutil.av_freep(relyz.enc.frame.data)
		deleteFrame(relyz.enc.frame)
		--deleteCodecContext(relyz.enc.codecContext)
		libav.avformat.avformat_free_context(relyz.enc.formatContextP)
		error("Encode failed", 2)
	elseif gotImg[0] == 1 then
		-- Ok got frame. Write the packet
		print("write", relyz.enc.packet[0].stream_index)
		libav.avcodec.av_packet_rescale_ts(relyz.enc.packet, relyz.enc.codecContext.time_base, relyz.enc.stream.time_base)
		libav.avformat.av_interleaved_write_frame(relyz.enc.formatContextP[0], relyz.enc.packet[0])
		print("av_interleaved_write_frame")
		libav.avcodec.av_packet_unref(relyz.enc.packet)
		print("write ok")
	end

	-- Increase frame counter
	relyz.enc.frameCount = relyz.enc.frameCount + 1
end

-- On encode done or quit requested.
function relyz.doneEncode()
	-- Send flush packet
	libav.avcodec.avcodec_send_frame(relyz.enc.codecContext, nil)
	if libav.avcodec.avcodec_receive_packet(relyz.enc.codecContext, relyz.enc.packet) == 0 then
		-- Ok got frame. Write the packet
		libav.avformat.av_interleaved_write_frame(relyz.enc.formatContextP[0], relyz.enc.packet[0])
		libav.avcodec.av_packet_unref(relyz.enc.packet)
	end

	-- Write trail header
	libav.avformat.av_write_trailer(relyz.enc.formatContextP[0])
	-- Free resource
	libav.avutil.av_freep(relyz.enc.rgbaFrame.data)
	deleteFrame(relyz.enc.rgbaFrame)
	libav.avutil.av_freep(relyz.enc.frame.data)
	deleteFrame(relyz.enc.frame)
	--deleteCodecContext(relyz.enc.codecContext)
	libav.avformat.avformat_free_context(relyz.enc.formatContextP)
	-- Done.
	relyz.enc = nil
end

return relyz
