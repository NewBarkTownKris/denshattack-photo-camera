-- Drive the real shutter recorder/renderer through its frame lifecycle.
-- The mock scene maps camera X to a pixel. Averaging first/last viewport
-- stills or rendering the same pose twice would both fail the sample checks.
local photo=dofile("mod/Scripts/photo.lua")
local lib,writer,world={}, {}, {}
local allocations,actors,targets,poses = 0, {}, {}, {}
local gpuError, writerSilent, lastPNG, lastRAW
local function valid() return true end
lib.IsValid,writer.IsValid=valid,valid
local class={IsValid=valid}
local objects={["/Script/Engine.Default__KismetRenderingLibrary"]=lib,
    ["/Script/ImageWriteQueue.Default__ImageWriteBlueprintLibrary"]=writer,
    ["/Script/Engine.SceneCapture2D"]=class,["/Script/Engine.SceneCaptureComponent2D"]=class}
local function pose(x,yaw) return {x=x,y=0,z=12,yaw=yaw or 0,pitch=0,roll=0,fov=55} end
local s={world=world,pc={},pose=pose(0,179),lens={PostProcessSettings={look=true},PostProcessBlendWeight=1},
    locationKeys={x="X",y="Y",z="Z"},angleKeys={pitch="pitch",yaw="Yaw",roll="Roll"}}
