local effects = {}

local function valid(o)
    return o and o:IsValid()
end

-- CheckAllBlendables pairs RadialBlurBlendable with the RadialBlur component.
-- Resolve the slot each time. Direction changes and streaming can reorder or
-- replace an array, so an array index or UScriptStruct wrapper cannot be saved.
local function radialSlot(target)
    if not valid(target.owner) or not valid(target.material) then return end
    local array = target.owner.Settings.WeightedBlendables.Array
    for index = 1, #array do
        local entry = array[index]
        local object = entry.Object
        if valid(object) and object:GetAddress() == target.material:GetAddress() then
            return entry, array, index
        end
    end
end

local function read(target)
    if not valid(target.material) then return nil end
    local value
    if target.owner then
        local entry = radialSlot(target)
        if not entry then return nil end
        value = entry.Weight
    else
        -- BP_TrainCharacter.SetSpeedlinesVisibility writes exactly this scalar.
        value = target.material:K2_GetScalarParameterValue(target.parameter)
    end
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge,
        "Could not read " .. target.label)
    return value
end

local function write(target, value)
    if target.owner then
        local entry, array, index = radialSlot(target)
        assert(entry, "The train's radial blendable was detached")
        entry.Weight = value
        -- Some UE4SS bindings copy a reflected struct into a plain Lua table.
        -- Write the edited copy back only on those bindings.
        if type(entry) == "table" then array[index] = entry end
    else
        target.material:SetScalarParameterValue(target.parameter, value)
    end
    assert(read(target) == value, "Could not set " .. target.label)
end

local function restore(target)
    if target.saved == nil then return end
    -- A destroyed/replaced material or a newer nonzero value means this
    -- session's override no longer needs to be removed.
    if target.saved ~= 0 and read(target) == 0 then write(target, target.saved) end
    target.saved = nil
end

local function restoreAll(targets)
    local errors = {}
    for _, target in ipairs(targets) do
        local ok, err = pcall(restore, target)
        if not ok then errors[#errors + 1] = tostring(err) end
    end
    assert(#errors == 0, table.concat(errors, ", "))
end

function effects.set(session, suppress)
    local targets = session.speedEffectTargets
    if not targets or #targets == 0 then return false, "No active train speed effects on this pawn" end
    if not suppress then
        local ok, err = pcall(restoreAll, targets)
        return ok, ok and "Game speed effects restored" or tostring(err)
    end
    local originals = {}
    local ok, err = pcall(function()
        for _, target in ipairs(targets) do
            if target.saved == nil then target.saved = read(target) end
            assert(target.saved ~= nil, "The train's " .. target.label .. " is no longer available")
            originals[#originals + 1] = ("%s %g"):format(target.label, target.saved)
            if target.saved ~= 0 then write(target, 0) end
        end
    end)
    if not ok then
        -- Roll back a later write failure after an earlier effect was changed.
        local restored, rollbackError = pcall(restoreAll, targets)
        return false, tostring(err) .. (restored and "" or (", restore pending: " .. tostring(rollbackError)))
    end
    return true, "Game speed effects off (original " .. table.concat(originals, ", ") .. ")"
end

function effects.open(session, defer)
    local targets, unavailable = {}, {}
    local function include(label, resolve)
        local ok, target = pcall(resolve)
        if ok and target then
            targets[#targets + 1] = target
        else
            unavailable[#unavailable + 1] = label .. (ok and "" or ": " .. tostring(target))
        end
    end
    include("speed lines", function()
        local material = session.pawn.SpeedLinesBlendable
        if valid(material) then
            return {material = material, parameter = FName("Visible"), label = "line visibility"}
        end
    end)
    include("radial blur", function()
        local target = {owner = session.pawn.RadialBlur, material = session.pawn.RadialBlurBlendable,
            label = "radial blend weight"}
        if radialSlot(target) then return target end
    end)
    if #targets == 0 then return false, "No active train speed effects on this pawn (" .. table.concat(unavailable, ", ") .. ")" end
    session.speedEffectTargets = targets
    defer(session, "restore train speed effects", function() restoreAll(targets) end)
    local ok, detail = effects.set(session, true)
    if #unavailable > 0 then detail = detail .. " (unavailable: " .. table.concat(unavailable, ", ") .. ")" end
    return ok, detail
end

return effects
