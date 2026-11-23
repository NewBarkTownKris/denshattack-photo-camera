-- Record the moving camera against wall time while its world stays paused.
-- Render the locked view at evenly spaced shutter midpoints after it closes.
local motion = {}
local folder = assert(debug.getinfo(1,"S").source:match("^@(.+[/\\])"))
local linear = dofile(folder .. "linear.lua")
local photo = dofile(folder .. "photo.lua")
local png = dofile(folder .. "motionpng.lua")

local function object(path)
    local value = StaticFindObject(path)
    assert(value and value:IsValid(), "Unavailable motion capture object " .. path)
    return value
end

local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function interpolate(a, b, k)
    local function position(key) return a[key] + k * (b[key] - a[key]) end
    local function rotation(key) return a[key] + k * ((b[key] - a[key] + 180) % 360 - 180) end
    return {x=position("x"), y=position("y"), z=position("z"), yaw=rotation("yaw"),
        pitch=position("pitch"), roll=rotation("roll"), fov=a.fov}
end

function motion.start(session, request, now)
    local e = request.exposure
    if not e or e.mode == "Game" or not (e.seconds >= 1/15 - 1e-7 and e.seconds <= 8) then
        return false, "Choose a photographic shutter between 1/15 s and 8 s"
    end
    if not request.path:match("%.png$") then return false, "Expected a PNG path" end
    local stage = request.path:sub(1,-5) .. ".motion.png"
    local recovery = stage .. ".partial"
    if request.motionJob or exists(request.path) or exists(stage) or exists(recovery)
            or (request.linear and exists(request.linear.path)) then return false, "Shutter filename is in use" end
    request.motionJob = {open=true, start=now, last=0, lastPose=session.pose,
        count=math.min(64, math.max(2, math.ceil(e.seconds * 30))), duration=e.seconds,
        poses={}, actors={}, targets={}, stage=stage, recovery=recovery, world=session.world, inputCrop=request.crop}
    return true
end

