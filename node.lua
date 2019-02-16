--[[

	Node.lua by Ale32bit
	https://github.com/Ale32bit-CC/Node.lua

	MIT License

	Copyright (c) 2019 Ale32bit

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
	
	
	-- DOCUMENTATION --
	
	To start:
	
	local node = require("node")
	
	Functions:
	
	node.on( event, callback ): Event name (string), Callback (function)
	Returns table with listener details and thread
	
	node.removeListener( listener ): Listener (table)
	Returns boolean if success
	
	node.setInterval( callback, interval, [...] ): Callback (function), Interval in seconds (number), ...Arguments for callback (anything)
	Returns table with interval details and thread
	
	node.clearInterval( interval ): Interval (table)
	Returns boolean if success
	
	node.setTimeout( callback, timeout, [...] ): Callback (function), Timeout in seconds (number), ...Arguments for callback (anything)
	Returns table with timeout details and thread
	
	node.clearTimeout( timeout ): Timeout (table)
	Returns boolean if success
	
	node.spawn( function ): Function to execute in the coroutine manager (function)
	Returns table containing details and methods
	
	node.promise( executor, [options] ): Executor (function), Options (table): options.errorOnUncaught (boolean) use error() or just printError in case of uncaught reject
	Returns table, 3 functions: bind(cb) on fulfill, catch(cb) on reject and finally(cb) after these functions. They all want callback functions.
	
	node.init(): Start the event loop engine !! REQUIRED TO RUN !!
	
	node.isRunning(): Check if event loop engine is running
	Returns boolean
	
]]--


-- Variables --

local isRunning = false
local threads = {} -- Store all threads here

-- Utils --

local function assertType(v, exp, n, level)
	n = n or 1
	level = level or 3
	if type(v) ~= exp then
		error("bad argument #"..n.." (expected "..exp..", got "..type(v)..")", level)
	end
end

-- Thread functions --

local function killThread(pid) -- Kill a thread
	assertType(pid, "number", 1, 2)
	if threads[pid] then
		threads[pid].tokill = true
		return true
	end
	return false
end

local function spawnThread(f) -- Spawn new thread
	assertType(f, "function", 1, 2)
	local pid = #threads + 1
	local thread = {
		tokill = false,
		thread = coroutine.create(f),
		filter = nil,
		pid = pid,
	}
	thread = setmetatable(thread, {
		__index = {
			kill = function(self)
				killThread(self.pid)
			end,
			status = function(self)
				return coroutine.status(self.thread)
			end,
		},
		
		__tostring = function(self)
			return "Thread "..self.pid..": "..self:status()
		end,
	})
	threads[pid] = thread
	return thread, pid
end

-- Node functions --

-- Event Listener
local function on(event, callback)
	assertType(event, "string", 1)
	assertType(callback, "function", 2)
	
	-- Create listener
	local listener = {}
	listener.event = event
	listener.callback = callback
	listener.run = true
	listener.stopped = false
	listener.thread = spawnThread(function()
		while listener.run do
			local ev = {os.pullEvent(listener.event)}
			spawnThread(function() listener.callback(unpack(ev, 2)) end)
		end
	end)
	
	return listener
end


-- Remove event listener
local function removeListener(listener)
	assert(listener, "table")
	if not listener.thread then
		error("bad argument #1 (expected Event Listener)", 2)
	end
	if listener.stopped then
		return false
	end
	listener.run = false
	listener.stopped = true
	killThread(listener.thread.pid)
	return true
end

-- Create new interval
local function setInterval(callback, s, ...)
	assertType(callback, "function", 1)
	s = s or 0
	assertType(s, "number", 2)
	
	local interval = {}
	interval.interval = s
	interval.callback = callback
	interval.args = {...}
	interval.run = true
	interval.stopped = false
	interval.thread = spawnThread(function()
		while interval.run do
			local timer = os.startTimer( interval.interval )
			repeat
				local _, t = os.pullEvent("timer")
			until t == timer
			spawnThread(function()
				interval.callback(unpack(interval.args))
			end)
		end
	end)
	
	return interval
end

