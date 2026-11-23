-- Recover scanlines directly from the frozen RGBA16f target when Unreal's
-- image writer returns without producing a source file.
local fallback = {}
local maxSamples = 65536
local packed = {}

-- Raw, unnormalized readback promotes an IEEE half to a Lua number without
-- changing its value. Cache the two-byte representation for repeated colors.
local function half(value)
    if value == 0 then return 1 / value < 0 and "\0\128" or "\0\0" end
    local bytes = packed[value]
    if bytes then return bytes end
    local magnitude = math.abs(value)
    assert(magnitude <= 65504, "Invalid scene color in EXR readback")
    local bits
    if magnitude < 2^-14 then
        bits = math.tointeger(magnitude * 2^24)
    else
        local single = string.unpack("<I4", string.pack("<f", magnitude))
        -- Half normals have ten mantissa bits and use an exponent bias of 15.
        assert(single & 0x1fff == 0, "Readback contains a non-HALF color")
        bits = (single >> 13) - 0x1c000
    end
    assert(bits, "Unexpected fractional half subnormal")
    if value < 0 then bits = bits | 0x8000 end
    bytes = string.pack("<I2", bits)
    packed[value] = bytes
    return bytes
end

-- Writes to tx.partial. The caller publishes the completed file and handles
-- cancellation with the same lifecycle used by the native writer.
function fallback.step(tx, request, rgbHeader)
    local w, h = request.crop.w, request.crop.h
    local left = tx.left or 0
    if tx.fallbackRow == nil then
        local hdr = rgbHeader(w, h, tx.chroma)
        local out <close> = assert(io.open(tx.partial, "wb"))
        assert(out:write(hdr))
        local first = #hdr + h * 8
        for y = 0, h - 1 do assert(out:write(string.pack("<I8", first + y * (8 + 6 * w)))) end
        assert(out:flush())
        tx.fallbackRow = 0
    end
    if tx.fallbackRow == h then return true end
    local first = tx.fallbackRow
    local rows = math.min(h - first, math.max(1, maxSamples // w))
    -- This shipping build interprets the last two rectangle arguments as
    -- extents, even though their reflected names are MaxX and MaxY.
    local colors = tx.library:ReadRenderTargetRawPixelArea(tx.world, tx.target, left, first, w, rows, false)
    assert(#colors == w * rows, "Incomplete rectangle in EXR scene color readback")
    local firstPixel = colors[1]
    local unwrap = firstPixel.R == nil and type(firstPixel.get) == "function"
    local sample = unwrap and firstPixel:get() or firstPixel
    assert(type(sample.R) == "number", "Could not read the reflected LinearColor")
    local out <close> = assert(io.open(tx.partial, "ab"))
    local blue, green, red = {}, {}, {}
    local index = 1
    for y = first, first + rows - 1 do
        for x = 1, w do
            local pixel = colors[index]
            if unwrap then pixel = pixel:get() end
            blue[x], green[x], red[x] = half(pixel.B), half(pixel.G), half(pixel.R)
            index = index + 1
        end
        assert(out:write(string.pack("<i4I4", y, 6 * w),
            table.concat(blue), table.concat(green), table.concat(red)))
    end
    assert(out:flush())
    tx.fallbackRow = first + rows
    return tx.fallbackRow == h
end

return fallback
