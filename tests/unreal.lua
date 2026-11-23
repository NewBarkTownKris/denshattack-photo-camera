-- Run from the repository root with lua tests/unreal.lua.
local function object(properties)
    local value = properties or {}
    function value:IsValid() return not self.destroyed end
    function value:GetAddress() return self end
    return value
end

local function widget(visibility, inViewport)
    return object({
        visibility = visibility,
        GetVisibility = function(self) return self.visibility end,
        SetVisibility = function(self, setting) self.visibility = setting end,
        IsInViewport = function() return inViewport end,
    })
end

local viewport, world, pawn, original = object(), object(), object(), object()
local engine = object({GameViewport = viewport})
local hud = object({bShowHUD = true})
local visible, nested, collapsed = widget(3, true), widget(0, false), widget(1, true)
local pc = object({view = original, PrimaryActorTick = {bTickEvenWhenPaused = false}})
local gameplay = object()
function gameplay:GetPlayerController() return pc end
function gameplay:IsGamePaused(w) return w.paused end
function gameplay:SetGamePaused(w, value) w.paused = value return true end
function pc:K2_GetPawn() return pawn end
function pc:GetWorld() return world end
function pc:GetHUD() return hud end
function pc:GetViewTarget() return self.view end
function pc:SetTickableWhenPaused(value) self.PrimaryActorTick.bTickEvenWhenPaused = value end
function pc:SetViewTargetWithBlend(target)
    if target ~= original then
        assert(target.applied, "view was switched before applying the complete camera pose")
        assert(target.angle.pitch == -24.25)
        assert(target.lens.FieldOfView == 100)
    end
    self.view = target
end
pc.PlayerCameraManager = object({
    GetCameraLocation = function() return {X = -2312044.25, Y = -13990, Z = 252535} end,
    -- Observed in the Denshattack! UE 5.6.1 shipping build.
    GetCameraRotation = function() return {pitch = -24.25, Yaw = 71, Roll = -14} end,
    GetFOVAngle = function() return 100 end,
})
function world:SpawnActor(_, xyz, angle)
    -- UE4SS native SpawnActor parses canonical keys. Reflected setters use
    -- the game-specific spelling returned by GetCameraRotation.
    assert(xyz.X == -2312044.25 and xyz.Y == -13990 and xyz.Z == 252535)
    assert(angle.Pitch == -24.25 and angle.Yaw == 71 and angle.Roll == -14)
    local camera = object({lens = object({FieldOfView = 90})})
    function camera:GetComponentByClass() return self.lens end
    function camera.lens:SetFieldOfView(value) self.FieldOfView = value end
    function camera.lens:SetConstraintAspectRatio(value) self.constrain = value end
    function camera:K2_SetActorLocationAndRotation(location, rot)
        assert(type(rot.pitch) == "number" and rot.Pitch == nil)
        assert(rot.Yaw == 71 and rot.Roll == -14)
        self.applied, self.location, self.angle = true, location, rot
        return not world.rejectTransform
    end
    function camera:EnableInput() self.input = true end
    function camera:DisableInput() self.input = false end
    function camera:K2_DestroyActor() self.destroyed = true end
    self.lastCamera = camera
    return camera
end

local screenshotCommand, mounted
local env = setmetatable({
    FindFirstOf = function(name) assert(name == "GameEngine") return engine end,
    FindAllOf = function(name) assert(name == "UserWidget") return {visible, nested, collapsed} end,
    StaticFindObject = function(path)
        if path == "/Script/Engine.Default__GameplayStatics" then return gameplay end
        if path == "/Script/Engine.Default__BlueprintPathsLibrary" then
            return object({DirectoryExists = function(_, dir)
                assert(dir:find("/Saved/DenshattackPhotoFolders/", 1, true))
                return mounted
            end})
        end
        if path == "/Script/UMG.Default__WidgetLayoutLibrary" then
            return object({GetViewportSize = function() return {X=1920, Y=1080} end})
        end
        if path == "/Script/Engine.Default__KismetSystemLibrary" then
            return object({ExecuteConsoleCommand = function(_, _, cmd) screenshotCommand = cmd end})
        end
        assert(path == "/Script/Engine.CameraComponent" or path == "/Script/Engine.CameraActor")
        return object()
    end,
}, {__index = _G})
local adapter = assert(loadfile("mod/Scripts/unreal.lua", "t", env))()

