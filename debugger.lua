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
		-- Turn off JIT to ensure the debug hook runs
		jit.off()
	end
end

-- Forward declare some tables and functions.
local Debugger = {}
local commands = {}
local breakpoints

local debugger_loop
local default_hook

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
	-- Remove @ prefix
	if line:sub(1,1) == "@" then
		line = line:sub(2)
	end
	
	-- Transform backslashes to forward slashes
	line = line:gsub("\\", "/")
	
	-- Remove ./ prefix
	if line:sub(1,2) == "./" then
		line = line:sub(3)
	end
	
	return line
end

--- The debugger shell. Must be ran in a debug hook
debugger_loop = function(stackoffset)
	stackoffset = stackoffset or 3
	debug.sethook(default_hook, "l")
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
		elseif commands[cmd].func(args, stackoffset+1) then
			break
		end
	end
end

--- Returns the current position of the debugged code.
local get_current_pos
do
	-- Is LuaJIT's profiler available
	local ok, profile = pcall(require, "jit.profile")
	if ok then
		-- Use LuaJIT's profile.dumpstack function, which is faster than debug.getinfo
		local dumpstack = profile.dumpstack
		
		get_current_pos = function(stackoffset)
			local stack = dumpstack("pl:", -stackoffset-2)
			local file, line = string.match(stack, "^[^:]*:[%d]:")
			return file, line and tonumber(line)
		end
	else
		-- LuaJIT's profiler is unavailable. Use debug.getinfo
		
		get_current_pos = function(stackoffset)
			local info = debug.getinfo(stackoffset+1, "Sl")
			assert(info, "Invalid stackoffset")
			return transform_filename(info.source), info.currentline
		end
		
	end
end

-- ------------------------------------------------------------------------------------------
-- Breakpoints

--- Adds a breakpoint
local function breakpoint_add(file, line)
	file = transform_filename(file)
	
	if not breakpoints then breakpoints = {} end
	if not breakpoints[file] then breakpoints[file] = {} end
	breakpoints[file][line] = true
end

--- Removes a breakpoint. Returns true on success, or false if there was no breakpoint there
local function breakpoint_remove(file, line)
	file = transform_filename(file)
	
	-- Is there a breakpoint there?
	if not breakpoints then return false end
	if not breakpoints[file] then return false end
	if not breakpoints[file][line] then return false end
	
	-- Delete the breakpoint
	breakpoints[file][line] = nil
	
	-- Last breakpoint in the file?
	if not next(breakpoints[file]) then
		-- Remove file from breakpoints list.
		breakpoints[file] = nil
		
		-- Last breakpoint?
		if not next(breakpoints) then
			-- Remove breakpoints list.
			breakpoints = nil
		end
	end
	
	return true
end

--- Checks if a currently executing line has a breakpoint on it.
local function breakpoint_check(stackoffset)
	if not breakpoints then return false end -- Don't bother if no breakpoints
	
	stackoffset = stackoffset or 2
	local source, curline = get_current_pos(stackoffset+1)
	if breakpoints[source] and breakpoints[source][curline] then
		io.write(">>> Breakpoint hit\n")
		debugger_loop(4)
		return true
	end
	return false
end


