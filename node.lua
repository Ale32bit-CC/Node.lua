-- Node.lua
-- By Ale32bit

-- https://git.ale32bit.me/Ale32bit/Node.lua

-- MIT License
-- Copyright (c) 2019 Alessandro "Ale32bit"

-- Full license
-- https://git.ale32bit.me/Ale32bit/Node.lua/src/branch/master/LICENSE

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

local function on(event, func)
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
			spawn(function() listener.func(unpack(ev, 2)) end)
		end
	end)
	
	listener = setmetatable(listener, {
		__tostring = function()
			return string.format("Listener 0x%x [%s] (%s)", listener.id, event, string.match(tostring(func),"%w+$"))
		end,
	})
	
	return listener
end

local function removeListener(listener)
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

local function setInterval(func, s, ...)
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
			sleep(interval.interval)
			spawn(function()
				interval.func(unpack(interval.args))
			end)
		end
	end)
	
	interval = setmetatable(interval, {
		__tostring = function()
			return string.format("Interval 0x%x [%s]s (%s)", interval.id, s, string.match(tostring(func),"%w+$"))
		end,
	})
	
	return interval
end

local function clearInterval(interval)
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

local function setTimeout(func, s, ...)
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
		sleep(interval.timeout)
		spawn(function()
			interval.func(unpack(interval.args))
			interval.stopped = true
		end)
	end)
	
	interval = setmetatable(interval, {
		__tostring = function()
			return string.format("Timeout 0x%x [%s]s (%s)", interval.id, s, string.match(tostring(func),"%w+$"))
		end,
	})
	
	return interval
end

local function clearTimeout(interval)
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

local function spawnFunction(func)
	assert(type(func) == "function", "bad argument #1 (expected function, got ".. type(func) ..")")
	local pid = spawn(func)
	local thread = {}
	thread.pid = pid
	thread.kill = function()
		return kill(pid)
	end
	thread.status = function()
		return coroutine.status(procs[pid].thread)
	end
	
	local tostr = string.format("Thread 0x%s [%s] (%s)", string.match(tostring(procs[pid].thread),"%w+$"), thread.pid, string.match(tostring(func),"%w+$"))
	
	thread = setmetatable(thread, {
		__tostring = function()
			return tostr
		end,
	})
	return thread
end

local function promise(func, errorOnUncaught) -- errorOnUncaught is temporary
	assert(type(func) == "function", "bad argument #1 (expected function, got ".. type(func) ..")")
	
	local promise = {}
	promise.id = genHex()
	promise.status = "pending" -- "resolved", "rejected"
	promise.value = nil
	
	promise.bind = function(func)
		assert(type(func) == "function", "bad argument (expected function, got ".. type(func) ..")")
		promise.__then = func
	end
	
	promise.catch = function(func)
		assert(type(func) == "function", "bad argument (expected function, got ".. type(func) ..")")
		promise.__catch = func
	end
	
	promise.finally = function(func)
		assert(type(func) == "function", "bad argument (expected function, got ".. type(func) ..")")
		promise.__finally = func
	end
	
	local resolve = function(...)
		promise.value = {...}
		promise.status = "resolved"
		if promise.__then then
			spawn(function()
				promise.__then(unpack(promise.value))
			end)
		end
		if promise.__finally then
			spawn(promise.__finally)
		end
		kill(promise.pid)
	end
	
	local reject = function(...)
		promise.value = {...}
		promise.status = "rejected"
		if promise.__catch then
			spawn(function()
				promise.__catch(unpack(promise.value))
			end)
		else
			if errorOnUncaught then
				local val = {}
				for k, v in ipairs(promise.value) do
					val[k] = tostring(v)
				end
				error("Uncaught (in promise) "..table.concat(promise.value, " "), 2)
			else
				printError("Uncaught (in promise)", unpack(promise.value))
			end
		end
		if promise.__finally then
			spawn(promise.__finally)
		end
		kill(promise.pid)
	end
	
	promise.pid = spawn(function()
		func(resolve, reject)
	end)
	
	promise = setmetatable(promise, {
		__tostring = function()
			return string.format("Promise 0x%x [%s] (%s)", promise.id, promise.status, tostring(promise.value) or "nil")
		end,
	})
	
	return promise
end

local isRunning = false

local function init()
	if isRunning then
		error("Node Event Loop already running", 2)
	end
	isRunning = true
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
						isRunning = false
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
	isRunning = false
end

local function status()
	return isRunning
end


return {
	on = on,
	removeListener = removeListener,
	setInterval = setInterval,
	clearInterval = clearInterval,
	setTimeout = setTimeout,
	clearTimeout = clearTimeout,
	spawn = spawnFunction,
	promise = promise,
	init = init,
}
