local folder = assert(debug.getinfo(1, "S").source:match("^@(.+[/\\])"))
local gamepad = dofile(folder .. "gamepad.lua")
local mouselook = dofile(folder .. "mouselook.lua")
local input = {}
local active

local bindings = {
    help = "F1", directory = "F2", gradingCapture = "F3",
    frame = "F5", portrait = "F6", lens = "F7",
    toggle = "F8", capture = "F9", level = "F10",
    finder = "H", grid = "G", reticle = "R", lines = "V", dof = "B", autofocus = "N",
    nearer = "J", farther = "K", fineFocus = "L", wider = "U", narrower = "I", strength = "Y",
}

local keys = {}
local function key(name)
    if not keys[name] then
        keys[name] = { KeyName = FName(name) }
    end
    return keys[name]
end

local function held(controller, name)
    return controller:IsInputKeyDown(key(name))
end

local function readAnalog(controller, name)
    return controller:GetInputAnalogKeyState(key(name))
end

local function axis(controller, positive, negative)
    return (held(controller, positive) and 1 or 0) - (held(controller, negative) and 1 or 0)
end

local function cameraAxes(pc, readMouse, now)
    local speed = 1
    if held(pc, "LeftControl") or held(pc, "RightControl") then
        speed = 0.2
    elseif held(pc, "LeftShift") or held(pc, "RightShift") then
        speed = 4
    end
    local axes = {
        forward = axis(pc, "W", "S"), right = axis(pc, "D", "A"), up = axis(pc, "E", "Q"),
        yaw = axis(pc, "Right", "Left"), pitch = axis(pc, "Up", "Down"), roll = axis(pc, "X", "Z"),
        zoom = axis(pc, "RightBracket", "LeftBracket"), speed = speed,
    }
    gamepad.apply(axes, readAnalog, pc)
    axes.mouseYaw, axes.mousePitch = readMouse(now)
    return axes
end

-- One-shot actions use UE4SS's foreground key binds. Movement is read from
-- the local player's Unreal input state only while the photo session exists.
function input.install(callbacks)
    assert(EngineTickAvailable or ProcessEventAvailable, "UE4SS has no game-thread scheduler available")
    for action, name in pairs(bindings) do
        local invoke = assert(callbacks[action], "Missing photo camera action: " .. action)
        RegisterKeyBind(Key[name], function()
            local function dispatch()
                if action == "toggle" or active then invoke() end
            end
            local method = EngineTickAvailable and EGameThreadMethod.EngineTick
                or EGameThreadMethod.ProcessEvent
            ExecuteInGameThread(dispatch, method)
        end)
    end
end

-- Call on the game thread. stop() is idempotent, including when called from tick.
function input.stop(loop)
    if not loop or active ~= loop then return end
    active = nil
    CancelDelayedAction(loop.handle)
end

-- tick(seconds, axes) runs even when all axes are neutral. Return false to
-- stop polling. Errors stop the loop before handing control to onError.
function input.start(pc, tick, onError)
    assert(not active, "Photo camera input loop already started")
    assert(pc and pc:IsValid(), "Local player controller is unavailable")
    local clock = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    assert(clock and clock:IsValid(), "Gameplay clock is unavailable")
    local previousTime = clock:GetRealTimeSeconds(pc)
    local readMouse = mouselook.reader(pc, readAnalog)
    local loop = {}
    local function step()
        assert(pc:IsValid(), "Photo camera player controller expired")
        local now = clock:GetRealTimeSeconds(pc)
        local seconds = math.min(0.1, math.max(0, now - previousTime))
        previousTime = now
        return tick(seconds, cameraAxes(pc, readMouse, now))
    end
    local function update()
        if active ~= loop then return end
        local ok, keepGoing = pcall(step)
        if not ok or keepGoing == false then input.stop(loop) end
        if not ok then onError(keepGoing) end
    end
    -- UE4SS's engine frame counter continues when the UWorld is paused.
    -- Older configurations can dispatch wall-clock delayed actions instead.
    if EngineTickAvailable then
        loop.handle = LoopInGameThreadAfterFrames(1, update)
    else
        loop.handle = LoopInGameThreadWithDelay(16, update)
    end
    assert(loop.handle, "Failed to schedule the photo camera input loop")
    active = loop
    return loop
end

-- Flush pressed keys before restoring gameplay input. Some games omit the
-- Enhanced Input library, so an unavailable flush must allow cleanup to finish.
function input.flush(pc)
    if not pc or not pc:IsValid() then return false end
    local library = StaticFindObject("/Script/EnhancedInput.Default__EnhancedInputLibrary")
    if not library or not library:IsValid() then return false end
    return pcall(function() library:FlushPlayerInput(pc) end)
end

return input
