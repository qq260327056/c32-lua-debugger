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

--- Counts the size of the stack, in number of functions called (not including
-- this function call)
local function countStack()
	local i = 2
	while debug.getinfo(i, 'u') do
		i = i + 1
	end
	return i-2
end

local commands = {}

local function debugger_loop(stackoffset, message)
	stackoffset = stackoffset or 3
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
	
	commands["locals"] = {
		shortdesc = "Prints local vars",
		longdesc = "Prints out all local variables in a function. Optionally takes a stack offset.",
		func = function(argstr, stackoffset)
			stackoffset = stackoffset + (tonumber(argstr) or 1) - 1
			local i = 1
			while true do
				local name, val = debug.getlocal(stackoffset, i)
				if not name then break end
				io.write(name, string.rep(" ", math.max(20-#name, 1)), "= ", tostring(val), "\n")
				i = i + 1
			end
		end,
	}
	commands["vars"] = commands["locals"]
	
	commands["next"] = {
		shortdesc = "Resumes execution for one line, not going into function calls",
		func = function(argstr, stackoffset)
			-- If we get a line executed event and our stack count is equal or less than it was,
			-- break. If it is greater, we are in a called function.
			local stackcount = countStack() - stackoffset + 2
			debug.sethook(function(event, linenum)
				local thislevel = countStack()
				if thislevel <= stackcount then
					debug.sethook(nil)
					debugger_loop()
				end
			end, "l")
			return true
		end
	}
	commands["n"] = commands["next"]

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

--- Pauses the script and enters the debug shell, similar to hitting a breakpoint
function Debugger.pause()
	io.write(">>> Debugger.pause()\n")
	debugger_loop()
end

--- Sets up the debug hook so that it can catch breakpoints.
-- You should call this as soon as you start the script.
-- For LuaJIT users, luajit -jdebugger <script> should also work.
function Debugger.start()

end

return Debugger
