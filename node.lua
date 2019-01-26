-- Node.lua
-- By Ale32bit

-- https://git.ale32bit.me/Ale32bit/Node.lua

-- MIT License
-- Copyright (c) 2019 Alessandro "Ale32bit"

-- Full license
-- https://git.ale32bit.me/Ale32bit/Node.lua/src/branch/master/LICENSE

local node = {}

-- utils

local function genHex()
	local rand = math.floor(math.random() * math.floor(16^8))
	
	return rand
end

-- coroutine manager

local procs = {}

local function spawn(func)
	local id = #procs + 1
	procs[id] = {
		kill = false,
		thread = coroutine.create(func),
		filter = nil,
	}
	return id
end

local function kill(pid)
	procs[pid].kill = true
end

-- Node functions

function node.on(event, func)
	assert(type(event) == "string", "bad argument #1 (expected string, got ".. type(func) ..")")
	assert(type(func) == "function", "bad argument #2 (expected function, got ".. type(func) ..")")
	local listener = {}
	listener.event = event
	listener.func = func
	listener.id = genHex()
	listener.run = true
	listener.stopped = false
	listener.pid = spawn(function()
		while listener.run do
			local ev = {os.pullEvent(event)}
			listener.func(unpack(ev, 2))
		end
	end)
	
	listener = setmetatable(listener, {
		__tostring = function()
			return string.format("Listener 0x%x [%s] (%s)", listener.id, event, string.match(tostring(func),"%w+$"))
		end,
	})
	
	return listener
end

function node.removeListener(listener)
	assert(type(listener) == "table", "bad argument #1 (expected listener, got ".. type(listener) ..")")
	local id = listener.id
	assert(id, "bad argument #1 (expected listener, got ".. type(listener) ..")")
	
	if listener.stopped then
		return false
	end
	
	listener.run = false
	listener.stopped = true
	kill(listener.pid)
	return true
end

function node.setInterval(func, s, ...)
	assert(type(func) == "function", "bad argument #1 (expected function, got ".. type(func) ..")")
	s = s or 0
	assert(type(s) == "number", "bad argument #2 (expected number, got ".. type(s) ..")")
	local interval = {}
	interval.interval = s
	interval.func = func
	interval.args = {...}
	interval.id = genHex()
	interval.run = true
	interval.stopped = false
	interval.pid = spawn(function()
		while interval.run do
			local timer = os.startTimer(interval.interval)
			local _, p = os.pullEvent("timer")
			if p == timer then
				spawn(function()
					interval.func(unpack(interval.args))
				end)
			end
		end
	end)
	
	interval = setmetatable(interval, {
		__tostring = function()
			return string.format("Interval 0x%x [%s]s (%s)", interval.id, s, string.match(tostring(func),"%w+$"))
		end,
	})
	
	return interval
end

function node.clearInterval(interval)
	assert(type(interval) == "table", "bad argument #1 (expected interval, got ".. type(interval) ..")")
	local id = interval.id
	assert(id, "bad argument #1 (expected interval, got ".. type(interval) ..")")
	
	if interval.stopped then
		return false
	end
	
	interval.run = false
	interval.stopped = true
	kill(interval.pid)
	return true
end

function node.setTimeout(func, s, ...)
	assert(type(func) == "function", "bad argument #1 (expected function, got ".. type(func) ..")")
	s = s or 0
	assert(type(s) == "number", "bad argument #2 (expected number, got ".. type(s) ..")")
	local interval = {}
	interval.timeout = s
	interval.func = func
	interval.args = {...}
	interval.id = genHex()
	interval.stopped = false
	interval.pid = spawn(function()
		local timer = os.startTimer(interval.timeout)
		local _, p = os.pullEvent("timer")
		if p == timer then
			spawn(function()
				interval.func(unpack(interval.args))
				interval.stopped = true
			end)
		end
	end)
	
	interval = setmetatable(interval, {
		__tostring = function()
			return string.format("Timeout 0x%x [%s]s (%s)", interval.id, s, string.match(tostring(func),"%w+$"))
		end,
	})
	
	return interval
end

function node.clearTimeout(interval)
	assert(type(interval) == "table", "bad argument #1 (expected timeout, got ".. type(interval) ..")")
	local id = interval.id
	assert(id, "bad argument #1 (expected timeout, got ".. type(interval) ..")")
	
	if interval.stopped then
		return false
	end
	
	interval.stopped = true
	kill(interval.pid)
	return true
end

function node.init()
	while (function() 
		local c = 0
		for k,v in pairs(procs) do
			c = c+1
		end
		
		return c > 0
	end)() do
		local event = {coroutine.yield()}
		for pid, proc in pairs(procs) do
			if proc.kill then -- remove process if killed
				procs[pid] = nil
			else
				if proc.filter == nil or proc.filter == event[1] or event[1] == "terminate" then
					local ok, par = coroutine.resume( proc.thread, unpack(event))
					if not ok then
						error(par, 0)
						break
					else
						procs[pid].filter = par
					end
				end
				if coroutine.status(proc.thread) == "dead" then
					procs[pid] = nil
				end
			end
		end
	end
end


return node
