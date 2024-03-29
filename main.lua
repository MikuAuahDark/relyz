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
local relyz = require("relyz")
local ffi = require("ffi")

local main = {time = 0, fpsTimerUpdate = 0, amp = 1}
local usage = [[
Usage: %s [options] songFile visualizer

Options:
  -?, -help, -h          Show this message.
  -r, -render output     Render as video to `output`.
  -canvas <w>x<h>        Set render output to specified dimensions.
  -about                 Show information.
  -<any option> <value>  Other option which may needed by specific visualizer.]]

local about = [[
RE:LOVisual v%s

Copyright (C) 2018 MikuAuahDark

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.]]

assert(love.filesystem.createDirectory("relyz"), "Failed to create directory \"relyz\"")

-- Code for built-in wave generator (debugging purpose)
main.wave = {
	sine = function(f, t)
		return math.sin(2*math.pi * f * t)
	end
}

function main.generateWave(wave, freq, length)
	local smpLen = length * 44100
	local sd = love.sound.newSoundData(smpLen, 44100, 16, 2)
	for i = 1, smpLen do
		local v = main.wave[wave](freq, (i - 1) / 44100)
		sd:setSample(i - 1, 1, v)
		sd:setSample(i - 1, 2, v)
	end

	return sd, {}
end

function main.initializeStereoMix(bufsize)
	local mix
	-- Find stereo mix device
	for _, v in ipairs(love.audio.getRecordingDevices()) do
		if v:getName():lower():find("stereo mix", 1, true) then
			mix = v
			break
		end
	end
	assert(mix, "No Stereo Mix found")
	assert(mix:start(bufsize * 4, 48000, 16, 2), "Failed to record")

	-- Set mix table
	main.mix = {device = mix}
	main.mix.buffer = bufsize
	main.mix.soundData = love.sound.newSoundData(bufsize, 48000, 16, 2)
	main.mix.soundDataPtr = ffi.cast("int32_t*", main.mix.soundData:getPointer())
	main.mix.ffiRing = ffi.new("int32_t[?]", bufsize)
	main.mix.ffiRingPos = 0
	main.audioSampleRate = 48000
end

function main.mixUpdate()
	local capturedSound = main.mix.device:getData()

	-- capturedSound can be nil
	if capturedSound then
		local captureSize = capturedSound:getSampleCount()
		local capturePtr = ffi.cast("int32_t*", capturedSound:getPointer())
		-- Copy data to FFI ring buffer (should invent faster method -_-)
		for i = 0, captureSize - 1 do
			local idx = (i + main.mix.ffiRingPos) % main.mix.buffer
			main.mix.ffiRing[idx] = capturePtr[i]
		end
		-- Copy data to SoundData continuous buffer
		for i = 0, main.mix.buffer - 1 do
			main.mix.soundDataPtr[i] = main.mix.ffiRing[main.mix.ffiRingPos]
			main.mix.ffiRingPos = (main.mix.ffiRingPos + 1) % main.mix.buffer
		end
	end
end

