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
	if hasjit then
		jit = ajit
		jit.off()
	end
end

-- Forward declare some tables and functions.
local Debugger = {}
local commands = {}
local breakpoints = {}

local debugger_loop
local breakpoints_hook

-- ------------------------------------------------------------------------------------------
-- Helper functions

--- Counts the size of the stack, in number of functions called (not including
-- this function call)
local function count_stack()
	local i = 2
	while debug.getinfo(i, 'u') do
		i = i + 1
	end
	return i-2
end

--- Transforms a path name into a less-ambiguous format.
-- IE: stripping the '@./' prefix
local function transform_filename(line)
	if line:sub(1,1) == "@" then
		line = line:sub(2)
	end
	
	line = line:gsub("\\", "/")
	if line:sub(1,2) == "./" then
		line = line:sub(3)
	end
	
	return line
end

--- Checks if a currently executing line has a breakpoint on it.
local function check_breakpoints(stackoffset)
	stackoffset = stackoffset or 2
	local info = debug.getinfo(stackoffset+1, "Sl")
	assert(info, "Invalid stackoffset passed to stackoffset")
	local source, curline = transform_filename(info.source), info.currentline
	if breakpoints[source] and breakpoints[source][curline] then
		debug.sethook(breakpoints_hook, "l")
		io.write(">>> Breakpoint hit\n")
		debugger_loop(4)
		return true
	end
	return false
end

--- Debug hook that only scans for breakpoints
breakpoints_hook = function(event, linenum)
	check_breakpoints()
end

--- The debugger shell. Must be ran in a debug hook
debugger_loop = function(stackoffset, inhook)
	stackoffset = stackoffset or 3
	while true do
		-- Get and print the line of code we are on
		local info = debug.getinfo(stackoffset, "nSlu")
		assert(info, "Invalid stackoffset passed to debugger_loop")
		io.write(info.short_src, ":", info.currentline, "> ")
		local cmdstr = io.read("*l")
		assert(cmdstr, "Got nil from io.read, probably got ^C")
		local cmd, args = cmdstr:match("^([^%s]+)%s*(.-)$")
		
		if not cmd then
			io.write("Bad command\n")
		elseif not commands[cmd] then
			io.write("Unknown command\n")
		elseif commands[cmd].func(args, stackoffset+1, inhook) then
			break
		end
	end
end

-- ------------------------------------------------------------------------------------------
-- Commands

do
	-- ------------------------------------------------------------------------------------------
	-- Inspection
	
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
	
	-- ------------------------------------------------------------------------------------------
	-- Traversal
	
	commands["next"] = {
		shortdesc = "Resumes execution for one line, not going into function calls",
		func = function(argstr, stackoffset)
			-- Get the stack position that the debugged line is in
			local stackcount = count_stack() - stackoffset + 2
			debug.sethook(function(event, linenum)
				if check_breakpoints() then return end
				
				-- If we get a line event where the stack size is <= the stack size of the
				-- debugged line, then we are in the same function (or the function returned).
				-- Larger stack size means we are in an internal function, or the debugger function.
				if count_stack() <= stackcount then
					debug.sethook(breakpoints_hook, "l")
					debugger_loop()
				end
			end, "l")
			return true
		end
	}
	commands["n"] = commands["next"]
	
	commands["step"] = {
		shortdesc = "Resumes execution for one line, going into function calls",
		func = function(argstr, stackoffset, inhook)
			debug.sethook(function(event, linenum)
				if check_breakpoints() then return end
				
				debug.sethook(breakpoints_hook, "l")
				debugger_loop()
			end, "l")
			return true
		end
	}
	commands["s"] = commands["step"]
	
	-- ------------------------------------------------------------------------------------------
	-- Breakpoints
	
	commands["break"] = {
		shortdesc = "Sets a breakpoint",
		longdesc  = [[Usage: b(reak) <file>:<line>
Sets a breakpoint.
The line number must be an active line (a line with code on it) or else the breakpoint will never trigger.]],
		func = function(argstr, stackoffset)
			local file, line = argstr:match("^([^:]+):(%d+)$")
			if not file then
				io.write("Syntax: b(reak) <file>:<linenum>\n")
				return
			end
			line = tonumber(line)
			file = transform_filename(file)
			
			if not breakpoints[file] then
				breakpoints[file] = {}
			end
			
			breakpoints[file][line] = true
			io.write("Breakpoint set on ", file, ":", tostring(line), "\n")
		end
	}
	commands["b"] = commands["break"]
	
	commands["clear"] = {
		shortdesc = "Clears a breakpoint",
		longdesc  = [[Usage: cl(ear) <file>:<line>
Clears a previous set breakpoint.]],
		func = function(argstr, stackoffset)
			local file, line = argstr:match("^([^:]+):(%d+)$")
			if not file then
				io.write("Syntax: cl(ear) <file>:<linenum>\n")
				return
			end
			line = tonumber(line)
			file = transform_filename(file)
			
			if not breakpoints[file] or not breakpoints[file][line] then
				io.write("No breakpoint set on ", file, ":", tonumber(line), "\n")
				return
			end
			
			breakpoints[file][line] = nil
			io.write("Breakpoint on ", file, ":", tonumber(line), " cleared\n")
		end
	}
	commands["cl"] = commands["clear"]
	
	-- ------------------------------------------------------------------------------------------
	-- Other commands
	
	commands["help"] = {
		shortdesc = "Prints help",
		func = function(argstr, stackoffset)
			if argstr and commands[argstr] then
				io.write(commands[argstr].longdesc or commands[argstr].shortdesc, "\n")
			else
				-- Get keys and sort
				local keys = {}
				for k,_ in pairs(commands) do keys[#keys+1] = k end
				table.sort(keys)
				
				-- Iterate over sorted keys
				for _, cmd in ipairs(keys) do
					local tbl = commands[cmd]
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
	
	commands["quit"] = {
		shortdesc = "Terminates the process",
		longdesc  = "Terminates the process by calling os.exit().",
		func = function(argstr, stackoffset)
			os.exit()
		end,
	}
end

-- ------------------------------------------------------------------------------------------
-- Library functions

--- Pauses the script on the NEXT line of active code, and enters the debug shell.
function Debugger.pause()
	-- Instead of starting the debugger shell now, set a one-shot hook that starts the debugger code on
	-- the next line of user code and start the debugger shell in there.
	-- Because debug hook execution is disabled in the debug hook, the shell is free to set a new hook
	-- to run in the user code without worrying about the debugger code tripping the hook.
	debug.sethook(function()
		-- Skip the first line event, which is the 'end' of this pause function.
		debug.sethook(function()
			debug.sethook(breakpoints_hook, "l")
			io.write(">>> Debugger.pause()\n")
			debugger_loop()
		end, "l")
	end, "l")
end

debug.sethook(breakpoints_hook, "l")
return Debugger
