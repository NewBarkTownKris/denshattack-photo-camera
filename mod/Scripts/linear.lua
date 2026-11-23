-- SceneColor HDR is sampled before the display transform in an independent,
-- one-shot view. A fresh capture has no persistent eye-adaptation history.
local linear = {}
local folder = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local fallback = dofile(folder .. "exrfallback.lua")
local magic = "\118\047\049\001" .. string.pack("<I4", 2)

local function valid(o)
    return o and o:IsValid()
end

local function object(path)
    local o = StaticFindObject(path)
    assert(valid(o), "Unavailable Unreal object " .. path)
    return o
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function attribute(name, kind, bytes)
    return name .. "\0" .. kind .. "\0" .. string.pack("<I4", #bytes) .. bytes
end

local function readExact(f, count)
    local b = f:read(count)
    assert(b and #b == count, "Incomplete EXR")
    return b
end

local function name(f)
    local result = {}
    for i = 1, 256 do
        local ch = readExact(f, 1)
        if ch == "\0" then return table.concat(result) end
        result[i] = ch
    end
    error("Overlong EXR name")
end

local function header(f, w, h)
    assert(readExact(f, 8) == magic, "Expected a single-part scanline OpenEXR")
    local attrs = {}
    for i = 1, 100 do
        local key = name(f)
        if key == "" then break end
        local kind = name(f)
        local len = string.unpack("<I4", readExact(f, 4))
        assert(len < 65536, "Unexpectedly large EXR attribute")
        attrs[key] = {kind=kind, bytes=readExact(f, len)}
    end
    assert(attrs.dataWindow and attrs.dataWindow.bytes == string.pack("<i4i4i4i4", 0, 0, w-1, h-1),
        "EXR dimensions do not match the selected frame")
    assert(attrs.compression and attrs.compression.bytes == "\0", "Expected uncompressed EXR scanlines")
    assert(attrs.channels and attrs.channels.kind == "chlist", "Missing EXR channels")
    local list = {}
    local pos, data = 1, attrs.channels.bytes
    while data:byte(pos) ~= 0 do
        local channel, pixel, _, x, y
        channel, pixel, _, x, y, pos = string.unpack("<zI4I4i4i4", data, pos)
        assert(pixel == 1 and x == 1 and y == 1, "Expected full-resolution HALF channels")
        list[#list + 1] = channel
    end
    local channels = table.concat(list)
    assert(channels == "ABGR" or channels == "BGR", "Unexpected EXR channels: " .. channels)
    return channels
end

local function colorSpace()
    local settings = object("/Script/Engine.Default__RendererSettings")
    local enum = object("/Script/Engine.EWorkingColorSpace")
    local selected = enum:GetNameByValue(settings.WorkingColorSpaceChoice):ToString()
    assert(selected:match("sRGB$"), "EXR grading requires a verified working gamut; game selected " .. selected)
    return string.pack("<ffffffff", 0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.3290)
end

local function rgbHeader(w, h, chroma)
    local entries = {}
    for _, ch in ipairs({"B", "G", "R"}) do
        entries[#entries + 1] = string.pack("<zI4I4i4i4", ch, 1, 0, 1, 1)
    end
    local box = string.pack("<i4i4i4i4", 0, 0, w-1, h-1)
    return magic .. attribute("channels", "chlist", table.concat(entries) .. "\0")
        .. attribute("compression", "compression", "\0")
        .. attribute("dataWindow", "box2i", box) .. attribute("displayWindow", "box2i", box)
        .. attribute("lineOrder", "lineOrder", "\0") .. attribute("pixelAspectRatio", "float", string.pack("<f", 1))
        .. attribute("screenWindowCenter", "v2f", string.pack("<ff", 0, 0))
        .. attribute("screenWindowWidth", "float", string.pack("<f", 1))
        .. attribute("chromaticities", "chromaticities", chroma)
        .. attribute("comments", "string", "Denshattack Photo Camera; SceneColor HDR; linear Rec.709/D65") .. "\0"
end

-- The HDRNoAlpha source places zero in alpha. Strip that channel so grading
-- software displays the RGB as an opaque still. Preserve every RGB half bit,
-- including signed and superwhite values. Memory usage scales with one row.
local function publishRGB(source, dest, w, h, chroma, renderWidth, left)
    local f <close> = assert(io.open(source, "rb"), "Unreal did not produce the EXR")
    local channels = header(f, renderWidth, h)
    local indices = readExact(f, h * 8)
    local out <close> = assert(io.open(dest, "wb"))
    local hdr = rgbHeader(w, h, chroma)
    assert(out:write(hdr))
    local stride = 8 + 6 * w
    local first = #hdr + h * 8
    for y = 0, h-1 do assert(out:write(string.pack("<I8", first + y * stride))) end
    for y = 0, h-1 do
        assert(f:seek("set", string.unpack("<I8", indices, y * 8 + 1)))
        local line, size = string.unpack("<i4I4", readExact(f, 8))
        assert(line == y and size == #channels * renderWidth * 2, "Invalid EXR scanline")
        if channels == "ABGR" then assert(f:seek("cur", renderWidth * 2)) end
        local rgb = readExact(f, 6 * renderWidth)
        assert(out:write(string.pack("<i4I4", y, 6 * w)))
        if renderWidth == w then
            assert(out:write(rgb))
        else
            -- Uncompressed EXR stores B, G, R as separate planes per row.
            for plane = 0, 2 do
                local start = 2 * (plane * renderWidth + left)
                assert(out:write(rgb:sub(start + 1, start + 2 * w)))
            end
        end
    end
    assert(out:flush())
end

-- Use the active game's projection at the selected crop boundaries. This
-- handles the project's axis constraint, including portrait and native gates.
local function projection(session, crop, library, renderWidth, left)
    local y = crop.y + crop.h / 2
    local function ray(x)
        local direction = {}
        assert(session.pc:DeprojectScreenPositionToWorld(x, y, {}, direction), "Could not read viewfinder projection")
        local k = session.locationKeys
        return {direction[k.x], direction[k.y], direction[k.z]}
    end
    local a, b = ray(crop.x), ray(crop.x + crop.w)
    local dot = a[1]*b[1] + a[2]*b[2] + a[3]*b[3]
    local fov = math.deg(math.acos(math.max(-1, math.min(1, dot))))
    assert(fov > 0 and fov < 180, "Invalid viewfinder field of view")
    -- Extend the frustum by one original pixel footprint per guard column.
    -- For an odd guard count, shift the principal point by half a pixel so
    -- each retained texel still represents the same viewfinder ray.
    local tangent = math.tan(math.rad(fov) / 2) * renderWidth / crop.w
    local paddedFov = math.deg(2 * math.atan(tangent))
    local right = renderWidth - crop.w - left
    local view = {FOV=paddedFov, AspectRatio=renderWidth/crop.h, ProjectionMode=0,
        OffCenterProjectionOffset={X=(right-left)/renderWidth, Y=0}}
    return library:CalculateProjectionMatrix(view), paddedFov
end

-- UE4SS serializes struct arguments with the exact display spelling of
-- reflected names. A project's cooked FName casing may differ from the SDK.
local function structArgs(path, values)
    local fields, n = {}, 0
    object(path):ForEachProperty(function(prop)
        local key = prop:GetFName():ToString()
        local v = values[key:lower()]
        if v ~= nil then fields[key], n = v, n + 1 end
    end)
    local count = 0
    for _ in pairs(values) do count = count + 1 end
    assert(n == count, "Missing reflected properties on " .. path)
    return fields
end

function linear.cancel(request)
    local tx = request and request.linearJob
    if not tx then return true end
    local errors = {}
    local function release(task)
        local ok, err = pcall(task)
        if not ok then errors[#errors + 1] = tostring(err) end
    end
    if valid(tx.actor) then release(function() tx.actor:K2_DestroyActor(); tx.actor = nil end) end
    if valid(tx.target) then release(function() tx.library:ReleaseRenderTarget2D(tx.target); tx.target = nil end) end
    for _, path in ipairs({tx.source, tx.partial}) do
        if exists(path) then release(function() assert(os.remove(path)) end) end
    end
    if #errors > 0 then return false, table.concat(errors, " / ") end
    request.linearJob = nil
    return true
end

function linear.capture(session, request)
    local path, crop = request.path, request.crop
    if not path or not path:match("%.exr$") then return false, "Expected an EXR path" end
    local source, partial = path:sub(1, -5) .. ".source.exr", path .. ".partial"
    if request.linearJob or exists(path) or exists(source) or exists(partial) then return false, "EXR filename is already in use" end
    local tx = {source=source, partial=partial, world=session.world}
    request.linearJob = tx
    local ok, issue = pcall(function()
        local w, h = crop.w, crop.h
        assert(math.tointeger(w) and w > 0 and math.tointeger(h) and h > 0, "Invalid EXR dimensions")
        tx.chroma = colorSpace()
        tx.library = object("/Script/Engine.Default__KismetRenderingLibrary")
        tx.writer = object("/Script/ImageWriteQueue.Default__ImageWriteBlueprintLibrary")
        tx.options = structArgs("/Script/ImageWriteQueue.ImageWriteOptions",
            {format=3, compressionquality=1, boverwritefile=false, basync=false})
        -- DX12 staging rows are 256-byte aligned. RGBA16F is eight bytes per
        -- texel, so a 32-texel multiple gives the writer tightly packed rows.
        tx.renderWidth = ((w + 31) // 32) * 32
        tx.left = (tx.renderWidth - w) // 2
        local matrix, fov = projection(session, crop, tx.library, tx.renderWidth, tx.left)
        local p = session.pose
        tx.actor = session.world:SpawnActor(object("/Script/Engine.SceneCapture2D"),
            {X=p.x, Y=p.y, Z=p.z}, {Pitch=p.pitch, Yaw=p.yaw, Roll=p.roll})
        assert(valid(tx.actor), "Could not spawn EXR capture")
        local component = tx.actor:GetComponentByClass(object("/Script/Engine.SceneCaptureComponent2D"))
        assert(valid(component), "Missing scene capture component")
        component.bCaptureEveryFrame, component.bCaptureOnMovement = false, false
        component.bAlwaysPersistRenderingState = false
        local k, r = session.locationKeys, session.angleKeys
        assert(tx.actor:K2_SetActorLocationAndRotation({[k.x]=p.x, [k.y]=p.y, [k.z]=p.z},
            {[r.pitch]=p.pitch, [r.yaw]=p.yaw, [r.roll]=p.roll}, false, {}, true), "Could not position EXR camera")
        tx.target = tx.library:CreateRenderTarget2D(session.world, tx.renderWidth, h, 6, {R=0,G=0,B=0,A=0}, false, false)
        assert(valid(tx.target), "Could not create RGBA16f render target")
        tx.target.TargetGamma = 1
        component.FOVAngle, component.CustomProjectionMatrix, component.bUseCustomProjectionMatrix = fov, matrix, true
        component.CaptureSource, component.TextureTarget = 1, tx.target -- SCS_SceneColorHDRNoAlpha
        component:CaptureScene()
    end)
    if not ok then
        local _, cleanup = linear.cancel(request)
        return false, tostring(issue) .. (cleanup and " / " .. cleanup or "")
    end
    return true
end

function linear.checkFile(request, now)
    local tx = request.linearJob
    if tx then
        now = now or os.clock()
        local previousRow = tx.fallbackRow
        local ok, err = pcall(function()
            if not tx.submittedAt then
                -- CaptureScene queues the render. Keep the actor and target
                -- alive across an engine frame before requesting GPU readback.
                tx.writer:ExportToDisk(tx.target, tx.source, tx.options)
                -- ExportToDisk can return before its render command executes,
                -- even with bAsync=false. A one-pixel read fences previous
                -- work and keeps the render target alive through readback.
                tx.library:ReadRenderTargetRawPixel(tx.world, tx.target, 0, 0, false)
                tx.submittedAt = now
                return
            end
            local w, h = request.crop.w, request.crop.h
            if tx.fallbackRow or not exists(tx.source) then
                if now - tx.submittedAt < 2 then return end
                if not tx.fallbackRow then
                    print("[DenshattackPhotoCamera] EXR writer produced no file. Reading scene RGB directly.\n")
                end
                if not fallback.step(tx, request, rgbHeader) then return end
            else
                local f <close> = assert(io.open(tx.source, "rb"))
                local size = assert(f:seek("end"))
                if not tx.lastSize or tx.lastSize ~= size then tx.lastSize = size; return end
                f:close()
                publishRGB(tx.source, tx.partial, w, h, tx.chroma, tx.renderWidth, tx.left)
            end
            assert(os.rename(tx.partial, request.path))
            local cleaned, why = linear.cancel(request)
            assert(cleaned, why)
        end)
        if not ok then
            local _, cleanup = linear.cancel(request)
            return false, tostring(err) .. (cleanup and " / " .. cleanup or "")
        end
        if request.linearJob then return false, nil, previousRow ~= tx.fallbackRow end
    end
    if not exists(request.path) then return false end
    local ok, err = pcall(function()
        local f <close> = assert(io.open(request.path, "rb"))
        local w, h = request.crop.w, request.crop.h
        assert(header(f, w, h) == "BGR", "Expected RGB EXR")
        local endOfHeader = assert(f:seek())
        assert(f:seek("end") == endOfHeader + h * (16 + w * 6), "Incomplete RGB EXR")
    end)
    if not ok then return false, tostring(err) end
    return true
end

return linear