-- Clear interval
local function clearInterval(interval)
	assert(interval, "table")
	if not interval.thread then
		error("bad argument #1 (expected Interval)", 2)
	end
	if interval.stopped then
		return false
	end
	
	interval.run = false
	interval.stopped = true
	killThread(interval.thread.pid)
	return true
end

-- Create new timeout
local function setTimeout(callback, s, ...)
	assertType(callback, "function", 1)
	s = s or 0
	assertType(s, "number", 2)
	
	local timeout = {}
	timeout.timeout = s
	timeout.callback = callback
	timeout.args = {...}
	timeout.stopped = false
	timeout.thread = spawnThread(function()
		local timer = os.startTimer( timeout.timeout )
		repeat
			local _, t = os.pullEvent("timer")
		until t == timer
		timeout.callback(unpack(timeout.args))
	end)
	
	return timeout
end

-- Clear timeout
local function clearTimeout(timeout)
	assert(timeout, "table")
	if not timeout.thread then
		error("bad argument #1 (expected Timeout)", 2)
	end
	if timeout.stopped then
		return false
	end
	
	timeout.stopped = true
	killThread(timeout.thread.pid)
	return true
end

-- New promise
local function promise(executor, options)
	assertType(executor, "function", 1)
	options = options or {}
	options.errorOnUncaught = options.errorOnUncaught or false
	assertType(options, "table", 2)
	
	local promise = {}
	promise.options = options
	promise.status = "pending"
	promise.value = nil
	
	promise.bind = function( callback )
		assertType(callback, "function")
		promise.__bind = callback
	end
	
	promise.catch = function( callback )
		assertType(callback, "function")
		promise.__catch = callback
	end
	
	promise.finally = function( callback )
		assertType(callback, "function")
		promise.__finally = callback
	end
	
	promise.__resolve = function( value )
		promise.status = "resolved"
		promise.value = value
		killThread(promise.thread.pid)
		if promise.__bind then
			spawnThread(function()
				promise.__bind(value)
			end)
		end
		if promise.__finally then
			spawnThread(promise.__finally)
		end
		return value
		
	end
	
	promise.__reject = function( reason )
		promise.status = "rejected"
		promise.value = reason
		killThread(promise.thread.pid)
		if promise.__catch then
			spawnThread(function()
				promise.__catch(reason)
			end)
		else
			if promise.options.errorOnUncaught then
				error("Uncaught (in promise) "..tostring(reason), 3)
			else
				printError("Uncaught (in promise) "..tostring(reason))
			end
		end
		if promise.__finally then
			spawnThread(promise.__finally)
		end
		return reason
	end
	
	promise.thread = spawnThread(function()
		executor(promise.__resolve, promise.__reject)
	end)
	
	return promise
end

-- Start the event loop engine
local function init()
	assert(not isRunning, "Event loop engine already running")
	isRunning = true
	
	os.queueEvent("node_init")
	
	while (function() -- Execute loop if threads count is higher than 0
		local count = 0
		for k,v in pairs(threads) do
			count = count+1
		end
		return count > 0
	end)() do
		local event = {coroutine.yield()}
		for pid, thread in pairs(threads) do
			if thread.tokill then
				threads[pid] = nil -- Remove thread if killed (and don't resume it)
			else
				if thread.filter == nil or thread.filter == event[1] or event[1] == "terminate" then -- filter events
					local ok, par = coroutine.resume( thread.thread, unpack(event))

					
					if ok then -- If ok par should be the event os.pullEvent expects
						threads[pid].filter = par
					else -- else the thread crashed
						isRunning = false
						error(par, 0) -- terminate event loop engine because of error
						break -- just in case
					end
				end
				
				if coroutine.status(thread.thread) == "dead" then -- If thread died (ended with no errors) remove it from the threads table
					threads[pid] = nil
				end
			end
		end
	end
	
	isRunning = false
end

-- Returns status
local function status()
	return isRunning
end

-- Export and set in _ENV --

local node = {
	on = on,
	removeListener = removeListener,
	setInterval = setInterval,
	clearInterval = clearInterval,
	setTimeout = setTimeout,
	clearTimeout = clearTimeout,
	spawn = spawnThread,
	promise = promise,
	init = init,
	status = status,
}

if _ENV then
	_ENV.node = node
end

return node
