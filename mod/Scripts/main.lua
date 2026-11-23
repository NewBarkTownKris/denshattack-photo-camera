local folder = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local ue = dofile(folder .. "unreal.lua")
local input = dofile(folder .. "input.lua")
local photo = dofile(folder .. "photo.lua")
local effects = dofile(folder .. "effects.lua")
local finder = dofile(folder .. "finder.lua")
local optics = dofile(folder .. "optics.lua")
local linear = dofile(folder .. "linear.lua")
local current

local function log(message)
    print("[DenshattackPhotoCamera] " .. tostring(message) .. "\n")
end

local function releaseCapture(request)
    if request and request.isLinear then
        local ok, why = linear.cancel(request)
        if not ok then log("EXR cleanup: " .. tostring(why)) end
    end
end

local function finish(session)
    if current ~= session then return end
    current = nil
    releaseCapture(session.pending)
    if session.loop then
        local ok, err = pcall(input.stop, session.loop)
        if not ok then log(err) end
    end
    if session.finder then
        local ok, reason = finder.close(session.finder)
        if not ok then log(reason) end
        session.finder = nil
    end
    pcall(input.flush, session.pc)
    local ok, restored, reason = pcall(ue.close, session)
    if not ok or not restored then
        log("Restore: " .. tostring(reason or restored))
    else
        log("Gameplay view restored")
    end
end

local function apply(session, pose)
    local oldFov = session.pose.fov
    local ok, reason = ue.apply(session, pose)
    assert(ok, reason)
    session.pose = pose
    if oldFov ~= pose.fov then optics.refresh(session) end
end

local function showFinder(s, show)
    if not s.finder then return end
    local ok, reason = finder.visible(s.finder, show)
    assert(ok, reason)
end

local function drawFinder(s)
    if not s.finder or not s.showFinder then return end
    local w, h = ue.viewport(s)
    if not w then return end
    local a, b = photo.frame(s.frameIndex, s.portrait)
    local frame = a and ("%d:%d"):format(a, b) or "Viewport"
    local reticle = finder.reticles[s.reticleIndex]
    local mm = 18 / math.tan(math.rad(s.pose.fov / 2))
    local info = ("%g mm   %s   %s"):format(math.floor(mm * 10 + 0.5) / 10, frame, optics.status(s))
    local hint = s.notice or "F9 PNG   F3 PNG + EXR   F2 Folder   N Focus   F1 Controls"
    if s.help and not s.notice then
        hint = "WASD / Left stick Move   Mouse / Arrows / Right stick Aim\n"
            .. "E/Q Height   Z/X Roll   F10 Level\n"
            .. "F5 Frame   F6 Rotate   F7 Lens   [ ] Zoom   H Finder   G Grid   R Reticle\n"
            .. "N Autofocus   J/K Manual   L Fine   U/I Aperture   B DOF   Y Strength\n"
            .. "V Speed effects   F9 PNG   F3 PNG + EXR   F2 Folder   F8 Resume   F1 Hide controls"
    end
    local key = table.concat({w, h, frame, tostring(s.grid), reticle, info, hint}, "|")
    if key == s.lastFinder then return end
    local ok, reason = finder.update(s.finder, {width=w, height=h, crop=photo.crop(w, h, a, b),
        readout=info, hint=hint, grid=s.grid, reticle=reticle})
    if not ok then
        log("Finder unavailable: " .. tostring(reason))
        local removed, problem = finder.close(s.finder)
        assert(removed, problem)
        s.finder = nil
        return
    end
    s.lastFinder = key
end

local function completeShot(s, message)
    log(message)
    releaseCapture(s.pending)
    local notice = message
    if message:match("^Saved ") then
        notice = s.pending.isLinear and "PNG + EXR saved" or "PNG saved"
    end
    s.notice, s.noticeUntil, s.nextDraw = notice, ue.time(s) + 6, 0
    s.pending = nil
    if s.exitRequested then finish(s); return false end
    showFinder(s, s.showFinder)
    return true