function love.load(argv)
	local parsedArgument = {}

	-- Check encoder satisfication
	local satisfy = relyz.verifyEncoder()
	if satisfy then
		print(satisfy)
	end

	-- Parse argument
	local songFile, visualizer
	do local i = 1 while argv[i] do
		local arg = argv[i]

		-- Help?
		if arg == "-?" or arg == "-help" or arg == "-h" then
			print(string.format(usage, argv[0] or "program"))
			love.event.quit(0) return
		-- About?
		elseif arg == "-about" then
			print(string.format(about, relyz.VERSION))
			love.event.quit(0) return
		-- If argument starts with "-" then it's options
		elseif #arg > 1 and arg:sub(1, 1) == "-" and argv[i + 1] then
			parsedArgument[arg:sub(2)] = argv[i + 1]
			i = i + 1
		-- If it's not, then it's maybe the songFile
		elseif not(songFile) then
			songFile = arg
		-- If it's not the songFile to, then it's probably the visualizer
		elseif not(visualizer) then
			visualizer = arg
		else
			-- Unknown
			print("Ignored", arg)
		end
		i = i + 1
	end end

	-- Check argument
	if not(songFile) then
		print("Missing song file!")
		print(string.format(usage, argv[0] or "program"))
		love.event.quit(1) return
	elseif not(visualizer) then
		print("Missing visualizer!")
		print(string.format(usage, argv[0] or "program"))
		love.event.quit(1) return
	end

	if parsedArgument.canvas then
		local canvasDimension = parsedArgument.canvas:lower()

		if canvasDimension == "720p" or canvasDimension == "hd" then
			relyz.canvasWidth, relyz.canvasHeight = 1280, 720
		elseif canvasDimension == "1080p" or canvasDimension == "2k" or canvasDimension == "fhd" then
			relyz.canvasWidth, relyz.canvasHeight = 1920, 1080
		elseif canvasDimension == "1440p" or canvasDimension == "qhd" then
			relyz.canvasWidth, relyz.canvasHeight = 2560, 1440
		elseif canvasDimension == "4k" then
			relyz.canvasWidth, relyz.canvasHeight = 3840, 2160
		elseif canvasDimension == "8k" then
			relyz.canvasWidth, relyz.canvasHeight = 7680, 4320
		else
			local w, h = parsedArgument.canvas:match("^(%d+)x(%d+)$")
			if w and h then
				relyz.canvasWidth = tonumber(w)
				relyz.canvasHeight = tonumber(h)
			end
		end
	end

	if parsedArgument.amp then
		local amp = tonumber(parsedArgument.amp) or 1
		if amp > 0 then
			main.amp = amp
		end
	end

	-- If song file is somewhat a pattern, then try to use built-in generator
	-- The pattern is: wave:frequency:duration
	if songFile:find("%w+:%d+:%d+$") == 1 then
		local wave, freq, dur = songFile:match("(%w+):(%d+):(%d+)$")
		if main.wave[wave] then
			main.sound, relyz.songMetadata = main.generateWave(wave, freq*1, dur*1) -- * 1 = tonumber
		end
	elseif songFile == "-" then
		-- Stereo mix.
		main.mixMode = true
		relyz.songMetadata = {}
	end

	if not(main.sound) and not(main.mixMode) then
		-- The previous function is unsuccessful, so load it as usual.
		main.sound, relyz.songMetadata = relyz.loadAudio(songFile)
	end

	-- Create window
	local rendering = parsedArgument.r or parsedArgument.render
	love.window.setMode(relyz.windowWidth, relyz.windowHeight, {
		vsync = rendering and 0 or 1
	})
	main.title = "RE:LÖVisual: "..visualizer.." | %d FPS"
	love.window.setTitle(string.format(main.title, 0))
	-- Create canvas
	if not(rendering) then
		relyz.canvasWidth, relyz.canvasHeight = 1280, 720
	end

	main.canvas = love.graphics.newCanvas(relyz.canvasWidth, relyz.canvasHeight)
	main.stencil = love.graphics.newCanvas(relyz.canvasWidth, relyz.canvasHeight, {format = "depth24stencil8"})
	main.canvasInfo = {main.canvas, depthstencil = {main.stencil}}
	-- Load visualizer
	relyz.loadVisualizer(visualizer, parsedArgument)

	-- Attempt to setup the mix mode
	if main.mixMode then
		-- In stereo mix, we don't actually create source
		main.time = -math.huge
		main.initializeStereoMix(relyz.neededSamples)
		main.sound = main.mix.soundData
		main.audioDuration = math.huge
	else
		-- Create audio source
		main.audio = love.audio.newSource(main.sound)
		main.audioDuration = main.audio:getDuration()
	end

	if parsedArgument.r or parsedArgument.render then
		assert(not(main.mixMode), "Render cannot be used when reading stereo mix")
		local out = parsedArgument.r or parsedArgument.render
		relyz.initializeEncoder(out)
		main.audioPosition = 0
		main.audioLength = main.sound:getSampleCount()
		main.audioSampleRate = main.sound:getSampleRate()
	elseif not(main.mixMode) then
		-- Play audio if not in encode mode
		main.audioPosition = 0
		main.audioSampleRate = main.sound:getSampleRate()
		main.audioLength = main.sound:getSampleCount()
		main.audio:play()
	end
end

function love.quit()
	if relyz.enc then
		relyz.doneEncode()
	end
end

function love.update(dT)
	if main.time >= main.audioDuration then
		-- Exit
		love.event.quit(0) return
	end
	-- Update
	local adT = relyz.enc and 1/60 or dT
	if main.mixMode then main.mixUpdate() end

	relyz.updateVisualizer(adT, main.sound, relyz.enc and math.floor(main.audioPosition) or (main.audio and main.audio:tell("samples") or 0), main.amp)

	main.time = main.time + adT
	main.fpsTimerUpdate = main.fpsTimerUpdate + dT

	if main.audioPosition then
		main.audioPosition = math.min(main.audioLength, main.audioPosition + main.audioSampleRate * adT)
	end

	while main.fpsTimerUpdate >= 1 do
		love.window.setTitle(string.format(main.title, love.timer.getFPS()))
		main.fpsTimerUpdate = main.fpsTimerUpdate - 1
	end
end

function love.draw()
	love.graphics.push("all")
	love.graphics.setCanvas(main.canvasInfo)
	love.graphics.clear(0, 0, 0, 1)
	love.graphics.scale(
		relyz.canvasWidth / relyz.logicalWidth,
		relyz.canvasHeight / relyz.logicalHeight
	)
	relyz.visualizer.draw()
	love.graphics.pop()
	love.graphics.draw(
		main.canvas, 0, 0, 0,
		relyz.windowWidth / relyz.canvasWidth,
		relyz.windowHeight / relyz.canvasHeight
	)

	-- Canvas pointer supply to encoder
	if relyz.enc then
		local imageData = main.canvas:newImageData()
		relyz.supplyEncoder(imageData:getPointer())
		imageData:release()
	end
end
