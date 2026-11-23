local shift = dofile("mod/Scripts/pixelshift.lua")
local stem = os.tmpname()
assert(os.remove(stem))
local function exists(path)
    local f=io.open(path,"rb")
    if f then f:close(); return true end
    return false
end

local fixture = {tick=0,started={},cancelled=0}
local function attr(key,kind,value)
    return string.pack("<zzI4",key,kind,#value)..value
end
local function sample(x,y,ch,bytes)
    if bytes==4 then return string.pack("<f",x-y*23+ch*70000) end
    -- Test bit preservation including negative zero and HALF subnormals.
    return string.pack("<I2",(x+y*23+ch*313)%32768 + (ch==0 and 32768 or 0))
end
local function fileForPhase(p)
    local n,px,py=p.phase.grid,p.phase.x,p.phase.y
    local w,h=p.output.w,p.output.h
    local bytes=p.exposure and 4 or 2
    local channels={}
    for _,c in ipairs({"B","G","R"}) do
        channels[#channels+1]=string.pack("<zI4I4i4i4",c,bytes==2 and 1 or 2,0,1,1)
    end
    local box=string.pack("<i4i4i4i4",0,0,w-1,h-1)
    local head="\118\047\049\001"..string.pack("<I4",2)
        ..attr("dataWindow","box2i",box)..attr("displayWindow","box2i",box)
        ..attr("channels","chlist",table.concat(channels).."\0")
        ..attr("lineOrder","lineOrder","\0")..attr("compression","compression","\0")
        ..attr("chromaticities","chromaticities",string.pack("<ffffffff",.64,.33,.30,.60,.15,.06,.3127,.329))
        ..(p.exposure and attr("isoSpeed","float",string.pack("<f", p.exposure.iso)) or "").."\0"
    local f <close> = assert(io.open(p.path,"wb"))
    assert(f:write(head))
    -- Store physical scanlines in reverse order. The merge must follow the
    -- offset table, and crop only the final phase samples on odd edges.
    local stride=8+w*3*bytes
    for y=0,h-1 do assert(f:write(string.pack("<I8",#head+h*8+(h-1-y)*stride))) end
    for y=h-1,0,-1 do
        assert(f:write(string.pack("<i4I4",y,w*3*bytes)))
        for ch=0,2 do for x=0,w-1 do
            assert(f:write(sample(n*x+px,n*y+py,ch,bytes)))
        end end
    end
end
local function capture(s,p)
    assert(s==fixture and fixture.tick==0,"phase renders must submit in the same game tick")
    fixture.started[#fixture.started+1]=p
    assert(not exists(p.path) and p.exposure==fixture.req.exposure and p.crop==fixture.req.crop)
    p.linearJob={fallbackRow=0}
    if fixture.failAt==#fixture.started then return false,"allocation failed" end
    return true
end
local function check(p)
    assert(p.linearJob)
    if p.linearJob.fallbackRow==0 then p.linearJob.fallbackRow=1; return false,nil,true end
    fileForPhase(p)
    p.linearJob=nil
    return true
end
local function cancel(p)
    p.linearJob=nil
    fixture.cancelled=fixture.cancelled+1
    return true
end
local callbacks={capture=capture,checkFile=check,cancel=cancel}
local function request(w,h,iso)
    local req={path=stem..".exr",crop={x=0,y=3,w=7,h=9},output={w=w,h=h},
        exposure=iso and {iso=iso,mode="Manual",gain=2}}
    fixture.req,fixture.tick,fixture.started,fixture.cancelled=req,0,{},0
    return req
end

local n,pw,ph=shift.grid(15308,6020)
assert(n==2 and pw==7654 and ph==3010)
n,pw,ph=shift.grid(15360,8640)
assert(n==2 and pw==7680 and ph==4320)
n,pw,ph=shift.grid(16384,16384)
assert(n==3 and pw==5462 and ph==5462 and ((pw+31)//32)*32*ph<=7680*4320)

for _,arg in ipairs({{19,13},{16,8,800},{1025,65,3200}}) do
    local w,h,iso=table.unpack(arg)
    local req=request(w,h,iso)
    assert(shift.capture(fixture,req,callbacks) and #fixture.started==4)
    local previous=0
    repeat
        fixture.tick=fixture.tick+1
        local done,err,advanced=shift.checkFile(req,fixture.tick)
        assert(not err and advanced,err)
        if done then break end
        assert(previous<=req.pixelShiftJob.progress and req.pixelShiftJob.progress<=1)
        previous=req.pixelShiftJob.progress
    until fixture.tick>15
    assert(not req.pixelShiftJob)
    local f=assert(io.open(req.path,"rb"))
    local data=f:read("a"); f:close()
    local pos,attrs=9,{}
    while data:byte(pos)~=0 do
        local key,kind,len,start=string.unpack("<zzI4",data,pos)
        attrs[key]=data:sub(start,start+len-1)
        pos=start+len
    end
    local box=string.pack("<i4i4i4i4",0,0,w-1,h-1)
    assert(attrs.dataWindow==box and attrs.displayWindow==box)
    assert(attrs.chromaticities and attrs.denshPixelShiftGrid==string.pack("<i4",2))
    assert(attrs.isoSpeed==(iso and string.pack("<f",iso) or nil))
    local bytes=iso and 4 or 2
    for y=0,h-1 do
        local row=string.unpack("<I8",data,pos+1+y*8)+1
        local line,length,pixel=string.unpack("<i4I4",data,row)
        assert(line==y and length==w*3*bytes)
        for ch=0,2 do for x=0,w-1 do
            assert(data:sub(pixel,pixel+bytes-1)==sample(x,y,ch,bytes))
            pixel=pixel+bytes
        end end
    end
    assert(os.remove(req.path))
    for _,phase in ipairs(fixture.started) do assert(not exists(phase.path)) end
end

-- Release every already-rendered target and completed phase on cancel.
local req=request(9,5)
assert(shift.capture(fixture,req,callbacks))
assert(not shift.checkFile(req,1)); assert(not shift.checkFile(req,2))
assert(exists(fixture.started[1].path) and shift.cancel(req) and fixture.cancelled==3)
assert(not req.pixelShiftJob and not exists(req.path) and not exists(fixture.started[1].path))

-- Preserve existing files, even when allocation fails partway or a stale
-- phase file is discovered before the first game-side capture.
req=request(9,5)
fixture.failAt=3
local ok,why=shift.capture(fixture,req,callbacks)
assert(not ok and why:find("allocation failed") and fixture.cancelled==3 and not req.pixelShiftJob)
fixture.failAt=nil
local collision=fixture.started[2].path
local f=assert(io.open(collision,"wb")); assert(f:write("other capture")); f:close()
req=request(9,5)
assert(not shift.capture(fixture,req,callbacks) and not req.pixelShiftJob and #fixture.started==0)
f=assert(io.open(collision,"rb")); assert(f:read("a")=="other capture"); f:close(); assert(os.remove(collision))
req=request(9,5)
assert(shift.capture(fixture,req,callbacks))
for i=1,9 do assert(not shift.checkFile(req,i)) end
local partial=req.pixelShiftJob.partial
assert(req.pixelShiftJob.row==0 and exists(partial))
assert(shift.cancel(req) and not exists(partial) and not exists(req.path))
for _,phase in ipairs(fixture.started) do assert(not exists(phase.path)) end
print("Pixel-shift whole-frame scheduling, HALF/FLOAT interleave, odd edges, staging and cancellation passed.")
