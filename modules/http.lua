if not node then
	error("Node.lua not found", 2)
end

function get(url)
    return node.promise(function(resolve, reject)
        local ok, err = http.request(url)
        if not ok then
            return reject(err)
        end
       
        local ev
        repeat
            ev = {os.pullEvent()}
        until ev[1] == "http_success" or ev[1] == "http_failure" and ev[2] == url
       
        if ev[1] == "http_success" then
            return resolve(ev[3])
        elseif ev[1] == "http_failure" then
            return reject(ev[3])
        end
    end)
end
 
return {
    get = get,
}

