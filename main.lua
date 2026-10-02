--========================  SETTINGS  ========================--
-- (Kill Selected adapts by itself, nothing here needs touching)
local WALK_SPEED = 40
local JUMP_POWER = 120
local ROOT_HEIGHT = 3             -- HumanoidRootPart height above the ground

local SPACING_START = 4           -- first guess for studs behind the target
local SPACING_MIN = 2.5
local SPACING_MAX = 8
local MAX_PREDICT_SPEED = 45      -- studs/sec cap for lag compensation
local ENGAGE_DISTANCE = 10        -- walk to the target, lock behind once this close
local DISENGAGE_DISTANCE = 60     -- farther than this and the lock drops and it walks again
--============================================================--

local p = game.Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local uid = tostring(math.random(100000, 999999))
local LOCK_STEP = "KS_Lock_" .. uid
local CAM_STEP = "KS_Cam_" .. uid

local g = Instance.new("ScreenGui", p.PlayerGui)
g.ResetOnSpawn = false

local f = Instance.new("Frame", g)
f.Size = UDim2.new(0, 220, 0, 236)
f.Position = UDim2.new(0, 40, 0, 120)
f.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
f.BorderSizePixel = 0
f.Active = true
f.Draggable = true
Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)

local t = Instance.new("TextLabel", f)
t.Size = UDim2.new(1, 0, 0, 26)
t.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
t.Text = "Target"
t.TextColor3 = Color3.new(1, 1, 1)
t.Font = Enum.Font.GothamBold
t.TextSize = 13
t.BorderSizePixel = 0
Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8)

local x = Instance.new("TextButton", f)
x.Size = UDim2.new(0, 26, 0, 26)
x.Position = UDim2.new(1, -26, 0, 0)
x.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
x.TextColor3 = Color3.fromRGB(255, 200, 200)
x.Font = Enum.Font.GothamBold
x.TextSize = 14
x.Text = "X"
x.BorderSizePixel = 0
x.ZIndex = 10
Instance.new("UICorner", x).CornerRadius = UDim.new(0, 8)

local d = Instance.new("TextButton", f)
d.Size = UDim2.new(1, -16, 0, 26)
d.Position = UDim2.new(0, 8, 0, 32)
d.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
d.TextColor3 = Color3.fromRGB(230, 230, 230)
d.Font = Enum.Font.Gotham
d.TextSize = 12
d.Text = "Select player..."
d.BorderSizePixel = 0
Instance.new("UICorner", d).CornerRadius = UDim.new(0, 6)

local l = Instance.new("ScrollingFrame", f)
l.Size = UDim2.new(1, -16, 0, 100)
l.Position = UDim2.new(0, 8, 0, 60)
l.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
l.BorderSizePixel = 0
l.ScrollBarThickness = 4
l.CanvasSize = UDim2.new(0, 0, 0, 0)
l.AutomaticCanvasSize = Enum.AutomaticSize.Y
l.Visible = false
l.ZIndex = 5
Instance.new("UICorner", l).CornerRadius = UDim.new(0, 6)
Instance.new("UIListLayout", l).Padding = UDim.new(0, 2)

local b = Instance.new("TextButton", f)
b.Size = UDim2.new(1, -16, 0, 28)
b.Position = UDim2.new(0, 8, 0, 164)
b.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
b.TextColor3 = Color3.fromRGB(255, 200, 200)
b.Font = Enum.Font.GothamBold
b.TextSize = 12
b.Text = "OFF"
b.BorderSizePixel = 0
Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)

local k = Instance.new("TextButton", f)
k.Size = UDim2.new(1, -16, 0, 28)
k.Position = UDim2.new(0, 8, 0, 198)
k.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
k.TextColor3 = Color3.fromRGB(200, 200, 210)
k.Font = Enum.Font.GothamBold
k.TextSize = 12
k.Text = "KILL SELECTED: OFF"
k.BorderSizePixel = 0
Instance.new("UICorner", k).CornerRadius = UDim.new(0, 6)