local function record(job, pose, now)
    local elapsed = math.max(job.last, now - job.start)
    while #job.poses < job.count do
        local t = (#job.poses + 0.5) * job.duration / job.count
        if t > elapsed then break end
        local fraction = (t - job.last) / (elapsed - job.last)
        job.poses[#job.poses+1] = interpolate(job.lastPose, pose, fraction)
    end
    job.last, job.lastPose = elapsed, pose
    if elapsed + 1e-9 >= job.duration and #job.poses == job.count then job.open = false end
end

local function place(s, actor, p)
    local k, r = s.locationKeys, s.angleKeys
    assert(actor:K2_SetActorLocationAndRotation({[k.x]=p.x,[k.y]=p.y,[k.z]=p.z},
        {[r.pitch]=p.pitch,[r.yaw]=p.yaw,[r.roll]=p.roll}, false, {}, true), "Could not move shutter camera")
end

-- Holding a target in a live capture component keeps it reachable by Unreal's
-- garbage collector, including while a large GPU readback spans many frames.
local function surface(s, job, w, h, format, gamma, source)
    local p = s.pose
    local actor = s.world:SpawnActor(job.captureClass, {X=p.x,Y=p.y,Z=p.z},
        {Pitch=p.pitch,Yaw=p.yaw,Roll=p.roll})
    assert(actor and actor:IsValid(), "Could not create shutter camera")
    job.actors[#job.actors+1] = actor
    local comp = actor:GetComponentByClass(job.componentClass)
    assert(comp and comp:IsValid(), "Missing shutter camera component")
    comp.bCaptureEveryFrame, comp.bCaptureOnMovement, comp.bAlwaysPersistRenderingState = false,false,false
    local clear = {R=0,G=0,B=0,A=1}
    local rt = job.lib:CreateRenderTarget2D(s.world,w,h,format,clear,false,false)
    assert(rt and rt:IsValid(), "Could not allocate the shutter render target")
    job.targets[#job.targets+1] = rt
    rt.TargetGamma = gamma
    comp.TextureTarget = rt
    if source then
        comp.CaptureSource, comp.FOVAngle = source, job.fov
        comp.CustomProjectionMatrix, comp.bUseCustomProjectionMatrix = job.matrix, true
        if source == 2 then
            comp.PostProcessSettings = s.lens.PostProcessSettings
            comp.PostProcessBlendWeight = s.lens.PostProcessBlendWeight
        end
    end
    job.lib:ClearRenderTarget2D(s.world,rt,clear)
    return {actor=actor, comp=comp, rt=rt, w=w, h=h}
end

local function draw(s, job, dst, src, gain, blend, alpha, crop)
    local out, size, ctx = {}, {}, {}
    job.lib:BeginDrawCanvasToRenderTarget(s.world, dst.rt, out, size, ctx)
    local drawn, why = pcall(function()
        local canvas = out.Canvas or out.canvas or select(2,next(out))
        assert(canvas and canvas:IsValid(), "Could not open shutter accumulation canvas")
        local offset = crop and job.left / src.w or 0
        local width = crop and dst.w / src.w or 1
        canvas:K2_DrawTexture(src.rt,{X=0,Y=0},{X=dst.w,Y=dst.h},{X=offset,Y=0},{X=width,Y=1},
            {R=gain,G=gain,B=gain,A=alpha},blend,0,{X=0,Y=0})
    end)
    job.lib:EndDrawCanvasToRenderTarget(s.world,ctx)
    assert(drawn, why)
end

local function beginRender(s, request, job)
    local crop = job.inputCrop
    local scale = math.min(1, 3840 / math.max(crop.w,crop.h))
    local w, h = math.max(1,math.floor(crop.w*scale + 0.5)), math.max(1,math.floor(crop.h*scale + 0.5))
    local padded = ((w+31)//32)*32
    job.left = (padded-w)//2
    job.lib = object("/Script/Engine.Default__KismetRenderingLibrary")
    job.writer = object("/Script/ImageWriteQueue.Default__ImageWriteBlueprintLibrary")
    job.captureClass = object("/Script/Engine.SceneCapture2D")
    job.componentClass = object("/Script/Engine.SceneCaptureComponent2D")
    job.matrix,job.fov = linear.projection(s,crop,job.lib,padded,job.left,w,h)
    job.display = surface(s,job,padded,h,3,2.2,2) -- FinalColorLDR in an sRGB texture
    job.displaySum = surface(s,job,padded,h,6,1) -- accumulate decoded display RGB in linear light
    if request.linear then
        job.raw = surface(s,job,padded,h,6,1,1) -- SceneColorHDRNoAlpha, ahead of grading
        job.rawSum = surface(s,job,padded,h,9,1) -- FLOAT to retain very bright sums
    end
    request.crop = {x=0,y=0,w=w,h=h}
    if request.linear then request.linear.crop = request.crop end
    job.index=1
end

local function accumulate(s, job, layer, sum, pose)
    place(s,layer.actor,pose)
    layer.comp:CaptureScene()
    -- AlphaComposite takes premultiplied RGB and keeps the destination with
    -- a zero source alpha. HDRNoAlpha has meaningful RGB even at zero alpha.
    draw(s,job,sum,layer,1,5,0,false)
end

local function submitPNG(s,request,job,now)
    local crop = request.crop
    local output = surface(s,job,crop.w,crop.h,3,2.2)
    draw(s,job,output,job.displaySum,1/job.count,0,1,true)
    local opts = linear.writeOptions(0) -- PNG
    local ok = pcall(function() job.writer:ExportToDisk(output.rt,job.stage,opts) end)
    if not ok then job.recoverPNG=true end
    job.lib:ReadRenderTargetRawPixel(s.world,output.rt,0,0,false)
    job.pngTime=now
end

function motion.cancel(request)
    local job = request and request.motionJob
    if not job then return true end
    local errors = {}
    local function release(fn)
        local ok,err=pcall(fn)
        if not ok then errors[#errors+1]=tostring(err) end
    end
    if request.linear and request.linear.linearJob then
        release(function() assert(linear.cancel(request.linear)) end)
    end
    for _,actor in ipairs(job.actors) do
        if actor:IsValid() then release(function() actor:K2_DestroyActor() end) end
    end
    for _,target in ipairs(job.targets) do
        if target:IsValid() then release(function() job.lib:ReleaseRenderTarget2D(target) end) end
    end
    for _,file in ipairs({job.stage,job.recovery}) do
        if exists(file) then release(function() assert(os.remove(file)) end) end
    end
    request.motionJob = nil
    return #errors == 0, #errors > 0 and table.concat(errors, " / ") or nil
end

function motion.step(session, request, now)
    local job = request.motionJob
    if not job then return false, "No active timed exposure" end
    local ok, done, progress = pcall(function()
        if job.open then record(job,session.pose,now); return false,true end
        if not job.index then beginRender(session,request,job); return false,true end
        if job.index <= job.count then
            local p=job.poses[job.index]
            accumulate(session,job,job.display,job.displaySum,p)
            if job.raw then accumulate(session,job,job.raw,job.rawSum,p) end
            job.index = job.index + 1
            return false,true
        end
        if not job.pngTime then submitPNG(session,request,job,now); return false,true end
        if not job.pngSaved then
            local staged = job.stage
            if not job.recoverPNG then
                local ready,err=photo.checkFile({path=staged,crop=request.crop})
                if not ready then
                    if not err and now-job.pngTime<1 then return false,false end
                    job.recoverPNG=true
                end
            end
            if job.recoverPNG then
                if not png.step(job,request) then return false,true end
                staged=job.recovery
                local ready,err=photo.checkFile({path=staged,crop=request.crop})
                assert(ready,err or "Timed PNG readback is incomplete")
            end
            assert(not exists(request.path), "A PNG already exists at the shutter destination")
            assert(os.rename(staged,request.path))
            job.pngSaved = true
            if not request.linear then return true,true end
            local raw = request.linear
            raw.exposure = request.exposure
            local started,why=linear.fromTarget(session,raw,job.rawSum.rt,job.rawSum.w,job.left,job.count,job.count)
            assert(started,why)
            return false,true
        end
        local ready,err,advanced=linear.checkFile(request.linear,now)
        assert(not err,err)
        return ready,advanced
    end)
    if not ok or done then
        local cleaned,detail = motion.cancel(request)
        if not ok then
            local prefix = job.pngSaved and "PNG saved. EXR failed: " or ""
            return false,prefix .. tostring(done) .. (detail and (" / " .. detail) or "")
        end
        if not cleaned then return false,detail end
    end
    return done,nil,progress
end

return motion