local session = assert(adapter.open())
assert(world.paused and pc.view == session.camera and pc.PrimaryActorTick.bTickEvenWhenPaused)
assert(not hud.bShowHUD and visible.visibility == 2 and nested.visibility == 0 and collapsed.visibility == 1)
session.pose.pitch, session.pose.z = -12, 252540
assert(adapter.apply(session, session.pose))
assert(session.camera.angle.pitch == -12 and session.camera.location.Z == 252540)

local saved = "C:/users/steamuser/AppData/Local/Denshattack_Proto/Saved"
env.os = setmetatable({getenv = function(name)
    assert(name == "LOCALAPPDATA")
    return "C:\\users\\steamuser\\AppData\\Local"
end}, {__index = os})
local contents, heartbeat, pickerRequested
env.io = {open = function(path, mode)
    if path == saved .. "/DenshattackPhotoDirectoryPicker.ready" then
        if not heartbeat then return nil, "missing", 2 end
        local file = assert(io.tmpfile())
        file:write(heartbeat)
        file:seek("set")
        return file
    end
    if path == saved .. "/DenshattackPhotoDirectoryPicker.request" then
        assert(mode == "wb")
        pickerRequested = true
        return io.tmpfile()
    end
    assert(path == saved .. "/DenshattackPhotoDirectory.txt" and mode == "rb")
    if not contents then return nil, "missing", 2 end
    local file = assert(io.tmpfile())
    file:write(contents)
    file:seek("set")
    return file
end}
assert(adapter.screenshotDir(session) == saved .. "/Screenshots/Windows")
local first, second = string.rep("a", 64), string.rep("b", 64)
mounted = true
contents = first .. "\n/home/test/Pictures/café | shots\n"
local dir, _, display = adapter.screenshotDir(session)
assert(dir == saved .. "/DenshattackPhotoFolders/" .. first and display == "/home/test/Pictures/café | shots")
contents = first .. "\nD:\\Photos\\撮影\n"
local native, _, nativeDisplay = adapter.screenshotDir(session)
assert(native == dir and nativeDisplay == "D:\\Photos\\撮影")
contents = first .. "\nD:relative\n"
assert(not adapter.screenshotDir(session))
local request = {path=dir .. "/portrait.png", filename="portrait.png"}
contents = second .. "\n/media/new drive\n"
assert(adapter.screenshotDir(session) == saved .. "/DenshattackPhotoFolders/" .. second)
assert(adapter.capture(session, request))
assert(screenshotCommand:find(request.path, 1, true), "finish an in-flight shot in its original folder")
mounted = false
assert(not adapter.screenshotDir(session))
contents = "../elsewhere\n/home/test\n"
assert(not adapter.screenshotDir(session))
contents = nil
assert(adapter.screenshotDir(session) == saved .. "/Screenshots/Windows")
assert(not adapter.requestDirectoryPicker() and not pickerRequested)
heartbeat = os.time() - 20
assert(not adapter.requestDirectoryPicker() and not pickerRequested)
heartbeat = os.time()
assert(adapter.requestDirectoryPicker() and pickerRequested)
assert(adapter.close(session))
assert(not world.paused and pc.view == original and session.camera.destroyed and not session.camera.input)
assert(hud.bShowHUD and visible.visibility == 3 and nested.visibility == 0 and collapsed.visibility == 1)
assert(not pc.PrimaryActorTick.bTickEvenWhenPaused and not pc.bShouldPerformFullTickWhenPaused)

world.rejectTransform = true
local failed, err = adapter.open()
assert(not failed and err:find("set initial camera transform", 1, true))
assert(not world.paused and pc.view == original and world.lastCamera.destroyed)
assert(hud.bShowHUD and visible.visibility == 3)
print("Unreal adapter checks passed")