local s = Instance.new("TextLabel", f)
s.Size = UDim2.new(1, -16, 0, 46)
s.Position = UDim2.new(0, 8, 0, 94)
s.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
s.TextColor3 = Color3.fromRGB(120, 220, 140)
s.Font = Enum.Font.Code
s.TextSize = 10
s.TextXAlignment = Enum.TextXAlignment.Left
s.TextYAlignment = Enum.TextYAlignment.Top
s.TextWrapped = true
s.Text = "Idle"
s.BorderSizePixel = 0
Instance.new("UICorner", s).CornerRadius = UDim.new(0, 6)

-------------------------------------------------------------------- state
local on = false
local kill = false
local locked = false
local target = nil
local facing = Vector3.new(0, 0, -1)
local lead = 0.15
local pathInfo = ""

-- auto-spacing (adapts from damage feedback)
local spacing = SPACING_START
local hurtAt = -100
local lastAdjust = -100
local hitStreak = 0
local missStreak = 0
local pendingSwing = nil
local lastOurHum = nil
local lastOurHealth = nil
local lastTargetHum = nil
local lastTargetHealth = nil
local animHum = nil
local animConn = nil

-- navigation
local waypoints = {}
local wpIndex = 1
local lastCompute = 0
local lastTargetPos = nil
local computing = false
local noPathCount = 0
local blocked = false
local directOk = false
local directPass = 0
local directFail = 0
local lastDirectCheck = 0
local lastSmooth = 0
local lastHopAt = -100
local lastClimbAt = -100
local jumpRestoreAt = nil
local lastStuckCheck = 0
local lastStuckPos = Vector3.zero
local stuckCount = 0
local sidestepUntil = 0
local sidestepSign = 1

local saved = nil
local conns = {}
local lastStatus = "Idle"

-- One place that writes the status box, so it can never go stale
local function setStatus(line1, line2)
    local text = line2 and (line1 .. "\n" .. line2) or line1
    if text ~= lastStatus then
        lastStatus = text
        s.Text = text
    end
end

local function resetState()
    waypoints = {}
    wpIndex = 1
    lastCompute = 0
    lastTargetPos = nil
    directOk = false
    directPass = 0
    directFail = 0
    locked = false
    lastStuckCheck = 0
    pathInfo = ""
    noPathCount = 0
    blocked = false
    stuckCount = 0
    sidestepUntil = 0
end

local function resetAdapt()
    spacing = SPACING_START
    hurtAt = -100
    lastAdjust = -100
    hitStreak = 0
    missStreak = 0
    pendingSwing = nil
end

-- Stop moving and give the character its original settings back
local function release()
    local c = p.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if hum and saved then
        hum.WalkSpeed = saved.speed
        hum.JumpPower = saved.jump
        hum.UseJumpPower = saved.useJump
        hum.AutoRotate = saved.autoRotate
    end
    saved = nil
    if hum and root then
        hum:MoveTo(root.Position)
    end
end

local function refreshButtons()
    b.Text = on and "ON" or "OFF"
    b.BackgroundColor3 = on and Color3.fromRGB(40, 70, 40) or Color3.fromRGB(60, 40, 40)
    b.TextColor3 = on and Color3.fromRGB(200, 255, 200) or Color3.fromRGB(255, 200, 200)
    k.Text = kill and "KILL SELECTED: ON" or "KILL SELECTED: OFF"
    k.BackgroundColor3 = kill and Color3.fromRGB(100, 40, 40) or Color3.fromRGB(45, 45, 55)
    k.TextColor3 = kill and Color3.fromRGB(255, 200, 200) or Color3.fromRGB(200, 200, 210)
end

local function stopAll()
    on = false
    kill = false
    resetState()
    release()
    setStatus("Idle")
    refreshButtons()
end

