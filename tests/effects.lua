local effects = dofile("mod/Scripts/effects.lua")
FName = function(name) assert(name == "Visible") return name end

local function object(address)
    return {
        valid = true,
        IsValid = function(self) return self.valid end,
        GetAddress = function() return address end,
    }
end

local function fixture(lineValue, weight)
    local lines, blur, other, owner = object(1), object(2), object(3), object(4)
    lines.value, lines.writes = lineValue, 0
    function lines:K2_GetScalarParameterValue(name)
        assert(name == "Visible")
        return self.value
    end
    function lines:SetScalarParameterValue(name, value)
        assert(name == "Visible")
        self.value = value
        self.writes = self.writes + 1
    end
    local slot = {object = blur, weight = weight, writes = 0}
    local slots = {{object = other, weight = 0.9375, writes = 0}, slot}
    local array = setmetatable({}, {
        __len = function() return #slots end,
        __index = function(_, i)
            return {Object = slots[i].object, Weight = slots[i].weight}
        end,
        __newindex = function(_, i, entry)
            local item = slots[i]
            assert(item.object == entry.Object, "Array slot has been replaced")
            item.weight, item.writes = entry.Weight, item.writes + 1
            if item.fail then
                item.fail = false
                error("write failed after setting blend weight")
            end
        end,
    })
    owner.Settings = {WeightedBlendables = {Array = array}}
    local session = {pawn = {SpeedLinesBlendable = lines, RadialBlurBlendable = blur, RadialBlur = owner}}
    local function defer(s, label, undo)
        assert(s == session and label ~= "" and not session.undo)
        session.undo = undo
    end
    return session, lines, slot, slots, defer
end

local session, lines, blur, slots, defer = fixture(0.625, 0.75)
assert(effects.open(session, defer))
assert(lines.value == 0 and blur.weight == 0)
assert(effects.set(session, false))
assert(lines.value == 0.625 and blur.weight == 0.75)
lines.value = 0.875
assert(effects.set(session, true))
slots[1], slots[2] = slots[2], slots[1]
session.undo()
assert(lines.value == 0.875 and blur.weight == 0.75)
assert(slots[2].writes == 0 and slots[2].weight == 0.9375)
session.undo()
assert(lines.writes == 4 and blur.writes == 4)

session, lines, blur, slots, defer = fixture(0, 0)
assert(effects.open(session, defer))
assert(effects.set(session, false))
session.undo()
assert(lines.writes == 0 and blur.writes == 0)

session, lines, blur, slots, defer = fixture(0.3, 0.5)
assert(effects.open(session, defer))
lines.value, blur.weight = 0.2, 0.375
session.undo()
assert(lines.value == 0.2 and blur.weight == 0.375)

session, lines, blur, slots, defer = fixture(0.7, 0.875)
blur.fail = true
assert(not effects.open(session, defer))
assert(lines.value == 0.7 and blur.weight == 0.875)
assert(effects.set(session, true))
lines.valid = false
table.remove(slots, 2)
session.undo()
assert(lines.writes == 3 and slots[1].writes == 0)

session, lines, blur, slots, defer = fixture(0.5, 0.75)
session.pawn.SpeedLinesBlendable = nil
assert(effects.open(session, defer))
assert(blur.weight == 0)
session.undo()
assert(blur.weight == 0.75)

session, lines, blur, slots, defer = fixture(0.5, 0.75)
table.remove(slots, 2)
assert(effects.open(session, defer))
assert(lines.value == 0 and slots[1].writes == 0)
session.undo()
assert(lines.value == 0.5)

session, lines, blur, slots, defer = fixture(0.5, 0.5)
session.pawn = {}
assert(not effects.open(session, defer))
assert(not effects.set(session, true))
assert(session.undo == nil)
print("Speed-line and radial blend-weight tests passed")
