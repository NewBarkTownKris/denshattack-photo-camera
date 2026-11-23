local function near(a, b)
    assert(math.abs(a - b) <= 1e-6 * math.max(1, math.abs(b)), ("%g != %g"):format(a, b))
end

local camera, world, train = {}, {}, {}
local trace = {calls = 0}
function trace:IsValid() return true end
function trace:LineTraceSingle(context, start, finish, channel, complex, ignore, draw, hit, ignoreSelf, _, _, duration)
    self.calls = self.calls + 1
    assert(context == camera and context ~= train and #ignore == 0 and ignoreSelf)
    assert(channel == 0 and complex and draw == 0 and duration == 0)
    -- Shipping FNames are case preserving. Use mixed-case keys like a reflected call.
    assert(start.x == -203000 and start.Y == 40 and start.z == 120)
    near(finish.x, start.x)
    near(finish.Y - start.Y, 1000000 * math.cos(math.rad(30)))
    near(finish.z - start.z, 500000)
    hit.distance = self.distance
    return self.distance ~= nil
end
local env = setmetatable({StaticFindObject = function(path)
    assert(path == "/Script/Engine.Default__KismetSystemLibrary")
    return trace
end}, {__index = _G})
local optics = assert(loadfile("mod/Scripts/optics.lua", "t", env))()

local properties = {
    DepthOfFieldSensorWidth = 24.576, bOverride_DepthOfFieldSensorWidth = true,
    DepthOfFieldFocalDistance = 73, bOverride_DepthOfFieldFocalDistance = false,
    DepthOfFieldFstop = 4, CameraISO = 250, AutoExposureBias = -1,
}
local failNextDistance = false
local pp = setmetatable({}, {__index = properties, __newindex = function(_, key, value)
    assert(key:match("DepthOfFieldSensorWidth$") or key:match("DepthOfFieldFocalDistance$"),
        "unexpected change to " .. key)
    if key == "DepthOfFieldFocalDistance" and failNextDistance then
        failNextDistance = false
        error("rejected reflected write")
    end
    properties[key] = value
end})
local s = {camera = camera, world = world, pawn = train, lens = {PostProcessSettings = pp},
    locationKeys = {x = "x", y = "Y", z = "z"},
    pose = {x = -203000, y = 40, z = 120, pitch = 30, yaw = 90, roll = 70, fov = 45}}

assert(optics.status(s):find("Photo DOF off"))
assert(optics.autofocus(s):find("no focusable surface"))
assert(not s.optics.enabled and properties.DepthOfFieldFocalDistance == 73)
trace.distance = 123.45
assert(optics.autofocus(s):find("AF lock"))
assert(pp.DepthOfFieldFocalDistance == 123.45 and pp.bOverride_DepthOfFieldFocalDistance)

-- Compare the sensor-normalized blur circle at infinity for the renderer and the
-- equivalent 36 mm aperture. The same factor also applies at finite subject depths.
local function blurCircle(width, fstop, fov, distanceCm)
    local focalMm = width / (2 * math.tan(math.rad(fov) / 2))
    return focalMm ^ 2 / (width * fstop * (distanceCm * 10 - focalMm))
end
local function checkBlur(expected)
    near(blurCircle(pp.DepthOfFieldSensorWidth, pp.DepthOfFieldFstop, s.pose.fov, pp.DepthOfFieldFocalDistance),
        blurCircle(36, expected, s.pose.fov, pp.DepthOfFieldFocalDistance))
end
checkBlur(2.8)
local distance = pp.DepthOfFieldFocalDistance
trace.distance = 0
assert(optics.autofocus(s):find("no focusable surface") and pp.DepthOfFieldFocalDistance == distance)
trace.distance = nil
assert(optics.autofocus(s):find("AF lock") and pp.DepthOfFieldFocalDistance == distance)

assert(optics.manual(s, -1, false):find("Manual"))
near(pp.DepthOfFieldFocalDistance, distance / 1.20)
optics.manual(s, 1, true)
near(pp.DepthOfFieldFocalDistance, distance / 1.20 * 1.01)
assert(optics.aperture(s, 1):find("f/3.2", 1, true))
checkBlur(3.2)
for _, multiplier in ipairs({2, 4, 8, 1}) do
    assert(optics.strength(s):find(multiplier .. "x DOF", 1, true))
    checkBlur(3.2 / multiplier)
end
s.pose.fov = 3
optics.refresh(s)
checkBlur(3.2)
assert(trace.calls == 4, "changing lenses or dials triggered another focus trace")

local beforeText, beforeWidth = optics.status(s), pp.DepthOfFieldSensorWidth
failNextDistance = true
assert(not pcall(optics.aperture, s, 1))
assert(optics.status(s) == beforeText and pp.DepthOfFieldSensorWidth == beforeWidth)
assert(optics.toggle(s):find("Photo DOF off"))
assert(pp.DepthOfFieldFocalDistance == 73 and not pp.bOverride_DepthOfFieldFocalDistance)
assert(pp.DepthOfFieldSensorWidth == 24.576 and pp.bOverride_DepthOfFieldSensorWidth)
optics.aperture(s, -1)
optics.refresh(s)
assert(pp.DepthOfFieldFocalDistance == 73)

trace.distance = 1
optics.autofocus(s)
assert(pp.DepthOfFieldFocalDistance > 36 / (20 * math.tan(math.rad(s.pose.fov) / 2)))
assert(pp.DepthOfFieldFstop == 4 and pp.CameraISO == 250 and pp.AutoExposureBias == -1)
print("Photo optics checks passed")
