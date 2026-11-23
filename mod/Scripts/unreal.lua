-- Game-thread adapter for Denshattack's Win64 build and UE4SS.
local unreal = {}
local pendingRestore

local function valid(object)
    return object ~= nil and object:IsValid()
end

local function requireObject(object, description)
    assert(valid(object), description)
    return object
end

local function same(first, second)
    return valid(first) and valid(second) and first:GetAddress() == second:GetAddress()
end

local function object(path)
    return requireObject(StaticFindObject(path), "Missing Unreal object " .. path)
end

local function position(pose)
    return {X = pose.x, Y = pose.y, Z = pose.z}
end

local function rotation(pose)
    return {Pitch = pose.pitch, Yaw = pose.yaw, Roll = pose.roll}
end

local function fields(value, names)
    local result, keys = {}, {}
    -- Shipping FNames may have different display casing. UE4SS 4 serializes
    -- struct returns with those exact keys and uses rawget when writing them.
    if type(value) == "table" then
        for key in pairs(value) do
            if type(key) == "string" then
                keys[key:lower()] = key
            end
        end
    end
    for _, name in ipairs(names) do
        local lower = name:lower()
        local key = keys[lower] or name
        local item = value and value[key]
        if type(item) ~= "number" or item ~= item or math.abs(item) == math.huge then return nil end
        result[lower], keys[lower] = item, key
    end
    return result, keys
end

local function readPose(session, manager)
    local locNames, rotNames = {"X", "Y", "Z"}, {"Pitch", "Yaw", "Roll"}
    local location, locationKeys = fields(manager:GetCameraLocation(), locNames)
    local angles, angleKeys = fields(manager:GetCameraRotation(), rotNames)
    if not location or not angles then
        -- Read the manager's evaluated POV directly if the convenience
        -- functions returned an incomplete struct on this loader/build.
        local pov = manager.CameraCachePrivate.POV
        if not location then location, locationKeys = fields(pov.Location, locNames) end
        if not angles then angles, angleKeys = fields(pov.Rotation, rotNames) end
    end
    assert(location and angles, "The engine returned an incomplete camera transform")
    local fov = manager:GetFOVAngle()
    assert(type(fov) == "number" and fov > 0 and fov < 180, "The engine returned an invalid camera FOV")
    session.locationKeys, session.angleKeys = locationKeys, angleKeys
    return {x = location.x, y = location.y, z = location.z, pitch = angles.pitch,
        yaw = angles.yaw, roll = angles.roll, fov = fov}
end

local function applyPose(session, pose)
    local location, angles = session.locationKeys, session.angleKeys
    local xyz = {[location.x] = pose.x, [location.y] = pose.y, [location.z] = pose.z}
    local pyr = {[angles.pitch] = pose.pitch, [angles.yaw] = pose.yaw, [angles.roll] = pose.roll}
    local moved = session.camera:K2_SetActorLocationAndRotation(xyz, pyr, false, {}, true)
    assert(moved, "Could not move the detached camera")
    if session.lens.FieldOfView ~= pose.fov then session.lens:SetFieldOfView(pose.fov) end
end

local function viewTarget(pc, actor)
    pc:SetViewTargetWithBlend(actor, 0, 0, 0, false)
end

-- Each successful change registers its inverse. An invalidated UObject needs
-- no restoration. Retry failed operations if close() is called again.
local function defer(session, label, undo)
    table.insert(session.undos, {label = label, undo = undo})
end
unreal.defer = defer

function unreal.close(session)
    if not session then return true end
    local errors = {}
    for index = #session.undos, 1, -1 do
        local entry = session.undos[index]
        local ok, err = pcall(entry.undo)
        if ok then
            table.remove(session.undos, index)
        else
            table.insert(errors, entry.label .. ": " .. tostring(err))
        end
    end
    session.closed = true
    if #errors > 0 then
        pendingRestore = session
        return false, table.concat(errors, "; ")
    end
    if pendingRestore == session then pendingRestore = nil end
    return true
end

local function hideHud(session)
    local hud = session.pc:GetHUD()
    if valid(hud) and hud.bShowHUD then
        hud.bShowHUD = false
        defer(session, "restore canvas HUD", function()
            if valid(hud) then hud.bShowHUD = true end
        end)
    end

    -- FindAllOf returns UObject wrappers. Entries in a reflected
    -- GetAllWidgetsOfClass out-array are RemoteUnrealParam on UE4SS v4.
    local widgets = FindAllOf("UserWidget") or {}
    -- ESlateVisibility: Visible=0, Collapsed=1, Hidden=2, HitTestInvisible=3,
    -- SelfHitTestInvisible=4. Keep hidden roots and nested widget state intact.
    for _, widget in ipairs(widgets) do
        if valid(widget) and widget:IsInViewport() then
            local visibility = widget:GetVisibility()
            if visibility ~= 1 and visibility ~= 2 then
                widget:SetVisibility(2)
                defer(session, "restore viewport widget", function()
                    if valid(widget) and widget:GetVisibility() == 2 then
                        widget:SetVisibility(visibility)
                    end
                end)
            end
        end
    end
