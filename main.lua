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
local usage = [[
Usage: %s [options] songFile visualizer

Options:
  -?, -help, -h          Show this message.
  -r, -render output     Render as video to `output`.
  -<any option> <value>  Other option which may needed by specific visualizer.]]

function love.load(argv)
	local parsedArgument = {}

	-- Parse argument
	local songFile, visualizer
	do local i = 1 while argv[i] do
		local arg = argv[i]

		-- Help?
		if arg == "-?" or arg == "-help" or arg == "-h" then
			print(string.format(usage, argv[0] or "program"))
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

	if not(songFile) then
		print("Missing song file!")
		print(string.format(usage, argv[0] or "program"))
		love.event.quit(1) return
	elseif not(visualizer) then
		print("Missing visualizer!")
		print(string.format(usage, argv[0] or "program"))
		love.event.quit(1) return
	end
	love.event.quit(1) return
end

function love.update(dT)
end

function love.draw()
end
