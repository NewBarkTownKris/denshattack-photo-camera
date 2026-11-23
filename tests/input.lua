-- Exercise UE4SS's normal keyboard dispatch and the paused player-controller loop.
local keybinds, held, analog, impulses, calls = {}, {}, {}, {}, {}
local now, frames, canceled = 10, 0, 0
local loop, scheduled, lastAxes, studioOpen, unsupported
local finderVisible = true
local pc = {}
function pc:IsValid() return true end
function pc:IsInputKeyDown(key)
    if unsupported and key.KeyName:match("^Gamepad_") then error("unavailable") end
    return held[key.KeyName] == true
end
function pc:GetInputAnalogKeyState(key)
    if unsupported then error("unavailable") end
    return analog[key.KeyName] or 0
end
function pc:WasInputKeyJustPressed(key)
    if unsupported then error("unavailable") end
    return impulses[key.KeyName] == true
end
local clock = {IsValid=function() return true end, GetRealTimeSeconds=function() return now end}
local env = setmetatable({
    FName = function(v) return v end,
    Key = setmetatable({}, {__index=function(_, v) return v end}),
    EngineTickAvailable=true, EGameThreadMethod={EngineTick=1},
    RegisterKeyBind=function(key,fn) keybinds[key]=fn end,
    ExecuteInGameThread=function(fn) fn() end,
    StaticFindObject=function() return clock end,
    LoopInGameThreadAfterFrames=function(_,fn) scheduled=fn; return 42 end,
    CancelDelayedAction=function(h) assert(h==42); canceled=canceled+1 end,
}, {__index=_G})
local input = assert(loadfile("mod/Scripts/input.lua", "t", env))()
local function start()
    loop = input.start(pc, function(_, a) frames=frames+1; lastAxes=a; return true end,
        function(err) error(err) end, function() return studioOpen end, function() return finderVisible end)
end
local callbacks = setmetatable({}, {__index=function(_, action)
    return function() calls[action]=(calls[action] or 0)+1 end
end})
callbacks.studio = function() studioOpen=not studioOpen end
callbacks.toggle = function()
    if loop then input.stop(loop); loop=nil else start() end
end
input.install(callbacks)
local function frame()
    now=now+.016
    scheduled()
    impulses={}
end
local function press(name)
    held[name]=true
    frame()
    held[name]=false
    frame()
end

keybinds.F9()
assert(not calls.capture and not scheduled)
keybinds.T()
assert(not calls.tracking)
held.Gamepad_FaceButton_Bottom, held.Gamepad_Special_Left, held.LeftMouseButton = true, true, true
keybinds.F8()
frame()
held.Gamepad_FaceButton_Bottom, held.Gamepad_Special_Left, held.LeftMouseButton = false, false, false
frame()
assert(loop and not calls.capture, "entry buttons must clear before activating")
press("Gamepad_FaceButton_Bottom")
held.Gamepad_FaceButton_Top=true
frame(); frame(); frame()
held.Gamepad_FaceButton_Top=false; frame()
assert(calls.capture==1 and calls.gradingCapture==1)
press("Gamepad_RightThumbstick")
assert(calls.autofocus==1)
keybinds.T()
assert(calls.tracking == 1)
held.Gamepad_LeftShoulder=true; frame(); assert(lastAxes.up==-1)
held.Gamepad_RightShoulder=true; frame(); assert(lastAxes.up==0)
held.Gamepad_LeftShoulder=false; held.E=true; frame(); assert(lastAxes.up==1)
held.Gamepad_RightShoulder=false; held.E=false

-- Digital wheel pulses, including duplicate callbacks in one engine frame.
impulses.MouseScrollUp=true
now=now+.016
scheduled(); scheduled()
impulses={}
assert(calls.farther==1)
impulses.MouseScrollDown=true; frame()
assert(calls.nearer==1)
held.RightShift=true
impulses.MouseScrollUp=true; frame()
impulses.MouseScrollDown=true; frame()
held.RightShift=false
assert(calls.wider==1 and calls.narrower==1)
held.LeftControl=true; impulses.MouseScrollUp=true; frame()
assert(calls.wider==2)
held.RightAlt=true; impulses.MouseScrollUp=true; frame()
impulses.MouseScrollDown=true; frame()
assert(calls.isoUp==1 and calls.isoDown==1)
held.LeftControl=false; impulses.MouseScrollUp=true; frame()
impulses.MouseScrollDown=true; frame()
held.RightAlt=false
assert(calls.faster==1 and calls.slower==1)
-- Fall back to analog-only wheel on builds which do not report the scroll keys.
analog.MouseWheelAxis=1
frame(); frame(); frame()
assert(calls.farther==2)
analog.MouseWheelAxis=0; frame()
analog.MouseWheelAxis=-1; frame()
assert(calls.nearer==2)
analog.MouseWheelAxis=0; frame()

press("Gamepad_LeftThumbstick")
assert(studioOpen)
held.Gamepad_RightShoulder=true; frame(); assert(lastAxes.up==0)
held.Gamepad_RightShoulder=false
held.Gamepad_DPad_Down=true; impulses.MouseScrollUp=true; frame()
assert(lastAxes.menuY==1 and calls.farther==2)
held.Gamepad_DPad_Down=false
unsupported=true; frame()
assert(lastAxes.menuY==0 and calls.farther==2 and loop)
unsupported=false; frame()
held.LeftMouseButton=true; frame()
press("Gamepad_LeftThumbstick")
assert(not studioOpen)
frame(); held.LeftMouseButton=false; frame()
assert(calls.capture==1, "release a Studio click before allowing the mouse shutter")

-- View held while another action is touched cancels the resume chord.
held.Gamepad_Special_Left=true; frame()
press("Gamepad_FaceButton_Bottom")
held.Gamepad_Special_Left=false; frame()
assert(loop and calls.capture==1)
-- Two shutter buttons arriving together choose neither output.
held.Gamepad_FaceButton_Bottom, held.Gamepad_FaceButton_Top=true,true
frame()
held.Gamepad_FaceButton_Bottom, held.Gamepad_FaceButton_Top=false,false
frame()
assert(calls.capture==1 and calls.gradingCapture==1)
finderVisible=false
press("LeftMouseButton"); held.MiddleMouseButton=true; frame()
finderVisible=true; frame(); held.MiddleMouseButton=false; frame()
assert(calls.capture==1 and calls.autofocus==1)
press("LeftMouseButton"); press("MiddleMouseButton")
assert(calls.capture==2 and calls.autofocus==2)
held.Gamepad_Special_Left=true; frame()
assert(loop)
local previousFrames=frames
held.Gamepad_Special_Left=false; frame()
assert(not loop and canceled==1 and frames==previousFrames)
held.Gamepad_FaceButton_Bottom=true; frame()
assert(calls.capture==2 and frames==previousFrames, "queued ticks after exit must ignore the controller")
print("Photo-only controller shutter, Studio, autofocus, resume and focus/aperture wheel checks passed.")
