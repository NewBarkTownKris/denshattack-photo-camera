-- Run from the project root with Lua 5.4.
local photo = dofile("mod/Scripts/photo.lua")
local function near(x, y) assert(math.abs(x - y) < 0.000001) end

for _, size in ipairs({{3840, 2160}, {3440, 1440}, {1281, 801}}) do
    for index = 1, #photo.frames do
        for _, portrait in ipairs({false, true}) do
            local a, b = photo.frame(index, portrait)
            local c = photo.crop(size[1], size[2], a, b)
            if a then assert(c.w * b == c.h * a) end
            assert(c.x >= 0 and c.y >= 0)
            assert(math.abs(size[1] - c.w - 2 * c.x) <= 1)
            assert(math.abs(size[2] - c.h - 2 * c.y) <= 1)
        end
    end
end

local pose = {x=0, y=0, z=0, pitch=0, yaw=90, roll=0, fov=90}
local axes = {forward=1, right=0, up=0, pitch=0, yaw=0, roll=0, zoom=0, speed=1}
local moved = photo.move(pose, 0.1, axes)
near(moved.x, 0); near(moved.y, 8); near(moved.z, 0)
axes.right = 1
moved = photo.move(pose, 0.1, axes)
near(math.sqrt(moved.x^2 + moved.y^2), 8)
near(photo.lensFov(18), 90)
assert(photo.lensFov(600) < photo.lensFov(200))

-- Mouse reports angular displacement. Keys and sticks report rates.
local aim = {forward=0, right=0, up=0, yaw=0, pitch=0, roll=0, zoom=0, speed=1,
    mouseYaw=12, mousePitch=-4}
local mouse60, mouse144 = photo.move(pose, 1/60, aim), photo.move(pose, 1/144, aim)
near(mouse60.yaw, 102); near(mouse60.pitch, -4)
near(mouse144.yaw, mouse60.yaw); near(mouse144.pitch, mouse60.pitch)
aim.yaw, aim.pitch = 1, 1
local mixed = photo.move(pose, 0.05, aim)
near(mixed.yaw, 106); near(mixed.pitch, -0.75)
aim.yaw, aim.pitch = 0, 0
local tele = {x=0, y=0, z=0, pitch=89, yaw=179, roll=0, fov=photo.lensFov(135)}
aim.mousePitch = 30
local reframed = photo.move(tele, 0.05, aim)
near(reframed.yaw, -179.4); near(reframed.pitch, 89.9)
aim.mousePitch, aim.mouseYaw, aim.stickYaw = 0, 0, 0.75
near(photo.move(tele, 0.1, aim).yaw, 179.8)
aim.yaw = 1
near(photo.move(tele, 0.1, aim).yaw, -173)

