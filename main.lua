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

local relyz = require("relyz")
local main = {time = 0}
local usage = [[
Usage: %s [options] songFile visualizer

Options:
  -?, -help, -h          Show this message.
  -r, -render output     Render as video to `output`.
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
		elseif arg:sub(1, 1) == "-" and argv[i + 1] then
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

	-- If song file is somewhat a pattern, then try to use built-in generator
	-- The pattern is: wave:frequency:duration
	if songFile:find("%w+:%d+:%d+$") == 1 then
		local wave, freq, dur = songFile:match("(%w+):(%d+):(%d+)$")
		if main.wave[wave] then
			main.sound, relyz.songMetadata = main.generateWave(wave, freq*1, dur*1) -- * 1 = tonumber
		end
	end

	if not(main.sound) then
		-- The previous function is unsuccessful, so load it as usual.
		main.sound, relyz.songMetadata = relyz.loadAudio(songFile)
	end
	main.audio = love.audio.newSource(main.sound)
	-- Create window
	love.window.setMode(relyz.windowWidth, relyz.windowHeight)
	main.title = "RE:LÖVisual: "..visualizer.." | %d FPS"
	love.window.setTitle(string.format(main.title, 0))
	-- Create canvas
	main.canvas = love.graphics.newCanvas(relyz.canvasWidth, relyz.canvasHeight)
	-- Load visualizer
	relyz.loadVisualizer(visualizer, parsedArgument)
	main.audioDuration = main.audio:getDuration()
	if parsedArgument.r or parsedArgument.render then
		local out = parsedArgument.r or parsedArgument.render
		relyz.initializeEncoder(out)
	else
		-- Play audio if not in encode mode
		main.audio:play()
	end
end

function love.quit()
	print("love quit")
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
	relyz.updateVisualizer(adT, main.sound, main.audio:tell("samples"))
	main.time = main.time + adT
end

function love.draw()
	love.graphics.push("all")
	love.graphics.setCanvas(main.canvas)
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
	love.window.setTitle(string.format(main.title, love.timer.getFPS()))

	-- Canvas pointer supply to encoder
	if relyz.enc then
		local imageData = main.canvas:newImageData()
		relyz.supplyEncoder(imageData:getPointer())
		imageData:release()
	end
end