end

local function start(session)
    session.stage = "find gameplay controller and camera"
    local game = requireObject(FindFirstOf("GameEngine"), "Game engine is not ready")
    local viewport = requireObject(game.GameViewport, "The game has no viewport")
    local api = object("/Script/Engine.Default__GameplayStatics")
    local pc = requireObject(api:GetPlayerController(viewport, 0), "Enter a level before using the camera")
    local pawn = requireObject(pc:K2_GetPawn(), "The local player has no pawn")
    local world = requireObject(pc:GetWorld(), "The level has no active world")
    assert(not api:IsGamePaused(world), "Close the game's pause menu before entering photo mode")
    local previous = requireObject(pc:GetViewTarget(), "The game has no active view target")
    local manager = requireObject(pc.PlayerCameraManager, "The player has no camera manager")
    session.stage = "read rendered camera transform"
    local pose = readPose(session, manager)
    session.pc, session.world, session.pawn = pc, world, pawn
    session.pose, session.api, session.viewportClient = pose, api, viewport

    session.stage = "pause simulation"
    assert(api:SetGamePaused(world, true), "The game declined the pause request")
    defer(session, "release world pause", function()
        -- The retained world context prevents unpausing a different map on travel.
        if valid(world) and api:IsGamePaused(world) then
            assert(api:SetGamePaused(world, false), "The game declined the resume request")
        end
    end)
    assert(api:IsGamePaused(world), "World pause did not take effect")

    session.stage = "spawn detached camera"
    local camera = requireObject(world:SpawnActor(object("/Script/Engine.CameraActor"),
        position(pose), rotation(pose)), "Could not spawn the photo camera")
    session.camera = camera
    defer(session, "remove camera actor", function()
        if valid(camera) then camera:K2_DestroyActor() end
    end)
    local lens = requireObject(camera:GetComponentByClass(object("/Script/Engine.CameraComponent")),
        "The detached camera has no camera component")
    session.lens = lens
    session.stage = "set initial camera transform"
    applyPose(session, pose)
    lens:SetConstraintAspectRatio(false)

    -- Input still reaches the player input device for polling. The camera's
    -- empty input component blocks lower gameplay bindings while it is active.
    session.stage = "take camera input"
    camera.bBlockInput = true
    camera.InputPriority = 100000
    camera:EnableInput(pc)
    defer(session, "remove photo input", function()
        if valid(pc) and valid(camera) then
            camera:DisableInput(pc)
        end
    end)
    session.stage = "enable paused camera updates"
    local tickPaused = pc.PrimaryActorTick.bTickEvenWhenPaused
    if not tickPaused then
        pc:SetTickableWhenPaused(true)
        defer(session, "restore controller tick", function()
            if valid(pc) then pc:SetTickableWhenPaused(false) end
        end)
    end
    if not pc.bShouldPerformFullTickWhenPaused then
        pc.bShouldPerformFullTickWhenPaused = true
        defer(session, "restore paused camera updates", function()
            if valid(pc) then pc.bShouldPerformFullTickWhenPaused = false end
        end)
    end

    session.stage = "hide gameplay HUD"
    hideHud(session)
    session.stage = "switch view target"
    viewTarget(pc, camera)
    defer(session, "restore game view", function()
        if valid(pc) and same(pc:GetWorld(), world) and same(pc:GetViewTarget(), camera) then
            local target = valid(previous) and previous or pc:K2_GetPawn()
            if valid(target) then viewTarget(pc, target) end
        end
    end)
    assert(same(pc:GetViewTarget(), camera), "The game kept control of its camera")
end

function unreal.open()
    if pendingRestore then
        local ok, err = unreal.close(pendingRestore)
        if not ok then return nil, "Gameplay restore still pending: " .. err end
        return nil, "Gameplay restored. Press F8 again to enter photo mode"
    end
    local session = {undos = {}}
    local ok, err = xpcall(start, function(err)
        return debug.traceback((session.stage or "enter photo mode") .. ": " .. tostring(err), 2)
    end, session)
    if not ok then
        local restored, cleanupError = unreal.close(session)
        if not restored then err = tostring(err) .. " (cleanup: " .. cleanupError .. ")" end
        return nil, err
    end
    return session
end

function unreal.alive(session)
    if not session or session.closed then return false, "Photo session is closed" end
    local ok, active = pcall(function()
        return valid(session.pc) and valid(session.viewportClient) and valid(session.camera)
            and valid(session.lens) and same(session.pc:GetWorld(), session.world)
            and same(session.api:GetPlayerController(session.viewportClient, 0), session.pc)
            and same(session.pc:K2_GetPawn(), session.pawn)
            and session.api:IsGamePaused(session.world)
            and same(session.pc:GetViewTarget(), session.camera)
    end)
    if not ok then return false, active end
    if not active then return false, "The game changed world, pause, pawn, or view target" end
    return true
end

function unreal.time(session)
    return session.api:GetRealTimeSeconds(session.world)
end

function unreal.apply(session, pose)
    return pcall(applyPose, session, pose)
