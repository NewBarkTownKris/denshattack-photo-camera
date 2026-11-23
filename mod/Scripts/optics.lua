local optics = {}

local apertures = {1, 1.1, 1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8, 3.2, 3.5,
    4, 4.5, 5, 5.6, 6.3, 7.1, 8, 9, 10, 11, 13, 14, 16}
local strengths = {1, 2, 4, 8}
local sensorWidth = 36 -- mm, matches photo.lensFov
local maxDistance = 1000000 -- cm

local function settings(session)
    if not session.optics then
        session.optics = {enabled = false, distance = 300, aperture = 10, strength = 1, mode = "Manual"}
    end
    return session.optics
end

local function focalLength(session)
    return sensorWidth / (2 * math.tan(math.rad(session.pose.fov) / 2))
end

local function focusDistance(session, distance)
    -- A physical lens cannot form an image of a subject inside its focal length.
    local minimum = math.max(2, focalLength(session) * 1.05 / 10)
    return math.max(minimum, math.min(maxDistance, distance))
end

function optics.status(session)
    local s = settings(session)
    local mode = s.enabled and s.mode or "Photo DOF off"
    return ("%s | %.2f m | f/%g equiv. | %dx DOF"):format(mode,
        focusDistance(session, s.distance) / 100, apertures[s.aperture], strengths[s.strength])
end

local function readOverrides(pp)
    return {
        DepthOfFieldSensorWidth = pp.DepthOfFieldSensorWidth,
        DepthOfFieldFocalDistance = pp.DepthOfFieldFocalDistance,
        bOverride_DepthOfFieldSensorWidth = pp.bOverride_DepthOfFieldSensorWidth,
        bOverride_DepthOfFieldFocalDistance = pp.bOverride_DepthOfFieldFocalDistance,
    }
end

local function writeOverrides(pp, values)
    pp.DepthOfFieldSensorWidth = values.DepthOfFieldSensorWidth
    pp.DepthOfFieldFocalDistance = values.DepthOfFieldFocalDistance
    pp.bOverride_DepthOfFieldSensorWidth = values.bOverride_DepthOfFieldSensorWidth
    pp.bOverride_DepthOfFieldFocalDistance = values.bOverride_DepthOfFieldFocalDistance
end

local function apply(session, changes)
    local old = settings(session)
    local s = {}
    for key, value in pairs(old) do s[key] = value end
    for key, value in pairs(changes) do s[key] = value end
    if s.enabled or old.enabled then
        local pp = session.lens.PostProcessSettings
        local previous = readOverrides(pp)
        if not old.enabled then s.baseline = previous end
        local wanted = s.baseline
        if s.enabled then
            local distance = focusDistance(session, s.distance)
            local focusMm = distance * 10
            local focalMm = focalLength(session)
            local engineFstop = pp.DepthOfFieldFstop
            assert(type(engineFstop) == "number" and engineFstop > 0, "No usable camera f-stop for DOF")
            local targetFstop = apertures[s.aperture] / strengths[s.strength]
            -- At a fixed FOV, focal length scales with the sensor width. Solve
            -- for a width giving the same normalized thin-lens circle of confusion
            -- as a 36 mm camera at targetFstop. Unreal also uses its f-stop for
            -- physical exposure, so leave that property and the exposure meter alone.
            local width = sensorWidth * engineFstop * focusMm /
                (targetFstop * (focusMm - focalMm) + engineFstop * focalMm)
            wanted = {
                DepthOfFieldSensorWidth = width, DepthOfFieldFocalDistance = distance,
                bOverride_DepthOfFieldSensorWidth = true, bOverride_DepthOfFieldFocalDistance = true,
            }
        else
            s.baseline = nil
        end
        local ok, err = pcall(writeOverrides, pp, wanted)
        if not ok then
            local restored, reason = pcall(writeOverrides, pp, previous)
            if not restored then error(tostring(err) .. " (could not restore focus settings: " .. tostring(reason) .. ")") end
            error(err)
        end
    end
    session.optics = s
    return optics.status(session)
end

function optics.toggle(session)
    return apply(session, {enabled = not settings(session).enabled})
end

-- Recalculate the optical model after a change to the horizontal field of view.
function optics.refresh(session)
    if session.optics and session.optics.enabled then apply(session, {}) end
end

function optics.manual(session, direction, fine)
    local oldDistance = focusDistance(session, settings(session).distance)
    local factor = fine and 1.01 or 1.20
    return apply(session, {enabled = true, mode = "Manual",
        distance = focusDistance(session, oldDistance * factor ^ direction)})
end

function optics.aperture(session, direction)
    local index = math.max(1, math.min(#apertures, settings(session).aperture + direction))
    return apply(session, {aperture = index})
end

function optics.strength(session)
    return apply(session, {strength = settings(session).strength % #strengths + 1})
end

function optics.autofocus(session)
    local system = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    assert(system and system:IsValid(), "Unreal collision tracing is unavailable")
    local pose, keys = session.pose, session.locationKeys
    local pitch, yaw = math.rad(pose.pitch), math.rad(pose.yaw)
    local horizontal = maxDistance * math.cos(pitch)
    local start = {[keys.x] = pose.x, [keys.y] = pose.y, [keys.z] = pose.z}
    local finish = {
        [keys.x] = pose.x + horizontal * math.cos(yaw),
        [keys.y] = pose.y + horizontal * math.sin(yaw),
        [keys.z] = pose.z + maxDistance * math.sin(pitch),
    }
    local hit, color = {}, {R = 0, G = 0, B = 0, A = 0}
    -- Use the camera as world context and ignore it. The player train must
    -- remain eligible for focus. The trace has no debug drawing in the shot.
    local found = system:LineTraceSingle(session.camera, start, finish, 0, true, {}, 0, hit, true, color, color, 0)
    if found then
        for key, value in pairs(hit) do
            if type(key) == "string" and key:lower() == "distance" and type(value) == "number"
                    and value > 0 and value <= maxDistance then
                return apply(session, {enabled = true, mode = "AF lock", distance = focusDistance(session, value)})
            end
        end
    end
    return "AF found no focusable surface | " .. optics.status(session)
end

return optics
