--
-- Lua Debugger
-- By Alex "Colonel Thirty Two" Parrill
-- 
--
--
-- This is free and unencumbered software released into the public domain.
-- 
-- Anyone is free to copy, modify, publish, use, compile, sell, or
-- distribute this software, either in source code form or as a compiled
-- binary, for any purpose, commercial or non-commercial, and by any
-- means.
-- 
-- In jurisdictions that recognize copyright laws, the author or authors
-- of this software dedicate any and all copyright interest in the
-- software to the public domain. We make this dedication for the benefit
-- of the public at large and to the detriment of our heirs and
-- successors. We intend this dedication to be an overt act of
-- relinquishment in perpetuity of all present and future rights to this
-- software under copyright law.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
-- OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
-- ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
-- OTHER DEALINGS IN THE SOFTWARE.

-- Detect LuaJIT
local jit
do
	local hasjit, ajit = pcall(require, "jit")
	if hasjit then jit = ajit end
end

local Debugger = {}

local commands = {}
do
	commands["bt"] = {
		shortdesc = "Prints a stack trace",
		longdesc  = "Runs debug.traceback on the debugged code.",
		func = function(argstr, stackoffset)
			io.write(debug.traceback("",stackoffset):sub(2),"\n")
		end,
	}
	
	commands["trace"] = commands["bt"]
	commands["backtrace"] = commands["bt"]
	commands["traceback"] = commands["bt"]
	
	commands["help"] = {
		shortdesc = "Prints help",
		func = function(argstr, stackoffset)
			if argstr and commands[argstr] then
				io.write(commands[argstr].longdesc or commands[argstr].shortdesc, "\n")
			else
				for cmd, tbl in pairs(commands) do
					io.write(cmd, string.rep(" ", math.max(20-#cmd, 1)), "- ", tbl.shortdesc, "\n")
				end
			end
		end,
	}
	
	commands["exit"] = {
		shortdesc = "Exits the debugger",
		longdesc  = "Exits the debugger and continues execution.",
		func = function(argstr, stackoffset)
			return true
		end,
	}
end

local function debugger_loop(stackoffset)
	stackoffset = stackoffset or 3
	
	io.write(">>> Entering debugger\n")
	while true do
		-- Get and print the line of code we are on
		local info = debug.getinfo(stackoffset, "nSlu")
		assert(info, "Invalid stackoffset passed to debugger_loop")
		io.write(info.short_src, ":", info.currentline, "> ")
		local cmdstr = io.read("*l")
		local cmd, args = cmdstr:match("^([^%s]+)%s*(.-)$")
		
		if not cmd then
			io.write("Bad command\n")
		elseif not commands[cmd] then
			io.write("Unknown command\n")
		elseif commands[cmd].func(args, stackoffset+1) then
			break
		end
	end
end

function Debugger.pause()
	debugger_loop()
end

return Debugger