local function fill()
    for _, c in ipairs(l:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    for _, v in ipairs(game.Players:GetPlayers()) do
        if v ~= p then
            local y = Instance.new("TextButton", l)
            y.Size = UDim2.new(1, -8, 0, 22)
            y.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
            y.TextColor3 = Color3.fromRGB(230, 230, 230)
            y.Font = Enum.Font.Gotham
            y.TextSize = 11
            y.Text = v.Name
            y.BorderSizePixel = 0
            y.ZIndex = 6
            Instance.new("UICorner", y).CornerRadius = UDim.new(0, 4)
            y.MouseButton1Click:Connect(function()
                target = v
                d.Text = v.Name
                l.Visible = false
                resetState()
                resetAdapt()
                if not on then setStatus("Idle") end
            end)
        end
    end
end

d.MouseButton1Click:Connect(function()
    fill()
    l.Visible = not l.Visible
end)

b.MouseButton1Click:Connect(function()
    if not target then
        setStatus("No target")
        return
    end
    if on then
        stopAll()
    else
        on = true
        resetState()
        refreshButtons()
        setStatus("Starting...")
    end
end)

k.MouseButton1Click:Connect(function()
    if not target then
        setStatus("No target")
        return
    end
    kill = not kill
    locked = false
    if kill and not on then
        on = true
        resetState()
    end
    refreshButtons()
    setStatus(kill and "Kill: starting..." or "Following...")
end)

refreshButtons()

-------------------------------------------------------------------- helpers
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshFilter()
    local filter = {}
    for _, plr in ipairs(game.Players:GetPlayers()) do
        if plr.Character then table.insert(filter, plr.Character) end
    end
    rayParams.FilterDescendantsInstances = filter
end

-- Body-sized sweep (3 studs wide) so poles / railings / thin objects can't slip through.
-- Falls back to a dense ray fan if Blockcast isn't available.
local function sweepClear(a, flat)
    local len = flat.Magnitude
    if len < 0.1 then return true end
    local dir = flat.Unit
    local center = a + Vector3.new(0, 0.5, 0)
    local ok, hit = pcall(function()
        return workspace:Blockcast(CFrame.lookAt(center, center + dir), Vector3.new(2.6, 4.5, 1), flat, rayParams)
    end)
    if ok then return hit == nil end
    local side = dir:Cross(Vector3.new(0, 1, 0))
    for _, h in ipairs({ -1.2, 0.5, 2 }) do
        for _, off in ipairs({ -1.5, -1, -0.5, 0, 0.5, 1, 1.5 }) do
            if workspace:Raycast(a + Vector3.new(0, h, 0) + side * off, flat, rayParams) then
                return false
            end
        end
    end
    return true
end

-- True if walking in a straight line from a to b is unobstructed with continuous ground
-- (stairs and ramps are fine, pits and ledges are not).
-- Both a and b are HumanoidRootPart-height positions.
local function walkable(a, b)
    if math.abs(b.Y - a.Y) > 4 then return false end
    refreshFilter()

    local dir = b - a
    local flat = Vector3.new(dir.X, 0, dir.Z)
    local len = flat.Magnitude
    if len < 0.5 then return true end
    if not sweepClear(a, flat) then return false end

    local prev = workspace:Raycast(a, Vector3.new(0, -8, 0), rayParams)
    if not prev then return false end
    local steps = math.ceil(len / 2)
    for i = 1, steps do
        local pt = a + flat * (i / steps)
        local gr = workspace:Raycast(pt, Vector3.new(0, -8, 0), rayParams)
        if not gr or math.abs(gr.Position.Y - prev.Position.Y) > 2 then
            return false
        end
        prev = gr
    end
    return true
end

-- Walking goal: aim where the target will be, not where it is
local function predictGoal(root, tRoot)
    local dist = (tRoot.Position - root.Position).Magnitude
    local vel = tRoot.AssemblyLinearVelocity
    vel = Vector3.new(vel.X, 0, vel.Z)
    if vel.Magnitude > 60 then vel = vel.Unit * 60 end
    local ahead = math.clamp(dist / WALK_SPEED, 0, 1)
    return tRoot.Position + vel * ahead
end

local function groundY(px, py, pz)
    refreshFilter()
    local hit = workspace:Raycast(Vector3.new(px, py + 1, pz), Vector3.new(0, -30, 0), rayParams)
    return hit and hit.Position.Y or nil
end

-- Jump only as high as needed, so stairs / small gaps don't launch you 36 studs
local function hop(hum, need, now)
    if now - lastHopAt < 0.45 then return end
    lastHopAt = now
    local power = math.clamp(math.sqrt(2 * 196.2 * math.max(need, 2)) + 8, 40, JUMP_POWER)
    hum.UseJumpPower = true
    hum.JumpPower = power
    hum.Jump = true
    jumpRestoreAt = now + 0.35
end

local function grounded(hum)
    return hum.FloorMaterial ~= Enum.Material.Air
end

-- Lag compensation that adapts to your connection
local function autoLead()
    local ok, ping = pcall(function() return p:GetNetworkPing() end)
    if ok and type(ping) == "number" then
        return math.clamp(ping + 0.08, 0.1, 0.35)
    end
    return 0.15
end

-------------------------------------------------------------------- auto spacing
-- Taking damage while locked = they can reach us: back off.
-- Landing hits for a while = safe: creep a little farther out.
-- Swinging and missing repeatedly = too far: move in.
local function onHurt(now)
    missStreak = 0
    hitStreak = 0
    hurtAt = now
    if now - lastAdjust >= 0.5 then
        spacing = math.min(SPACING_MAX, spacing + 0.75)
        lastAdjust = now
    end
end

local function onHit(now)
    pendingSwing = nil
    missStreak = 0
    hitStreak = hitStreak + 1
    if hitStreak >= 3 and now - hurtAt > 4 and now - lastAdjust >= 0.5 then
        spacing = math.min(SPACING_MAX, spacing + 0.25)
        hitStreak = 0
        lastAdjust = now
    end
end

local function onMiss(now)
    hitStreak = 0
    missStreak = missStreak + 1
    if missStreak >= 3 and now - hurtAt > 1.5 and now - lastAdjust >= 0.5 then
        spacing = math.max(SPACING_MIN, spacing - 0.5)
        missStreak = 0
        lastAdjust = now
    end
end

local function onAnim(track)
    if not locked or track.Looped then return end
    local pr = track.Priority
    if pr == Enum.AnimationPriority.Action or pr == Enum.AnimationPriority.Action2
        or pr == Enum.AnimationPriority.Action3 or pr == Enum.AnimationPriority.Action4 then
        pendingSwing = tick()
    end
end

local function trackAdapt(now, hum, tHum)
    if hum ~= lastOurHum then
        lastOurHum = hum
        lastOurHealth = nil
    end
    local hp = hum.Health
    if lastOurHealth and hp < lastOurHealth - 0.5 and locked then onHurt(now) end
    lastOurHealth = hp

    if tHum ~= lastTargetHum then
        lastTargetHum = tHum
        lastTargetHealth = nil
    end
    if tHum then
        local th = tHum.Health
        if lastTargetHealth and th < lastTargetHealth - 0.5 and locked then onHit(now) end
        lastTargetHealth = th
    end

    if pendingSwing and now - pendingSwing > 0.7 then
        pendingSwing = nil
        if locked then onMiss(now) end
    end

    -- watch our own attack animations (re-attach after respawn)
    if hum ~= animHum then
        if animConn then animConn:Disconnect() end
        animConn = nil
        animHum = hum
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then animConn = animator.AnimationPlayed:Connect(onAnim) end
    end
end

-------------------------------------------------------------------- kill lock
local function updateFacing(tRoot)
    local lv = tRoot.CFrame.LookVector
    local flat = Vector3.new(lv.X, 0, lv.Z)
    if flat.Magnitude > 0.2 then facing = flat.Unit end
end

-- Where we should stand (directly behind the target) and what to face
local function computeLock(tRoot)
    updateFacing(tRoot)
    local vel = tRoot.AssemblyLinearVelocity
    vel = Vector3.new(vel.X, 0, vel.Z)
    if vel.Magnitude > MAX_PREDICT_SPEED then vel = vel.Unit * MAX_PREDICT_SPEED end

    local tPos = tRoot.Position
    local ahead = tPos + vel * lead
    local lockPos = ahead - facing * spacing

    -- stand on the ground / stairs behind them (never sink in, never hover on stairs)
    local y = tPos.Y
    local gy = groundY(lockPos.X, tPos.Y, lockPos.Z)
    if gy then
        local snap = gy + ROOT_HEIGHT
        if snap > y or y - snap <= 3.5 then y = snap end
    end
    lockPos = Vector3.new(lockPos.X, y, lockPos.Z)

    local face = Vector3.new(tPos.X, y, tPos.Z)
    if (face - lockPos).Magnitude < 0.5 then face = lockPos + facing end
    return lockPos, face
end

-- Runs several times per frame so the lock holds through physics and rendering
local function lockStep()
    if not (on and kill and locked and target) then return end
    local c = p.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    local tc = target.Character
    local tRoot = tc and tc:FindFirstChild("HumanoidRootPart")
    if not root or not tRoot then return end
    local tHum = tc:FindFirstChildOfClass("Humanoid")
    if tHum and tHum.Health <= 0 then return end
    -- too far to snap (teleport / long dash): let the main loop drop the lock and walk
    local dx, dz = tRoot.Position.X - root.Position.X, tRoot.Position.Z - root.Position.Z
    if math.sqrt(dx * dx + dz * dz) > DISENGAGE_DISTANCE then return end

    local lockPos, face = computeLock(tRoot)
    root.CFrame = CFrame.lookAt(lockPos, face)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

-- Point the camera at the target while locked so camera-aimed moves connect
local function aimCamera()
    if not (on and kill and locked and target) then return end
    local cam = workspace.CurrentCamera
    local tc = target.Character
    local tRoot = tc and tc:FindFirstChild("HumanoidRootPart")
    if not cam or not tRoot then return end
    local aimAt = tRoot.Position + Vector3.new(0, 1.5, 0)
    local camPos = cam.CFrame.Position
    if (aimAt - camPos).Magnitude < 0.5 then return end
    cam.CFrame = CFrame.lookAt(camPos, aimAt)
end

-------------------------------------------------------------------- pathing
local TIERS = {
    { AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, AgentJumpHeight = 20,
      AgentMaxSlope = 89, AgentCanClimb = true, WaypointSpacing = 4 },
    -- tighter agent for narrow sewer gaps / vents
    { AgentRadius = 1, AgentHeight = 4, AgentCanJump = true, AgentJumpHeight = 30,
      AgentMaxSlope = 89, AgentCanClimb = true, WaypointSpacing = 4 },
}

local function newPath(tier)
    local ok, pth = pcall(function() return PathfindingService:CreatePath(tier) end)
    if ok and pth then return pth end
    local plain = {}
    for key, v in pairs(tier) do
        if key ~= "AgentCanClimb" then plain[key] = v end
    end
    return PathfindingService:CreatePath(plain)
end

local function computePath()
    if computing then return end
    local c = p.Character
    if not c or not c:FindFirstChild("HumanoidRootPart") then return end
    if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then return end

    local myTarget = target
    local root = c:FindFirstChild("HumanoidRootPart")
    local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
    if not root or not tRoot then return end
    local start = root.Position
    local goal = predictGoal(root, tRoot)
    local realGoal = tRoot.Position

    computing = true
    lastCompute = tick()

    local ok, path, partial = pcall(function()
        local attempts = {}
        if (goal - realGoal).Magnitude > 1 then
            attempts[#attempts + 1] = { TIERS[1], goal }
        end
        attempts[#attempts + 1] = { TIERS[1], realGoal }
        attempts[#attempts + 1] = { TIERS[2], realGoal }
        local last, part = nil, nil
        for _, at in ipairs(attempts) do
            local pth = newPath(at[1])
            pth:ComputeAsync(start, at[2])
            last = pth
            if pth.Status == Enum.PathStatus.Success then return pth, nil end
            if not part and (pth.Status == Enum.PathStatus.ClosestNoPath
                or pth.Status == Enum.PathStatus.ClosestOutOfRange) then
                if #pth:GetWaypoints() > 1 then part = pth end
            end
        end
        return last, part
    end)
    computing = false

    -- Ignore results that arrive after the user toggled off or switched target
    if not on or target ~= myTarget then return end

    if not ok or not path then
        pathInfo = "path error"
        waypoints = {}
        noPathCount = noPathCount + 1
        return
    end

    if path.Status ~= Enum.PathStatus.Success then
        -- no full route: walk the partial route to the closest reachable point if there is one
        if partial then
            local pw = partial:GetWaypoints()
            if (pw[#pw].Position - start).Magnitude > 4 then
                waypoints = pw
                wpIndex = 2
                pathInfo = string.format("partial %d wp", #pw)
                lastTargetPos = realGoal
                return
            end
        end
        pathInfo = "no path"
        waypoints = {}
        noPathCount = noPathCount + 1
        if noPathCount >= 2 then blocked = true end
        return
    end

    local wps = path:GetWaypoints()
    pathInfo = string.format("%d wp", #wps)
    waypoints = wps
    wpIndex = (#wps > 1) and 2 or 1
    lastTargetPos = realGoal
    noPathCount = 0
    blocked = false
end

local function detail(dist)
    if pathInfo ~= "" then
        return string.format("%.0f studs | %s", dist, pathInfo)
    end
    return string.format("%.0f studs", dist)
end

-- No full route (wall / gap / pole / high ledge): push at the target, slide around thin
-- obstacles, hop gaps and low ledges, and hop up toward a target that is above us.
-- Returns true when pressed against something we can't get past (a wall).
local function blindApproach(root, hum, goal, now)
    local rp = root.Position
    local flat = Vector3.new(goal.X - rp.X, 0, goal.Z - rp.Z)
    local hdist = flat.Magnitude
    local rise = goal.Y - rp.Y

    if hdist < 0.5 then
        if rise > 3.5 and grounded(hum) and now - lastClimbAt > 0.8 then
            lastClimbAt = now
            hop(hum, rise + 3, now)
        end
        hum:MoveTo(goal)
        return false
    end

    local dir = flat.Unit
    refreshFilter()
    local fwd = dir * 3
    local facingWall = false
    local sideV = dir:Cross(Vector3.new(0, 1, 0))

    if not sweepClear(rp, fwd) then
        local headroom = workspace:Raycast(rp + Vector3.new(0, 4.5, 0), fwd, rayParams)
        if not headroom then
            hop(hum, 6, now)                          -- low ledge / step: hop it
        else
            local leftClear = sweepClear(rp + sideV * 2.8, fwd)
            local rightClear = sweepClear(rp - sideV * 2.8, fwd)
            if leftClear or rightClear then           -- pole / pillar: slide around it
                local sgn = sidestepSign
                if leftClear and not rightClear then sgn = 1
                elseif rightClear and not leftClear then sgn = -1 end
                hum:MoveTo(rp + sideV * sgn * 4 + dir * 3)
                return false
            end
            facingWall = true
        end
    end

    -- gap / pit just ahead: jump it
    local near = workspace:Raycast(rp + dir * 3, Vector3.new(0, -14, 0), rayParams)
    local far = workspace:Raycast(rp + dir * 6, Vector3.new(0, -14, 0), rayParams)
    if (not near or not far) and goal.Y > rp.Y - 8 and grounded(hum) then
        hop(hum, 4, now)
    end

    -- target well above us and no way up: hop toward them (high ledges / roofs)
    if rise > 3.5 and grounded(hum) and (hdist < 8 or facingWall) and now - lastClimbAt > 0.8 then
        lastClimbAt = now
        hop(hum, rise + 3, now)
    end

    hum:MoveTo(goal)
    return facingWall
end

-------------------------------------------------------------------- main loop
conns[#conns + 1] = RunService.Heartbeat:Connect(function()
    if not on then return end
    if not target then
        setStatus("No target")
        return
    end

    local c = p.Character
    local root = c and c:FindFirstChild("HumanoidRootPart")
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then
        locked = false
        waypoints = {}
        setStatus("Respawning...")
        return
    end

    if not saved then
        saved = { speed = hum.WalkSpeed, jump = hum.JumpPower, useJump = hum.UseJumpPower, autoRotate = hum.AutoRotate }
    end
    local now = tick()
    hum.WalkSpeed = WALK_SPEED
    hum.UseJumpPower = true
    if jumpRestoreAt and now >= jumpRestoreAt then jumpRestoreAt = nil end
    if not jumpRestoreAt then hum.JumpPower = JUMP_POWER end

    local tc = target.Character
    local tRoot = tc and tc:FindFirstChild("HumanoidRootPart")
    local tHum = tc and tc:FindFirstChildOfClass("Humanoid")
    trackAdapt(now, hum, tHum)

    if not tRoot or (tHum and tHum.Health <= 0) then
        locked = false
        waypoints = {}
        lastTargetPos = nil
        lastStuckCheck = 0
        hum.AutoRotate = saved.autoRotate
        hum:MoveTo(root.Position)
        setStatus(tRoot and "Target down" or "Waiting for target...")
        return
    end

    local dist = (tRoot.Position - root.Position).Magnitude
    local hdist = math.sqrt((tRoot.Position.X - root.Position.X) ^ 2 + (tRoot.Position.Z - root.Position.Z) ^ 2)
    local vdist = math.abs(tRoot.Position.Y - root.Position.Y)
    lead = autoLead()

    -- Kill Selected: walk to the target, then lock behind them.
    -- Horizontal range is what counts, so a target on a ledge / roof / floor above or
    -- below you still gets locked onto (the lock snaps you up or down to them).
    if kill then
        if not locked and (dist <= ENGAGE_DISTANCE or (hdist <= ENGAGE_DISTANCE and vdist <= 80)) then
            locked = true
        elseif locked and (hdist > DISENGAGE_DISTANCE or vdist > 120) then
            locked = false
        end
    else
        locked = false
    end

    if locked then
        hum.AutoRotate = false
        local wantPos = computeLock(tRoot)
        local err = (root.Position - wantPos).Magnitude
        lockStep()
        hum:MoveTo(root.Position)
        waypoints = {}
        lastTargetPos = nil
        lastStuckCheck = 0
        setStatus(err <= 2 and "LOCKED behind" or "Locking...",
            string.format("%.1f studs (auto %.1f)", dist, spacing))
        return
    end
    hum.AutoRotate = saved.autoRotate

    local verb = kill and "Chasing" or "Following"

    if dist <= 5 then
        hum:MoveTo(root.Position)
        lastStuckCheck = 0
        setStatus("Arrived", string.format("%.1f studs", dist))
        return
    end

    local goal = predictGoal(root, tRoot)

    -- Stuck detection: jump, re-path, and sidestep if it keeps happening
    -- (not when blocked: then we WANT to stay pressed against the wall)
    if lastStuckCheck == 0 then
        lastStuckCheck = now
        lastStuckPos = root.Position
    elseif now - lastStuckCheck > 0.6 then
        if (root.Position - lastStuckPos).Magnitude < 1 and dist > 8 then
            if not blocked then
                stuckCount = stuckCount + 1
                hop(hum, 6, now)
                waypoints = {}
                lastCompute = 0
                if stuckCount % 2 == 0 then
                    sidestepUntil = now + 0.5
                    sidestepSign = -sidestepSign
                end
            end
        else
            stuckCount = 0
        end
        lastStuckPos = root.Position
        lastStuckCheck = now
    end

    if now < sidestepUntil then
        local fwd = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
        local side = Vector3.new(1, 0, 0)
        if fwd.Magnitude > 0.1 then side = fwd.Unit:Cross(Vector3.new(0, 1, 0)) end
        setStatus("Unsticking...", string.format("%.0f studs", dist))
        hum:MoveTo(root.Position + side * sidestepSign * 10)
        return
    end

    -- Straight line to the target if it's clear and on the same level
    if now - lastDirectCheck > 0.1 then
        lastDirectCheck = now
        if dist < 150 and walkable(root.Position, goal) then
            directPass = directPass + 1
            directFail = 0
        else
            directFail = directFail + 1
            directPass = 0
        end
        -- hysteresis: needs 2 checks in a row to switch, so stairs / edges can't make it flicker
        if not directOk and directPass >= 2 then directOk = true
        elseif directOk and directFail >= 2 then directOk = false end
    end
    if directOk then
        waypoints = {} -- drop any old path so we never resume it by mistake
        lastTargetPos = nil
        noPathCount = 0
        blocked = false
        setStatus(verb .. " (direct)", string.format("%.0f studs", dist))
        hum:MoveTo(goal)
        return
    end

    -- Recompute when needed
    local needCompute = #waypoints == 0
        or wpIndex > #waypoints
        or (lastTargetPos ~= nil and (tRoot.Position - lastTargetPos).Magnitude > 8)
    local interval = blocked and 0.6 or 0.25
    if needCompute and not computing and now - lastCompute > interval then
        task.spawn(computePath)
    end

    if #waypoints > 0 and wpIndex <= #waypoints then
        -- Path smoothing: skip ahead to the furthest waypoint we can walk to directly
        if now - lastSmooth > 0.1 then
            lastSmooth = now
            local best = wpIndex
            for i = wpIndex + 1, math.min(wpIndex + 6, #waypoints) do
                if waypoints[i - 1].Action == Enum.PathWaypointAction.Jump then break end
                local nextPos = waypoints[i].Position + Vector3.new(0, ROOT_HEIGHT, 0)
                if walkable(root.Position, nextPos) then
                    best = i
                else
                    break
                end
            end
            wpIndex = best
        end

        local wp = waypoints[wpIndex]
        local flatDist = (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude

        if wp.Action == Enum.PathWaypointAction.Jump and flatDist < 6 then
            hop(hum, (wp.Position.Y + ROOT_HEIGHT) - root.Position.Y + 2.5, now)
        end
        if flatDist < 3 then
            wpIndex = wpIndex + 1
        end
        setStatus(verb .. " (path)", detail(dist))
        hum:MoveTo(wp.Position)
    else
        local wall = blindApproach(root, hum, goal, now)
        if blocked and wall then
            setStatus("BLOCKED - M1 the wall", detail(dist))
        elseif blocked then
            setStatus("No route - pushing on", detail(dist))
        else
            setStatus(verb .. " (searching)", detail(dist))
        end
    end
end)

conns[#conns + 1] = RunService.Stepped:Connect(function()
    lockStep()
end)

RunService:BindToRenderStep(LOCK_STEP, Enum.RenderPriority.Input.Value + 1, lockStep)
RunService:BindToRenderStep(CAM_STEP, Enum.RenderPriority.Camera.Value + 1, aimCamera)

conns[#conns + 1] = game.Players.PlayerRemoving:Connect(function(plr)
    if plr == target then
        target = nil
        stopAll()
        d.Text = "Select player..."
    end
end)

-- Close button: fully shut everything down, not just hide the GUI
x.MouseButton1Click:Connect(function()
    stopAll()
    for _, cn in ipairs(conns) do
        cn:Disconnect()
    end
    if animConn then animConn:Disconnect() end
    pcall(function() RunService:UnbindFromRenderStep(LOCK_STEP) end)
    pcall(function() RunService:UnbindFromRenderStep(CAM_STEP) end)
    g:Destroy()
end)