end

local function update(session, dt, axes)
    if current ~= session then return false end
    local alive, why = ue.alive(session)
    if not alive then
        log(why or "Camera session ended")
        finish(session)
        return false
    end
    if session.pending then
        local now = ue.time(session)
        local request = session.pending
        if request.frames then
            request.frames = request.frames - 1
            if request.frames > 0 or now - session.requestTime < 0.05 then return true end
            request.frames = nil
            local ok, reason = ue.capture(session, request)
            if not ok then return completeShot(session, "Shutter failed: " .. tostring(reason)) end
            session.requestTime, session.nextCheck = now, now + 0.1
            return true
        end
        if now < session.nextCheck then return true end
        session.nextCheck = now + 0.1
        local checkFile = request.isLinear and linear.checkFile or photo.checkFile
        local saved, problem, madeProgress = checkFile(request, now)
        if madeProgress then session.requestTime = now end
        if saved and request.linear then
            log("Saved " .. (request.displayPath or request.path))
            local exr = request.linear
            local ok, reason = linear.capture(session, exr)
            if not ok then return completeShot(session, "PNG saved. EXR failed: " .. tostring(reason)) end
            exr.isLinear = true
            session.pending = exr
            session.requestTime = ue.time(session)
            session.nextCheck = session.requestTime
            return true
        end
        if saved or problem or now - session.requestTime >= (request.isLinear and 30 or 8) then
            local displayPath = request.displayPath or request.path
            if saved then return completeShot(session, "Saved " .. displayPath) end
            local errorMessage = problem or ("Timed out waiting for " .. displayPath)
            if request.isLinear then errorMessage = "PNG saved. EXR failed: " .. errorMessage end
            return completeShot(session, errorMessage)
        end
        return true
    end
    local pose = photo.move(session.pose, dt, axes)
    if pose then apply(session, pose) end
    local now = ue.time(session)
    if session.noticeUntil and now >= session.noticeUntil then session.notice, session.noticeUntil = nil, nil end
    if now >= session.nextDraw then
        drawFinder(session)
        session.nextDraw = now + 0.2
    end
    return true
end

local function toggle()
    if current then
        if current.pending then current.exitRequested = true
        else finish(current) end
        return
    end
    local session, reason = ue.open()
    if not session then log(reason); return end
    current = session
    session.frameIndex, session.lensIndex, session.portrait = 1, 0, false
    session.grid, session.showFinder, session.nextDraw, session.reticleIndex = false, true, 0, 1
    local applied, detail = effects.open(session, ue.defer)
    session.speedEffectsSuppressed = applied
    log(detail)
    session.finder, reason = finder.open(session)
    if session.finder then
        drawFinder(session)
        showFinder(session, true)
    else log("Finder unavailable: " .. tostring(reason)) end
    local ok, loop = pcall(input.start, session.pc, function(dt, axes)
        return update(session, dt, axes)
    end, function(err)
        log(err)
        finish(session)
    end)
    if not ok then log(loop); finish(session); return end
    session.loop = loop
    log("Photo mode active. F9 saves PNG, F3 saves PNG + linear EXR. F8 returns to the train.")
end

local function capture(session, withLinear)
    local w, h = ue.viewport(session)
    assert(w, h)
    local a, b = photo.frame(session.frameIndex, session.portrait)
    local crop = photo.crop(w, h, a, b)
    local dir, why, displayDir = ue.screenshotDir(session)
    assert(dir, why)
    local request = photo.request(dir, crop, withLinear)
    if displayDir then
        local native = displayDir:match("^%a:\\")
        local prefix = native and (displayDir:gsub("\\+$", "") .. "\\")
            or (displayDir:gsub("/+$", "") .. "/")
        request.displayPath = prefix .. request.filename
        if request.linear then request.linear.displayPath = prefix .. request.linear.filename end
    end
    showFinder(session, false)
    request.frames = 2
    session.pending, session.requestTime = request, ue.time(session)
    log("Requested " .. request.filename .. (withLinear and " + scene-linear EXR" or ""))
