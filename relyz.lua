-- RE:LÖVisual
-- Copyright (C) 2020 MikuAuahDark
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
local ls2x = require("ls2x")
local relyz = {
	-- Uses livesim2 version convention
	VERSION_NUMBER = 01010000,
	VERSION = "1.1.0",
}

assert(ls2x.libav, "need LS2X libav capabilities")

--- Load audio from system-dependent path
-- This function uses FFmpeg API (libav) to load audio.
-- @tparam string path Audio path
-- @treturn SoundData Audio sound data
-- @treturn table Audio metadata (audio cover can be accessed in `coverArt` field)
function relyz.loadAudio(path)
	local info = assert(ls2x.libav.loadAudioFile(path), "failed to load "..path)
	local metadata = {}
	-- copy metadata
	for k, v in pairs(info.metadata) do
		metadata[k] = v
	end
	-- new sound data
	local soundData = love.sound.newSoundData(tonumber(info.sampleCount), tonumber(info.sampleRate), 16, 2)
	ffi.copy(soundData:getPointer(), info.samples, info.sampleCount * 4)
	ls2x.libav.free(info.samples)
	-- if cover art available
	if info.coverArt then
		local imageData = love.image.newImageData(info.coverArt.width, info.coverArt.height)
		ffi.copy(imageData:getPointer(), info.coverArt.data, info.coverArt.width * info.coverArt.height * 4)
		ls2x.libav.free(info.coverArt.data)
		metadata.coverArt = imageData
	end

	return soundData, metadata
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
			relyz.visualizer.relyz and relyz.VERSION_NUMBER >= relyz.visualizer.relyz or not(relyz.visualizer.relyz),
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
	if relyz.window then
		for i = pos, maxSmp do
			local l, r = sound:getSample(i, 1), sound:getSample(i, 2)
			local fin = (l + r) * 0.5 * relyz.window[j]
			relyz.waveformLeft[j + 1] = l
			relyz.waveformRight[j + 1] = r
			relyz.fftSignal[j][0], relyz.fftSignal[j][1] = fin, fin
			j = j + 1
		end
		for _ = maxSmp + 1, pos + relyz.neededSamples - 1 do
			relyz.waveformLeft[j + 1], relyz.waveformRight[j + 1] = 0, 0
			relyz.fftSignal[j][0], relyz.fftSignal[j][1] = 0, 0
			j = j + 1
		end
	else
		for i = pos, maxSmp do
			local l, r = sound:getSample(i, 1), sound:getSample(i, 2)
			relyz.waveformLeft[j + 1] = l
			relyz.waveformRight[j + 1] = r
			j = j + 1
		end
		for _ = maxSmp + 1, pos + relyz.neededSamples - 1 do
			relyz.waveformLeft[j + 1], relyz.waveformRight[j + 1] = 0, 0
			j = j + 1
		end
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
	if ls2x.libav.startEncodingSession then
		return nil
	else
		return "LS2X does not support encoding"
	end
end

function relyz.initializeEncoder(out)
	relyz.enc = assert(ls2x.libav.startEncodingSession(out, relyz.canvasWidth, relyz.canvasHeight, 60), "cannot initialize encoding session")
end

-- This function must be called for encoding
function relyz.supplyEncoder(imagePointer)
	assert(ls2x.libav.supplyVideoEncoder(imagePointer), "failed to supply data to encoder")
end

-- On encode done or quit requested.
function relyz.doneEncode()
	ls2x.libav.endEncodingSession()
	relyz.enc = nil
end

return relyz