-- Drive main.lua through the same callbacks that the keyboard bindings use.
local actions, tick, mapChange, requested, problem
local clock, opens, closes, shutters, rolls = 0, 0, 0, 0, 0
local alive, failLoop = true, false
local imagePath = os.tmpname()
local messages = {}
local finderShown, finderClosed, lastDisplay, rejectShutter
local exrCalls, exrSaves = 0, 0
local exposureShot = {mode="Game", iso=100}
local motionSteps, motionCancelled, motionRequest = 0, 0, nil
local pickerRequests, pickerError, displayDir = 0, nil, nil
local finder = {
    reticles = {"optical", "square", "circle", "off"},
    open = function() return {} end,
    update = function(_, model) lastDisplay = model; return true end,
    visible = function(_, show) finderShown = show; return true end,
    close = function() finderShown = false; finderClosed = true; return true end,
}
local ue = {
    open = function() opens = opens + 1; return {pose=pose, pc={}} end,
    alive = function() return alive end, time = function() return clock end,
    close = function() closes = closes + 1; return true end,
    viewport = function() return 1920, 1080 end,
    screenshotDir = function() return "/tmp", nil, displayDir end,
    requestDirectoryPicker = function()
        pickerRequests = pickerRequests + 1
        if pickerError then return nil, pickerError end
        return true
    end,
    frame = function(_, ratio) near(ratio, 3/2); return true end,
    apply = function() rolls = rolls + 1; return true end,
    capture = function(_, req)
        assert(not finderShown)
        if rejectShutter then return false, "shutter declined" end
        shutters = shutters + 1
        req.path = imagePath
        requested = req
        return true, req
    end,
}
local input = {
    install = function(a) actions = a end,
    start = function(_, callback, onError)
        if failLoop then error("scheduler unavailable") end
        tick, problem = callback, onError
        return {}
    end,
    stop = function() end, flush = function() end,
}
local env = setmetatable({
    dofile = function(path)
        if path:match("unreal.lua$") then return ue end
        if path:match("input.lua$") then return input end
        if path:match("finder.lua$") then return finder end
        if path:match("exposure.lua$") then return {
            tick=function() end, close=function() return true end,
            snapshot=function() return exposureShot end, prepareShot=function() return exposureShot end,
            status=function() return "" end,
            options=function() return {} end,
        } end
        if path:match("motion.lua$") then return {
            start=function(_, r)
                assert(not finderShown and r.exposure == r.linear.exposure)
                r.motionJob = {open=true}
                motionRequest = r
                return true
            end,
            step=function() motionSteps = motionSteps + 1; return motionSteps >= 2, nil, true end,
            cancel=function(r) motionCancelled = motionCancelled + 1; r.motionJob = nil; return true end,
        } end
        if path:match("linear.lua$") then return {
            capture=function(_, request)
                assert(not finderShown and request.filename:match("%.exr$"))
                exrCalls = exrCalls + 1
                return true
            end,
            checkFile=function() exrSaves = exrSaves + 1; return true end,
            cancel=function() return true end,
        } end
        if path:match("effects.lua$") then return {
            open=function() return true, "Speed lines hidden" end,
            set=function(_, hide) return true, hide and "hidden" or "original" end,
        } end
        if path:match("optics.lua$") then return {
            status=function() return "DOF off" end, refresh=function() end, track=function() end,
        } end
        return dofile(path)
    end,
    RegisterLoadMapPreHook = function(callback) mapChange = callback end,
    print = function(message) messages[#messages+1] = message end,
}, {__index = _G})
assert(loadfile("mod/Scripts/main.lua", "t", env))()

local still = {forward=0,right=0,up=0,pitch=0,yaw=0,roll=0,zoom=0}
actions.directory()
assert(pickerRequests == 0)
actions.toggle(); assert(finderShown and not lastDisplay.grid and lastDisplay.reticle == "optical")
actions.grid(); tick(0, still)
assert(lastDisplay.grid)
for _, expected in ipairs({"square", "circle", "off", "optical"}) do
    actions.reticle(); tick(0, still)
    assert(lastDisplay.reticle == expected and lastDisplay.grid)
end
actions.directory(); tick(0, still)
assert(pickerRequests == 1 and lastDisplay.hint == "Choose a folder on your desktop")
pickerError = "Desktop folder picker unavailable"
actions.directory(); tick(0, still)
assert(pickerRequests == 2 and lastDisplay.hint == pickerError)
displayDir = "/home/test/Photo album/"
actions.frame(); actions.lens(); actions.capture(); actions.capture()
actions.directory(); actions.reticle()
assert(pickerRequests == 2 and lastDisplay.reticle == "optical")
assert(not finderShown and shutters == 0)
clock = 0.1; tick(0.01, axes); assert(shutters == 0)
clock = 0.2; tick(0.01, axes)
assert(opens == 1 and shutters == 1 and rolls == 1)
assert(requested.crop.w == 1620 and requested.crop.h == 1080)
assert(requested.displayPath == "/home/test/Photo album/" .. requested.filename)
actions.toggle(); clock = 0.5; tick(0.01, axes)
assert(closes == 0, "must hold the photographic view during a pending write")

-- Simulate the signature, dimensions and final chunk observed by the polling
-- code. An incomplete write must leave the pending request in place.
local function writeHeader(width, withEnd)
    local f = assert(io.open(imagePath, "wb"))
    f:write("\137PNG\r\n\26\n", string.pack(">I4", 13), "IHDR", string.pack(">I4I4", width, 1080))
    if withEnd then f:write("\0\0\0\0IEND\174\66\96\130") end
    f:close()
end
writeHeader(1620, false); clock = 1; tick(0.01, axes); assert(closes == 0)
writeHeader(1620, true); clock = 2; tick(0.01, axes)
assert(closes == 1 and finderClosed and table.concat(messages, "\n"):find("Saved " .. requested.displayPath, 1, true))
writeHeader(1920, true); assert(select(2, photo.checkFile(requested)):find("expected"))
os.remove(imagePath)

actions.toggle(); actions.capture(); actions.toggle()
clock = 2.1; tick(0.01, axes); clock = 2.2; tick(0.01, axes); clock = 11; tick(0.01, axes)
assert(closes == 2 and table.concat(messages, "\n"):find("Timed out", 1, true))
actions.toggle(); mapChange(); assert(closes == 3)
actions.toggle(); alive = false; tick(0.01, axes); assert(closes == 4)
alive = true; actions.toggle(); actions.lines(); actions.capture()
rejectShutter = true; clock = 11.1; tick(0.01, axes); clock = 11.2; tick(0.01, axes)
assert(finderShown and table.concat(messages, "\n"):find("shutter declined", 1, true))
actions.finder(); assert(not finderShown)
actions.capture(); clock = 11.3; tick(0.01, axes); clock = 11.4; tick(0.01, axes)
assert(not finderShown, "honor the photographer's hidden finder after a capture")
problem("lost controller"); assert(closes == 5)
failLoop = true; actions.toggle(); assert(closes == 6)
failLoop, rejectShutter = false, false
actions.toggle(); actions.frame(); actions.gradingCapture(); actions.capture(); actions.toggle()
clock = 12; tick(0.01, axes); clock = 12.1; tick(0.01, axes)
assert(requested.linear and requested.filename:gsub("%.png$", ".exr") == requested.linear.filename)
assert(requested.linear.displayPath == "/home/test/Photo album/" .. requested.linear.filename)
assert(exrCalls == 0)
writeHeader(1620, true); clock = 13; tick(0.01, axes); assert(exrCalls == 1 and closes == 6)
clock = 13.1; tick(0.01, axes); assert(exrSaves == 1 and closes == 7 and not finderShown)
assert(table.concat(messages, "\n"):find("Saved " .. requested.linear.displayPath, 1, true))
os.remove(imagePath)
alive, failLoop = true, false
exposureShot = {mode="Manual", seconds=1, iso=800, ready=true, gain=2}
actions.toggle(); actions.gradingCapture()
clock = 20; tick(0.01, axes); clock = 20.1; tick(0.01, axes)
assert(motionRequest and finderShown and lastDisplay.readout:find("Exposing"))
local beforeMoves = rolls
clock = 20.2; tick(0.01, axes); clock = 20.3; tick(0.01, axes)
assert(rolls == beforeMoves + 2 and motionSteps == 2 and motionCancelled == 1 and finderShown)
actions.gradingCapture(); clock = 21; tick(0.01, axes); clock = 21.1; tick(0.01, axes)
actions.toggle(); assert(motionCancelled == 2)
print("Passed camera movement, optics, crop, short and timed shutter, cancellation and session cleanup checks.")
