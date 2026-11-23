local photo = {}

photo.frames = {
    {name = "Viewport"}, {name = "3:2", 3, 2}, {name = "4:3", 4, 3},
    {name = "1:1", 1, 1}, {name = "16:9", 16, 9}, {name = "5:4", 5, 4},
    {name = "21:9", 21, 9}, {name = "65:24", 65, 24},
}
photo.lenses = {16, 24, 35, 50, 85, 135, 200, 600}

function photo.frame(index, portrait)
    local frame = photo.frames[index]
    if portrait then return frame[2], frame[1] end
    return frame[1], frame[2]
end

-- Center the largest integer-pixel rectangle with exactly the chosen ratio.
function photo.crop(width, height, a, b)
    width, height = math.floor(width), math.floor(height)
    assert(width > 0 and height > 0, "Viewport has no image")
    local w, h = width, height
    if a then
        local scale = math.floor(math.min(width / a, height / b))
        assert(scale >= 1, "Viewport is too small for this frame")
        w, h = a * scale, b * scale
    end
    return {x = (width - w) // 2, y = (height - h) // 2, w = w, h = h}
end

function photo.lensFov(mm)
    return math.deg(2 * math.atan(36 / (2 * mm)))
end

local function clamp(value, low, high)
    return math.min(high, math.max(low, value))
end

-- Unreal's axes are X forward, Y right, Z up. Up/down follows gravity even
-- when the photographer banks the frame or looks directly at the rails.
function photo.move(pose, dt, axes)
    local f, r, u = axes.forward, axes.right, axes.up
    local mouseYaw, mousePitch = axes.mouseYaw or 0, axes.mousePitch or 0
    local stickYaw, stickPitch = axes.stickYaw or 0, axes.stickPitch or 0
    if f == 0 and r == 0 and u == 0 and axes.pitch == 0 and axes.yaw == 0
            and axes.roll == 0 and axes.zoom == 0 and mouseYaw == 0 and mousePitch == 0
            and stickYaw == 0 and stickPitch == 0 then return end
    dt = clamp(dt, 0, 0.1)
    -- Long lenses need a smaller angular change to cover the same portion
    -- of the frame. Arrow keys retain their fixed turn rates.
    local aimScale = math.min(1, math.tan(math.rad(pose.fov / 2)))
    local pitchRate = clamp(axes.pitch + stickPitch * aimScale, -1, 1)
    local yawRate = clamp(axes.yaw + stickYaw * aimScale, -1, 1)
    local pitch = clamp(pose.pitch + pitchRate * 65 * dt + mousePitch * aimScale, -89.9, 89.9)
    local yaw = (pose.yaw + yawRate * 80 * dt + mouseYaw * aimScale + 180) % 360 - 180
    local roll = (pose.roll + axes.roll * 55 * dt + 180) % 360 - 180
    local p, y = math.rad(pitch), math.rad(yaw)
    local cp, sp, cy, sy = math.cos(p), math.sin(p), math.cos(y), math.sin(y)
    local dx, dy, dz = f * cp * cy - r * sy, f * cp * sy + r * cy, f * sp + u
    local step = 80 * axes.speed * dt / math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
    return {x = pose.x + dx * step, y = pose.y + dy * step, z = pose.z + dz * step,
        yaw = yaw, pitch = pitch, roll = roll, fov = clamp(pose.fov + axes.zoom * 30 * dt, 2, 155)}
end

local sequence = 0
function photo.request(dir, crop, withLinear)
    assert(type(dir) == "string" and dir ~= "", "Screenshot directory unavailable")
    local base = os.date("Denshattack_%Y%m%d_%H%M%S")
    repeat
        sequence = sequence + 1
        local filename = string.format("%s_%04d.png", base, sequence)
        local path = dir:gsub("[/\\]+$", "") .. "/" .. filename
        local existing = io.open(path, "rb")
        if existing then
            existing:close()
        else
            local request = {filename = filename, path = path, crop = crop}
            if not withLinear then return request end
            local exrPath = path:gsub("%.png$", ".exr")
            local exr = io.open(exrPath, "rb")
            if not exr then
                request.linear = {filename = filename:gsub("%.png$", ".exr"), path = exrPath, crop = crop}
                return request
            end
            exr:close()
        end
    until false
end

-- Screenshot writes are asynchronous. Wait for the final PNG chunk and check
-- the stored dimensions before reporting success or restoring the game view.
function photo.checkFile(request)
    local file = io.open(request.path, "rb")
    if not file then return false end
    local header = file:read(24)
    local tail = file:seek("end", -12) and file:read(12)
    file:close()
    if not header or #header < 24 or tail ~= "\0\0\0\0IEND\174\66\96\130" then return false end
    if header:sub(1, 8) ~= "\137PNG\r\n\26\n" or header:sub(13, 16) ~= "IHDR" then
        return false, "Capture has an unexpected file format"
    end
    local w, h = string.unpack(">I4I4", header, 17)
    if w ~= request.crop.w or h ~= request.crop.h then
        return false, ("Capture is %dx%d, expected %dx%d: %s"):format(w, h, request.crop.w, request.crop.h, request.path)
    end
    return true
end

return photo
