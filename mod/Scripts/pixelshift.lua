-- Interleave subpixel-shifted whole-frame captures. Every phase sees the
-- entire composition, so shadows never change frustum at a strip boundary.
local pixelshift = {}
local maxPixels = 7680 * 4320
local maxMergePixels = 65536
local magic = "\118\047\049\001" .. string.pack("<I4", 2)

function pixelshift.fitsSingleView(w, h)
    return ((w + 31) // 32) * 32 * h <= maxPixels
end

function pixelshift.grid(w, h)
    assert(math.tointeger(w) and math.tointeger(h) and w >= 1 and h >= 1 and math.max(w,h) <= 16384,
        "Unsupported pixel-shift dimensions")
    local n = 2
    while true do
        local pw, ph = (w+n-1)//n, (h+n-1)//n
        if pixelshift.fitsSingleView(pw, ph) then return n, pw, ph end
        n = n+1
    end
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function readExact(f, bytes)
    local data = f:read(bytes)
    assert(data and #data == bytes, "Incomplete pixel-shift EXR")
    return data
end

local function box(w,h)
    return string.pack("<i4i4i4i4", 0, 0, w-1, h-1)
end

local function attribute(name, kind, value)
    return string.pack("<zzI4", name, kind, #value) .. value
end

-- Only reads the verified, uncompressed RGB scanline files emitted by
-- linear.lua. Preserve the gamut and photographic metadata byte for byte.
local function openPhase(job, phase)
    local file = assert(io.open(phase.path, "rb"))
    phase.reader = file
    local data = assert(file:read(65536))
    assert(data:sub(1,8) == magic, "Expected one scanline EXR per phase")
    local output, attributes = {magic}, {}
    local pos = 9
    while pos <= #data and data:byte(pos) ~= 0 do
        local key, kind, len, start = string.unpack("<zzI4", data, pos)
        assert(start+len-1 <= #data and not attributes[key], "Invalid phase EXR attribute")
        local value = data:sub(start,start+len-1)
        attributes[key] = value
        if key == "dataWindow" or key == "displayWindow" then
            assert(kind == "box2i" and value == box(job.pw,job.ph), "Incorrect phase EXR dimensions")
            value = box(job.w,job.h)
        end
        output[#output+1] = attribute(key,kind,value)
        pos = start+len
    end
    assert(data:byte(pos) == 0 and attributes.dataWindow and attributes.displayWindow and
        attributes.compression == "\0" and attributes.lineOrder == "\0", "Unsupported phase EXR header")
    local channels = assert(attributes.channels)
    local sampleType = string.unpack("<I4", channels, 3)
    assert(sampleType == 1 or sampleType == 2, "Expected HALF or FLOAT phase samples")
    local channelEntries = {}
    for _,ch in ipairs({"B","G","R"}) do
        channelEntries[#channelEntries+1] = string.pack("<zI4I4i4i4", ch,sampleType,0,1,1)
    end
    assert(channels == table.concat(channelEntries).."\0", "Expected full-resolution RGB phase channels")
    output[#output+1] = attribute("denshPixelShiftGrid","int",string.pack("<i4",job.grid)).."\0"
    local header, bytes = table.concat(output), sampleType == 1 and 2 or 4
    assert(not job.header or (job.header == header and job.bytes == bytes), "Inconsistent pixel-shift phase metadata")
    job.header, job.bytes = header, bytes
    assert(file:seek("set",pos))
    phase.offsets = readExact(file,job.ph*8)
    assert(file:seek("end") == pos+job.ph*(16+job.pw*bytes*3), "Incomplete phase EXR scanlines")
end

local function startMerge(job)
    for _, phase in ipairs(job.phases) do openPhase(job,phase) end
    assert(not exists(job.partial), "Pixel-shift staging file already exists")
    local f <close> = assert(io.open(job.partial,"wb"))
    job.ownsPartial = true
    assert(f:write(job.header))
    local first = #job.header + job.h*8
    local stride = 8 + job.w * job.bytes * 3
    for y=0,job.h-1 do assert(f:write(string.pack("<I8",first+y*stride))) end
    assert(f:flush())
    job.row = 0
end

local function mergeRows(job)
    local n, bytes = job.grid, job.bytes
    local f <close> = assert(io.open(job.partial,"ab"))
    local stop = math.min(job.h,job.row + math.max(1,maxMergePixels//job.w))
    local phaseRows, samples = {}, {}
    for y=job.row,stop-1 do
        local py, row = y%n, y//n
        for px=0,n-1 do
            local phase = job.phases[py*n+px+1]
            assert(phase.reader:seek("set",(string.unpack("<I8",phase.offsets,row*8+1))))
            local line,size = string.unpack("<i4I4",readExact(phase.reader,8))
            assert(line == row and size == 3*job.pw*bytes, "Invalid phase EXR scanline")
            phaseRows[px+1] = readExact(phase.reader,size)
        end
        assert(f:write(string.pack("<i4I4",y,3*job.w*bytes)))
        for channel=0,2 do
            for px=0,n-1 do
                local data = phaseRows[px+1]
                local pos = channel*job.pw*bytes+1
                for x=px+1,job.w,n do
                    samples[x] = data:sub(pos,pos+bytes-1)
                    pos = pos+bytes
                end
            end
            assert(f:write(table.concat(samples)))
        end
    end
    assert(f:flush())
    job.row = stop
    job.progress = 0.8 + 0.2 * stop/job.h
    return stop == job.h
end

function pixelshift.cancel(request)
    local job = request and request.pixelShiftJob
    if not job then return true end
    local errors = {}
    local function clean(task)
        local ok,why = pcall(task)
        if not ok then errors[#errors+1] = tostring(why) end
    end
    for _,p in ipairs(job.phases) do
        if p.started then clean(function() assert(job.linear.cancel(p)); p.started=nil end) end
        if p.reader then clean(function() assert(p.reader:close()); p.reader=nil end) end
        if p.saved then clean(function() assert(os.remove(p.path)); p.saved=nil end) end
    end
    if job.ownsPartial then clean(function() assert(os.remove(job.partial)); job.ownsPartial=nil end) end
    if #errors > 0 then return false,table.concat(errors," / ") end
    request.pixelShiftJob = nil
    return true
end

local function failure(request,reason)
    local _,cleanup = pixelshift.cancel(request)
    return false,tostring(reason)..(cleanup and (" / "..cleanup) or "")
end

function pixelshift.capture(session,request,linear)
    if request.pixelShiftJob or request.linearJob then return false,"A capture already owns this EXR" end
    local ok,why = pcall(function()
        local w,h = request.output.w,request.output.h
        local n,pw,ph = pixelshift.grid(w,h)
        local path = request.path
        assert(type(path)=="string" and path:match("%.exr$") and not exists(path), "Invalid or occupied pixel-shift EXR path")
        local job = {w=w,h=h,pw=pw,ph=ph,grid=n,linear=linear,index=1,
            phases={},partial=path..".partial",progress=0}
        request.pixelShiftJob = job
        assert(not exists(job.partial),"Pixel-shift staging file already exists")
        for y=0,n-1 do for x=0,n-1 do
            local phasePath, changed = path:gsub("([^/\\]+)%.exr$", function(stem)
                return (".%s.phase-%d-%d.exr"):format(stem,x,y)
            end)
            assert(changed == 1 and not exists(phasePath), "Pixel-shift phase already exists")
            job.phases[#job.phases+1] = {path=phasePath, crop=request.crop, output={w=pw,h=ph},
                exposure=request.exposure, phase={grid=n,x=x,y=y,width=w,height=h}}
        end end
        -- Queue every CaptureScene during this game tick. A reflected GPU
        -- readback can take minutes; animated materials must keep one time
        -- across the phase lattice. Each target is released after readback.
        for _,p in ipairs(job.phases) do
            p.started = true
            local started,reason = linear.capture(session,p)
            assert(started,reason or "Pixel-shift phase failed to start")
        end
    end)
    if not ok then return failure(request,why) end
    return true
end

function pixelshift.checkFile(request,now)
    local job = request.pixelShiftJob
    if not job then return false,"No pixel-shift capture in progress" end
    local ok,finished,progress = pcall(function()
        if job.index <= #job.phases then
            local p = job.phases[job.index]
            local done,err,advanced = job.linear.checkFile(p,now)
            assert(not err,err)
            if done then
                p.saved, p.started, job.index = true,nil,job.index+1
            end
            local tx = p.linearJob
            local within = tx and (tx.fallbackRow or tx.writeRow) or 0
            job.progress = 0.8 * (job.index-1 + within/job.ph) / #job.phases
            return false,done or advanced
        end
        if job.row == nil then startMerge(job); return false,true end
        if not mergeRows(job) then return false,true end
        local size <close> = assert(io.open(job.partial,"rb"))
        assert(size:seek("end") == #job.header+job.h*(16+job.w*3*job.bytes), "Incomplete interleaved EXR")
        size:close()
        assert(not exists(request.path),"EXR filename is already in use")
        assert(os.rename(job.partial,request.path))
        job.ownsPartial = false
        assert(pixelshift.cancel(request))
        return true,true
    end)
    if not ok then return failure(request,finished) end
    return finished,nil,progress
end

return pixelshift