end

function unreal.frame(session, ratio)
    return pcall(function()
        if ratio ~= nil then
            assert(type(ratio) == "number" and ratio > 0 and ratio < math.huge, "Invalid frame ratio")
            session.lens:SetAspectRatio(ratio)
        end
        session.lens:SetConstraintAspectRatio(ratio ~= nil)
    end)
end

function unreal.viewport(session)
    local ok, width, height = pcall(function()
        local size = object("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(session.pc)
        assert(size.X >= 1 and size.Y >= 1, "Game viewport has no drawable area")
        return math.floor(size.X), math.floor(size.Y)
    end)
    if not ok then return nil, width end
    return width, height
end

local function savedDirectory()
    local appData = os.getenv("LOCALAPPDATA")
    if appData and appData ~= "" then
        return appData:gsub("\\", "/"):gsub("/+$", "") .. "/Denshattack_Proto/Saved"
    end
end

function unreal.requestDirectoryPicker()
    local saved = savedDirectory()
    if not saved then return nil, "Could not locate the photo settings" end
    local ready = io.open(saved .. "/DenshattackPhotoDirectoryPicker.ready", "rb")
    local heartbeat = ready and tonumber(ready:read(20))
    if ready then ready:close() end
    if not heartbeat or math.abs(os.time() - heartbeat) > 10 then
        return nil, "Start the camera launcher or run photo_directory.py on your desktop"
    end
    local marker, why = io.open(saved .. "/DenshattackPhotoDirectoryPicker.request", "wb")
    if not marker then return nil, why end
    return marker:close()
end

function unreal.screenshotDir(session)
    local saved = savedDirectory()
    if saved then
        local config, why, errno = io.open(saved .. "/DenshattackPhotoDirectory.txt", "rb")
        if config then
            local key, displayPath, extra = config:read("l", "l", 1)
            config:close()
            local absolute = displayPath and (displayPath:match("^/") or displayPath:match("^%a:[/\\]"))
            if not key or #key ~= 64 or not key:match("^[0-9a-f]+$") or not absolute
                    or displayPath:find("[\r\n%z]") or extra then
                return nil, "Invalid photo folder setting. Choose the folder again"
            end
            local alias = saved .. "/DenshattackPhotoFolders/" .. key
            local ok, exists = pcall(function()
                return object("/Script/Engine.Default__BlueprintPathsLibrary"):DirectoryExists(alias)
            end)
            if not ok or not exists then return nil, "Photo folder unavailable: " .. displayPath end
            return alias, nil, displayPath
        elseif errno ~= 2 then
            return nil, why
        end
    end
    if session.photoDir then return session.photoDir end
    local ok, dir = pcall(function()
        local paths = object("/Script/Engine.Default__BlueprintPathsLibrary")
        local dirName = paths:ScreenShotDir():ToString()
        return paths:ConvertRelativePathToFull(dirName, ""):ToString()
    end)
    if not ok or not dir or dir == "" then
        if not saved then return nil, "Could not locate the screenshot directory" end
        dir = saved .. "/Screenshots/Windows"
    end
    session.photoDir = dir:gsub("\\", "/"):gsub("/+$", "")
    return session.photoDir
end

function unreal.capture(session, request)
    local alive, reason = unreal.alive(session)
    if not alive then return false, reason end
    return pcall(function()
        local filename = request.filename
        assert(type(filename) == "string" and filename:match("^[%w_%-]+%.png$"), "Invalid photo filename")
        local width, height = unreal.viewport(session)
        assert(width, height)
        assert(not request.viewport or (request.viewport.w == width and request.viewport.h == height),
            "Viewport changed during capture. Reframe and press the shutter again")
        local crop = request.crop or {x = 0, y = 0, w = width, h = height}
        assert(math.tointeger(crop.x) and math.tointeger(crop.y) and math.tointeger(crop.w)
            and math.tointeger(crop.h) and crop.x >= 0 and crop.y >= 0 and crop.w >= 1 and crop.h >= 1
            and crop.x + crop.w <= width and crop.y + crop.h <= height, "Invalid photo crop")
        local path = request.path
        assert(type(path) == "string" and path:sub(-#filename - 1) == "/" .. filename, "Invalid photo path")
        path = request.stagedPNG or path
        assert(not path:find('[%c"|]'), "Unreal cannot quote the screenshot path")
        local scale = request.scale or 1
        assert(math.type(scale) == "integer" and scale >= 1 and scale <= 4, "Invalid PNG capture scale")
        request.width, request.height = crop.w * scale, crop.h * scale
        -- An explicit backing raster keeps the engine's resolution multiplier
        -- at one. The capture rectangle is expressed in that raster's pixels.
        local resolution = scale == 1 and "1" or ("%dx%d"):format(width * scale, height * scale)
        local command = string.format('HighResShot filename="%s" %s %d %d %d %d 0 0 0 0',
            path, resolution, crop.x * scale, crop.y * scale, request.width, request.height)
        object("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(session.pc, command, session.pc)
        return request
    end)
end

return unreal