--- The default debugger hook
default_hook = function(event, linenum)
	breakpoint_check()
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
		shortdesc = "Prints local variables",
		longdesc = [[Usage: locals [stackoffset]
Prints out all local variables in a function.
Optionally takes a frame offset.]],
		func = function(argstr, stackoffset)
			stackoffset = stackoffset + (tonumber(argstr) or 1) - 1
			local i = 1
			while true do
				local name, val = debug.getlocal(stackoffset, i)
				if not name then break end
				if name:sub(1,1) ~= "(" then
					io.write(name, string.rep(" ", math.max(20-#name, 1)), "= ", tostring(val), "\n")
				end
				i = i + 1
			end
		end,
	}
	commands["vars"] = commands["locals"]
	
	commands["upvalues"] = {
		shortdesc = "Prints upvalues",
		longdesc  = [[Usage: upvalues [stackoffset]
Prints out all upvalues in a function.
Optionally takes a frame offset.]],
		func = function(argstr, stackoffset)
			stackoffset = stackoffset + (tonumber(argstr) or 1) - 1
			local func = debug.getinfo(stackoffset, "f").func
			local i = 1
			while true do
				local name, val = debug.getupvalue(func, i)
				if not name then break end
				io.write(name, string.rep(" ", math.max(20-#name, 1)), "= ", tostring(val), "\n")
				i = i + 1
			end
		end
	}
	
	-- ------------------------------------------------------------------------------------------
	-- Traversal
	
	commands["next"] = {
		shortdesc = "Resumes execution for one line, not going into function calls",
		func = function(argstr, stackoffset)
			-- Get the stack position that the debugged line is in
			local stackcount = count_stack() - stackoffset + 2
			debug.sethook(function(event, linenum)
				if breakpoint_check() then return end
				
				-- If we get a line event where the stack size is <= the stack size of the
				-- debugged line, then we are in the same function (or the function returned).
				-- Larger stack size means we are in an internal function, or the debugger function.
				if count_stack() <= stackcount then
					debug.sethook(default_hook, "l")
					debugger_loop()
				end
			end, "l")
			return true
		end
	}
	commands["n"] = commands["next"]
	
	commands["step"] = {
		shortdesc = "Resumes execution for one line, going into function calls",
		func = function(argstr, stackoffset)
			debug.sethook(function(event, linenum)
				if breakpoint_check() then return end
				
				debug.sethook(default_hook, "l")
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
			if not file or not tonumber(line) then
				io.write("Syntax: b(reak) <file>:<linenum>\n")
				return
			end
			line = tonumber(line)
			
			breakpoint_add(file, line)
			
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
			if not file or not tonumber(line) then
				io.write("Syntax: cl(ear) <file>:<linenum>\n")
				return
			end
			line = tonumber(line)
			
			if not breakpoint_remove(file, line) then
				io.write("No breakpoint set on ", file, ":", tonumber(line), "\n")
				return
			end
			
			io.write("Breakpoint on ", file, ":", tonumber(line), " cleared\n")
		end
	}
	commands["cl"] = commands["clear"]
	
	-- ------------------------------------------------------------------------------------------
	-- Other commands
	
	commands["run"] = {
		shortdesc = "Runs a piece of code",
		longdesc  = [[Runs a piece of code in the currently examined scope.
Locals and upvalues are simulated via a function environment.]],
		func = function(argstr, stackoffset)
			local func, err = loadstring(argstr, "run")
			if not func then
				io.write(err, "\n")
				return
			end
			
			local debugging_func = debug.getinfo(stackoffset, "f").func
			
			local local_names = {}
			local local_values = {}
			local upvalue_names = {}
			local upvalue_values = {}
			
			-- Get locals
			local i = 1
			while true do
				local name, val = debug.getlocal(stackoffset, i)
				if not name then break end
				if name:sub(1,1) ~= "(" then
					local_names[name] = i
					local_values[name] = val
				end
				i = i + 1
			end
			
			-- Get upvalues
			i = 1
			while true do
				local name, val = debug.getupvalue(debugging_func, i)
				if not name then break end
				if name:sub(1,1) ~= "(" then
					upvalue_names[name] = i
					upvalue_values[name] = val
				end
				i = i + 1
			end
			
			-- Get executing function environment
			local env = debug.getfenv(debugging_func)
			
			-- Create fake environment table to redirect local/upvalue access
			local env_mt = {}
			env_mt.__index = function(self, k)
				if local_names[k] then
					return local_values[k]
				elseif upvalue_names[k] then
					return upvalue_values[k]
				else
					return env[k]
				end
			end
			
			env_mt.__newindex = function(self, k, v)
				if local_names[k] then
					local_values[k] = v
				elseif upvalue_names[k] then
					upvalue_values[k] = v
				else
					env[k] = v
				end
			end
			
			-- Set environment and run
			setfenv(func, setmetatable({}, env_mt))
			local ok, err = pcall(func)
			if not ok then
				io.write(tostring(err), "\n")
			end
			
			-- Set the locals' new values
			for name, index in pairs(local_names) do
				debug.setlocal(stackoffset, index, local_values[name])
			end
			
			-- Set the upvalues' new values
			for name, index in pairs(upvalue_names) do
				debug.setupvalue(debugging_func, index, upvalue_values[name])
			end
		end
	}
	
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
			debug.sethook(default_hook, "l")
			io.write(">>> Debugger.pause()\n")
			debugger_loop()
		end, "l")
	end, "l")
end

--- Sets a breakpoint
function Debugger.breakpoint(file, line)
	assert(type(file) == "string", "file must be a string")
	line = assert(tonumber(line), "line must be a number")
	breakpoint_add(file, line)
end

debug.sethook(default_hook, "l")
return Debugger
