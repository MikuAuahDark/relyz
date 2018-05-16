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
local ffi = require("ffi")
local relyz = {}

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

-- Helper function to free AVFrame
local function deleteFrame(frame)
	local x = ffi.new("AVFrame*[1]")
	x[0] = frame libav.avutil.av_frame_free(x)
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
		error("Failed to load audio: failed to load file", 2)
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
		libav.avcodec.avcodec_close(acctx)
		libav.avformat.avformat_close_input(tempfmtctx)
		error("Failed to load audio: avcodec_copy_context failed", 2)
	end

	if libav.avcodec.avcodec_open2(acctx, acodec, nil) < 0 then
		libav.avcodec.avcodec_close(acctx)
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
		libav.avcodec.avcodec_close(acctx)
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
					libav.avcodec.avcodec_close(vcctx)
					vididx = nil
				end
			else
				-- Cannot copy context. Just ignore it.
				libav.avcodec.avcodec_close(vcctx)
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
				libav.avcodec.avcodec_close(acctx)

				if vididx then
					libav.swscale.sws_freeContext(SwsCtx)
					deleteFrame(vframe)
					deleteFrame(vframergb)
					libav.avcodec.avcodec_close(vcodec)
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
					libav.avcodec.avcodec_close(acctx)

					if vididx then
						libav.swscale.sws_freeContext(SwsCtx)
						deleteFrame(vframe)
						deleteFrame(vframergb)
						libav.avcodec.avcodec_close(vcctx)
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
				libav.avcodec.avcodec_close(vcctx)
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
	libav.avcodec.avcodec_close(acctx)
	libav.avformat.avformat_close_input(tempfmtctx)

	return sounddata, output
end
