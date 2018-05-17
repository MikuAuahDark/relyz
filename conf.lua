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
local relyz = require("relyz")
assert(love._os ~= "Android" and love._os ~= "iOS", "Mobile device doesn't have enough power to run this")
assert(jit and jit.status(), "LuaJIT is required & JIT compiler must be turned on")

-- The actual canvas size
relyz.canvasWidth = 3840
relyz.canvasHeight = 2160
-- The logical screen size for visualizer
relyz.logicalWidth = 1280
relyz.logicalHeight = 720
-- Window size
relyz.windowWidth = 1216
relyz.windowHeight = 684

-- Lock global variable from changes
setmetatable(_G, {
	__index = function(_, var) error("Undefined variable: \""..var.."\"", 2) end,
	__newindex = function(_, var) error("New variable not allowed: \""..var.."\"", 2) end
})

function love.conf(t)
    t.identity = "lovelyzer"
    t.appendidentity = true
    t.version = "11.1"
	t.window = nil

    t.modules.joystick = false
    t.modules.keyboard = false
    t.modules.mouse = false
    t.modules.physics = false
    t.modules.touch = false
    t.modules.video = false
end