function world:SpawnActor(c)
    assert(c==class)
    local actor={IsValid=valid}
    local comp={IsValid=valid}
    actors[#actors+1]=actor
    function actor:GetComponentByClass() return comp end
    function actor:K2_SetActorLocationAndRotation(p,r)
        self.x,self.yaw=p.X,r.Yaw
        return true
    end
    function comp:CaptureScene()
        assert(not self.bCaptureEveryFrame and self.bUseCustomProjectionMatrix)
        assert(self.CaptureSource==1 or self.CaptureSource==2)
        if self.CaptureSource==2 then assert(self.PostProcessSettings==s.lens.PostProcessSettings) end
        self.TextureTarget.value=(self.CaptureSource==1 and 100 or 0)+actor.x
        poses[#poses+1]={self.CaptureSource,actor.x,actor.yaw}
    end
    function actor:K2_DestroyActor() self.destroyed=true end
    return actor
end
function lib:CreateRenderTarget2D(_,w,h,fmt)
    allocations=allocations+1
    if gpuError and allocations==gpuError then error("out of video memory") end
    local rt={IsValid=valid,w=w,h=h,format=fmt}
    targets[#targets+1]=rt
    return rt
end
function lib:ClearRenderTarget2D(_,rt) rt.value=0 end
function lib:ReleaseRenderTarget2D(rt) assert(not rt.released); rt.released=true end
function lib:ReadRenderTargetRawPixel() return {} end
function lib:BeginDrawCanvasToRenderTarget(_,dst,out,size,ctx)
    assert(not lib.drawing); lib.drawing=dst; ctx.RenderTarget=dst
    out.Canvas={IsValid=valid,K2_DrawTexture=function(_,src,_,_,offset,uv,weight,blend)
        if blend==5 then assert(weight.A==0 and uv.X==1); dst.value=dst.value+src.value
        else assert(blend==0 and offset.X>=0); dst.value=weight.R*src.value end
    end}
end
function lib:EndDrawCanvasToRenderTarget(_,ctx) assert(lib.drawing==ctx.RenderTarget); lib.drawing=nil end
function writer:ExportToDisk(rt,path)
    lastPNG=rt.value
    if writerSilent then return end
    local f <close> = assert(io.open(path,"wb"))
    f:write("\137PNG\r\n\26\n",string.pack(">I4",13),"IHDR",string.pack(">I4I4",rt.w,rt.h),"\0\0\0\0IEND\174\66\96\130")
end
local lin={writeOptions=function(v) assert(v==0); return {} end,projection=function(s,c,_,p,l,w,h)
    assert(c.w>=w and c.h>=h and p%32==0 and l==(p-w)//2); return {},55
end,fromTarget=function(_,req,rt,_,_,count,divisor)
    assert(rt.format==9 and count==divisor and count>=2); req.linearJob={}
    lastRAW=rt.value/divisor*req.exposure.gain; return true
end,checkFile=function(req) req.linearJob=nil; return true end,cancel=function(req) req.linearJob=nil; return true end}
local env=setmetatable({StaticFindObject=function(k) return objects[k] end,
    dofile=function(path) return path:match("linear.lua$") and lin or dofile(path) end}, {__index=_G})
local motion=assert(loadfile("mod/Scripts/motion.lua","t",env))()
local tmp=os.tmpname(); os.remove(tmp)
local function request(raw)
    local r={path=tmp..".png",crop={x=0,y=3,w=3835,h=1416},exposure={mode="Manual",seconds=1/15,gain=2}}
    if raw then r.linear={path=tmp..".exr",crop=r.crop} end
    return r
end
local req=request(true)
assert(motion.start(s,req,100))
s.pose=pose(4,-180)
assert(not motion.step(s,req,100+1/60))
s.pose=pose(16,-177)
assert(not motion.step(s,req,100+1/15))
assert(not req.motionJob.open)
for i=1,10 do
    local done,why=motion.step(s,req,100.1+i*.01)
    assert(not why,why)
    if done then break end
end
assert(not req.motionJob and photo.checkFile(req))
assert(#poses==4 and poses[1][1]==2 and poses[2][1]==1 and poses[3][1]==2 and poses[4][1]==1)
for i=1,4 do
    assert(math.abs(poses[i][2]-(i<=2 and 4 or 12))<1e-7)
    local yaw=poses[i][3]; assert(math.abs(yaw)>175, "cross yaw wrap along the short arc")
end
assert(math.abs(lastPNG-8)<1e-7 and math.abs(lastRAW-216)<1e-7)
os.remove(req.path)
for _,a in ipairs(actors) do assert(a.destroyed) end
for _,t in ipairs(targets) do assert(t.released) end

local cancelled=request(false)
assert(motion.start(s,cancelled,0)); assert(motion.cancel(cancelled) and not cancelled.motionJob)
local failed=request(false)
assert(motion.start(s,failed,0))
motion.step(s,failed,1)
gpuError=allocations+2
local _,why=motion.step(s,failed,1.01)
assert(why:find("out of video memory",1,true) and not failed.motionJob)
for _,a in ipairs(actors) do assert(a.destroyed) end
for _,t in ipairs(targets) do assert(t.released) end
assert(not io.open(failed.path,"rb"))

-- A long shutter bounds both replay count and output size.
local long=request(false); long.exposure.seconds=8; long.crop={x=0,y=0,w=7680,h=4320}
assert(motion.start(s,long,0)); motion.step(s,long,10); assert(#long.motionJob.poses==64)
motion.step(s,long,10.01); assert(long.crop.w==3840 and long.crop.h==2160)
assert(motion.cancel(long))
print("Real-time shutter midpoint sampling, mixed PNG/EXR rendering, highlight gain, yaw wrap, bounds and cleanup passed.")

-- A silent native image writer falls back to crop-correct opaque sRGB and
-- still advances to the matched RAW companion.
local repair=request(true)
repair.crop={x=2,y=0,w=7,h=6}
writerSilent=true
function lib:ReadRenderTargetRawPixelArea(_,rt,x,y,w,h,normalize)
    assert(x==12 and y==0 and w==7 and h==6 and not normalize)
    local out={}
    for i=1,w*h do out[i]={R=.36,G=2,B=0,A=0} end
    return out
end
assert(motion.start(s,repair,0)); motion.step(s,repair,1)
for i=1,16 do
    local done,why=motion.step(s,repair,i+1)
    assert(not why,why)
    if done then break end
end
assert(not repair.motionJob and photo.checkFile(repair))
local f=assert(io.open(repair.path,"rb")); local data=f:read("a"); f:close()
assert(data:byte(26)==2 and data:find("sRGB",1,true))
os.remove(repair.path)
