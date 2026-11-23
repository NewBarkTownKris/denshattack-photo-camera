-- The mocked writer reproduces a real uncompressed EXR channel list and
-- offset table, including zero alpha and a HALF highlight above 1.
local linear = dofile("mod/Scripts/linear.lua")
local width, height = 3, 4
local path = os.tmpname()
os.remove(path)
local req = {path=path .. ".exr", crop={x=2, y=0, w=width, h=height}}
local function attr(n, t, v) return string.pack("<zzI4", n, t, #v) .. v end
local function mockEXR(file, truncate, renderWidth)
    local data = {}
    for _, ch in ipairs({"A","B","G","R"}) do data[#data+1] = string.pack("<zI4I4i4i4",ch,1,0,1,1) end
    local header = "\118\047\049\001" .. string.pack("<I4",2)
       .. attr("channels","chlist",table.concat(data) .. "\0")
       .. attr("dataWindow","box2i",string.pack("<i4i4i4i4",0,0,renderWidth-1,height-1))
       .. attr("compression","compression","\0") .. "\0"
    local f <close> = assert(io.open(file, "wb"))
    assert(f:write(header))
    local left = (renderWidth - width) // 2
    local right = renderWidth - width - left
    local function plane(sample)
        return string.rep("\255\127",left) .. sample:rep(width) .. string.rep("\255\127",right)
    end
    local row = plane("\0\0") .. plane("\0\56") .. plane("\0\60") .. plane("\0\68")
    for y = 0, height-1 do assert(f:write(string.pack("<I8",#header+8*height+y*(#row+8)))) end
    local n = truncate and height-2 or height-1
    for y = 0, n do assert(f:write(string.pack("<i4I4",y,#row),row)) end
end

local actor, component, target, library, world, pc, writer = {}, {}, {}, {}, {}, {}, {}
local settings = {WorkingColorSpaceChoice=19}
local function valid() return true end
local enum = {GetNameByValue=function(_, value)
    assert(value == 19)
    return {ToString=function() return settings.choice or "EWorkingColorSpace::sRGB" end}
end}
local objects = {["/Script/Engine.Default__RendererSettings"]=settings, ["/Script/Engine.EWorkingColorSpace"]=enum,
    ["/Script/Engine.Default__KismetRenderingLibrary"]=library, ["/Script/ImageWriteQueue.Default__ImageWriteBlueprintLibrary"]=writer,
    ["/Script/Engine.SceneCapture2D"]={}, ["/Script/Engine.SceneCaptureComponent2D"]={}}
objects["/Script/ImageWriteQueue.ImageWriteOptions"] = {ForEachProperty=function(_, cb)
    for _, key in ipairs({"format","CompressionQuality","bOverwriteFile","bAsync","OnComplete"}) do
        cb({GetFName=function() return {ToString=function() return key end} end})
    end
end}
for _, o in pairs(objects) do o.IsValid = valid end
actor.IsValid, target.IsValid, component.IsValid = valid, valid, valid
function StaticFindObject(k) return assert(objects[k]) end
function pc:DeprojectScreenPositionToWorld(x,y,origin,ray)
    assert(y == req.crop.y + height/2 and (x == req.crop.x or x == req.crop.x+width))
    ray.X, ray.Y, ray.Z = math.sqrt(0.5), x == req.crop.x and -math.sqrt(0.5) or math.sqrt(0.5), 0
    return true
end
function world:SpawnActor(_, pos, rot) assert(pos.X==5 and rot.Pitch==24); return actor end
function actor:GetComponentByClass() return component end
function actor:K2_SetActorLocationAndRotation(pos, rot) assert(pos.X==5 and rot.pitch==24); return true end
function actor:K2_DestroyActor() self.destroyed=true end
function library:CreateRenderTarget2D(wld,w,h,fmt,_,mip,uav)
    assert(wld==world and w%32==0 and w>=width and w-width<32 and h==height and fmt==6 and not mip and not uav)
    target.width = w
    return target
end
function library:ReadRenderTargetRawPixel(wld, rt, x, y, normalize)
    assert(wld==world and rt==target and x==0 and y==0 and not normalize)
end
function library:ReleaseRenderTarget2D(rt) assert(rt==target); target.released=true end
function library:CalculateProjectionMatrix(info)
    local padded = info.AspectRatio * height
    local left = (padded-width) // 2
    local half = math.tan(math.rad(info.FOV)/2)
    -- For a 90-degree initial horizontal FOV, the desired ray slopes are
    -- -1..1. Integer crop boundaries and pixel centers must both agree.
    for _, x in ipairs({0, 0.5, width/2, width-0.5, width}) do
        local ndc = (2*(left+x)/padded)-1
        local slope = (ndc + info.OffCenterProjectionOffset.X)*half
        assert(math.abs(slope - (2*x/width-1)) < 1e-7)
    end
    assert(info.OffCenterProjectionOffset.Y==0 and math.abs(half/info.AspectRatio-height/width)<1e-7)
    return {calculated=true}
end
function component:CaptureScene()
    assert(self.TextureTarget==target and target.TargetGamma==1)
    assert(self.CaptureSource==1 and self.bUseCustomProjectionMatrix and self.CustomProjectionMatrix.calculated)
    assert(self.bCaptureEveryFrame==false and self.bAlwaysPersistRenderingState==false)
end
function writer:ExportToDisk(rt, file, options)
    assert(rt==target and options.format==3 and options.CompressionQuality==1 and not options.bAsync)
    mockEXR(file, self.truncate, rt.width)
end

local s = {world=world,pc=pc,pose={x=5,y=6,z=7,yaw=2,pitch=24,roll=3},
    locationKeys={x="X",y="Y",z="Z"}, angleKeys={pitch="pitch",yaw="Yaw",roll="Roll"}}
local function capture()
    local ok, err = linear.capture(s,req)
    if not ok then return false, err end
    assert(not actor.destroyed and not target.released)
    for _=1,5 do
        local done, why = linear.checkFile(req)
        if done or why then return done, why end
    end
    error("capture did not complete")
end
assert(capture())
assert(actor.destroyed and target.released and linear.checkFile(req))
do
    local f <close> = assert(io.open(req.path,"rb"))
    local bytes = f:read("a")
    assert(bytes:find("chromaticities\0chromaticities\0",1,true))
    assert(bytes:sub(-width*6) == string.rep("\0\56",width)..string.rep("\0\60",width)..string.rep("\0\68",width))
end
assert(not linear.capture(s,req))
assert(not linear.checkFile({path=req.path,crop={w=width,h=height+1}}))
os.remove(req.path)
writer.truncate, actor.destroyed, target.released = true, false, false
local written, err = capture()
assert(not written and err:find("Incomplete EXR") and actor.destroyed and target.released)
for _, p in ipairs({req.path, req.path:sub(1,-5)..".source.exr", req.path..".partial"}) do assert(not io.open(p,"rb")) end
settings.choice, actor.destroyed = "EWorkingColorSpace::Custom", false
assert(not linear.capture(s,req))
assert(not actor.destroyed)
print("Linear shutter projection, lossless HALF RGB, working gamut, staging and cleanup passed")

settings.choice, writer.truncate = nil, false
assert(linear.capture(s,req))
assert(linear.cancel(req) and linear.cancel(req))
assert(not req.linearJob and not io.open(req.path,"rb"))

-- At 4K the 65:24 framing preset produces 3835 columns. Verify its native
-- resolution and odd guard imbalance without writing a 40 MB test fixture.
for _, w in ipairs({3835, 3840}) do
    width, height = w, 1416
    req.crop = {x=(3840-w)//2,y=372,w=width,h=height}
    assert(linear.capture(s,req))
    assert(target.width==3840 and req.linearJob.left==(3840-w)//2)
    assert(linear.cancel(req))
end

-- A silent native writer was the failure reported on the 65:24 gate.
-- Advance the real-time poll clock and require the alternate readback to
-- publish a usable RGB master from the still-live target.
width, height = 5, 4
req.crop = {x=0,y=0,w=width,h=height}
function writer:ExportToDisk() end
function library:ReadRenderTargetRawPixelArea(_, _, left, top, numCols, numRows, normalize)
    assert(left == (target.width - width) // 2 and top == 0)
    assert(numCols == width and numRows == height and not normalize)
    local colors = {}
    for i = 1, numCols * numRows do colors[i] = {R=4,G=1,B=0.5} end
    return colors
end
assert(linear.capture(s,req))
assert(not linear.checkFile(req, 1))
assert(not linear.checkFile(req, 2))
assert(linear.checkFile(req, 3.1))
assert(not req.linearJob and linear.checkFile(req))
os.remove(req.path)

-- The photographic master applies gain once in both writer paths. FLOAT
-- retains detail even when a bright source multiplied by gain exceeds HALF.
req.exposure = {mode="Manual", aperture=2.8, seconds=1/125, iso=400,
                compensation=0.5, meteredEV=8, evError=-0.25, gain=32768}
local function verifyExposed()
    local f <close> = assert(io.open(req.path, "rb"))
    local bytes = f:read("a")
    assert(bytes:find(attr("aperture","float",string.pack("<f",2.8)),1,true))
    assert(bytes:find(attr("expTime","float",string.pack("<f",1/125)),1,true))
    assert(bytes:find(attr("isoSpeed","float",string.pack("<f",400)),1,true))
    assert(bytes:find(attr("denshExposureMode","string","Manual"),1,true))
    assert(bytes:find(attr("denshExposureGain","float",string.pack("<f",32768)),1,true))
    local tail = string.rep(string.pack("<f",16384),width) .. string.rep(string.pack("<f",32768),width)
        .. string.rep(string.pack("<f",131072),width)
    assert(bytes:sub(-width*12)==tail)
end
assert(linear.capture(s,req))
assert(not linear.checkFile(req,1)); assert(linear.checkFile(req,3.1)); verifyExposed()
os.remove(req.path)
function writer:ExportToDisk(rt,file) mockEXR(file,false,rt.width) end
actor.destroyed,target.released=false,false
assert(capture()); verifyExposed(); os.remove(req.path)
print("Photographic FLOAT EXR gain and metadata match across both render readback paths.")