end

local function setFrame(session, index, portrait)
    local a, b = photo.frame(index, portrait)
    local ratio
    if a then ratio = a / b end
    local ok, reason = ue.frame(session, ratio)
    assert(ok, reason)
    session.frameIndex, session.portrait = index, portrait
    log(a and ("Frame %d:%d"):format(a, b) or "Frame follows viewport")
end

local handlers = {
    capture = capture,
    gradingCapture = function(s) capture(s, true) end,
    directory = function()
        local ok, reason = ue.requestDirectoryPicker()
        if not ok then return reason end
        return "Choose a folder on your desktop"
    end,
    help = function(s)
        s.help = not s.help
        if s.help and not s.showFinder then
            s.showFinder = true
            showFinder(s, true)
        end
    end,
    finder = function(s)
        assert(s.finder, "Finder unavailable")
        s.showFinder = not s.showFinder
        drawFinder(s)
        showFinder(s, s.showFinder)
    end,
    grid = function(s) s.grid = not s.grid end,
    reticle = function(s)
        s.reticleIndex = s.reticleIndex % #finder.reticles + 1
        local mode = finder.reticles[s.reticleIndex]
        if mode == "off" then return "Reticle off" end
        return mode:sub(1, 1):upper() .. mode:sub(2) .. " reticle"
    end,
    lines = function(s)
        local target = not s.speedEffectsSuppressed
        local ok, reason = effects.set(s, target)
        if ok then s.speedEffectsSuppressed = target end
        return reason
    end,
    dof = optics.toggle, autofocus = optics.autofocus, strength = optics.strength,
    nearer = function(s) return optics.manual(s, -1, s.fineFocus) end,
    farther = function(s) return optics.manual(s, 1, s.fineFocus) end,
    fineFocus = function(s)
        s.fineFocus = not s.fineFocus
        return s.fineFocus and "Manual focus step 1%" or "Manual focus step 20%"
    end,
    wider = function(s) return optics.aperture(s, -1) end,
    narrower = function(s) return optics.aperture(s, 1) end,
    frame = function(s) setFrame(s, s.frameIndex % #photo.frames + 1, s.portrait) end,
    portrait = function(s)
        -- Rotating the native viewport starts with the 35 mm gate.
        setFrame(s, s.frameIndex == 1 and 2 or s.frameIndex, not s.portrait)
    end,
    lens = function(s)
        local nextIndex = s.lensIndex % #photo.lenses + 1
        local mm = photo.lenses[nextIndex]
        local pose = {}
        for key, value in pairs(s.pose) do pose[key] = value end
        pose.fov = photo.lensFov(mm)
        apply(s, pose)
        s.lensIndex = nextIndex
        log(("Lens %d mm"):format(mm))
    end,
    level = function(s)
        local pose = {}
        for key, value in pairs(s.pose) do pose[key] = value end
        pose.roll = 0
        apply(s, pose)
    end,
}

local actions = {toggle = function()
    local ok, reason = pcall(toggle)
    if not ok then log(reason); if current then finish(current) end end
end}
for key, handler in pairs(handlers) do
    actions[key] = function()
        if not current or current.pending then return end
        local ok, reason = pcall(handler, current)
        if reason then
            log(reason)
            if ok and reason == optics.status(current) then
                current.notice, current.noticeUntil = nil, nil
            else
                current.notice, current.noticeUntil = tostring(reason), ue.time(current) + 3
            end
        end
        if not current.pending then current.nextDraw = 0 end
    end
end
input.install(actions)

RegisterLoadMapPreHook(function()
    if current then finish(current) end
end)
log("Camera loaded. Press F8 during a run.")
