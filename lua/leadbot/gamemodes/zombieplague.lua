LeadBot.RespawnAllowed = false
LeadBot.SetModel = false
LeadBot.Gamemode = "zombieplague"
LeadBot.TeamPlay = true
LeadBot.LerpAim = true

local DEBUG = false
local HidingSpots = {}

function LeadBot.AddBotOverride(bot)
    RoundManager:AddPlayerToPlay(bot)
end

local function addSpots()
    local areas = navmesh.GetAllNavAreas()
    local hidingspots = {}
    local spotsReset = {}

    for _, area in pairs(areas) do
        local spots = area:GetHidingSpots(1)
        -- local spots2 = area:GetHidingSpots(8)
        local spotsReset2 = {}

        for _, spot in pairs(spots) do
            if !util.QuickTrace(spot, Vector(0, 0, 72)).Hit and !util.QuickTrace(spot, Vector(0, 0, 72)).Hit and !util.TraceHull({start = spot, endpos = spot + Vector(0, 0, 72), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72)}).HitWorld then
                table.Add(hidingspots, spots)
                table.insert(spotsReset2, spot)
            end
        end

        table.insert(spotsReset, {area, spotsReset2})

        -- table.Add(hidingspots, spots2)

        -- the reason why we don't use spots2 is because these are barely hidden
        -- we should only use it when there are not enough normal hiding spots to diversify hiding places
    end

    MsgN("Found " .. #hidingspots .. " default hiding spots!")
    if #hidingspots < 1 then return end
    --[[MsgN("Teleporting to one...")
    ply:SetPos(table.Random(hidingspots))]]

    HidingSpots = spotsReset
end

function LeadBot.StartCommand(bot, cmd)
    local buttons = IN_SPEED
    local botWeapon = bot:GetActiveWeapon()
    local controller = bot.ControllerBot
    local target = controller.Target

    if !IsValid(controller) then return end

    if bot:IsHuman() then
        buttons = 0
    end

    if IsValid(botWeapon) and (botWeapon:Clip1() == 0 or !IsValid(target) and botWeapon:Clip1() <= botWeapon:GetMaxClip1() / 2) then
        buttons = buttons + IN_RELOAD
    end

    if IsValid(target) and target:GetPos():DistToSqr(bot:GetPos()) < 5000 then
        buttons = buttons + IN_ATTACK
    end

    if bot:GetMoveType() == MOVETYPE_LADDER then
        local pos = controller.goalPos
        local ang = ((pos + bot:GetCurrentViewOffset()) - bot:GetShootPos()):Angle()

        if pos.z > controller:GetPos().z then
            controller.LookAt = Angle(-30, ang.y, 0)
        else
            controller.LookAt = Angle(30, ang.y, 0)
        end

        controller.LookAtTime = CurTime() + 0.1
        controller.NextJump = -1
        buttons = buttons + IN_FORWARD
    end

    if controller.NextDuck > CurTime() then
        buttons = buttons + IN_DUCK
    elseif controller.NextJump == 0 then
        controller.NextJump = CurTime() + 1
        buttons = buttons + IN_JUMP
    end

    if !bot:IsOnGround() and controller.NextJump > CurTime() then
        buttons = buttons + IN_DUCK
    end

    bot:SelectWeapon((IsValid(controller.Target) and controller.Target:GetPos():DistToSqr(controller:GetPos()) < 129000 and "weapon_shotgun") or "weapon_smg1")
    cmd:ClearButtons()
    cmd:ClearMovement()
    cmd:SetButtons(buttons)
end

-- local function findNearest(bot, radius, filter)
--     local pos = bot:EyePos()

-- 	local plys = {}
-- 	for num, ply in ipairs((radius == nil) and player_GetAll() or ents_FindInSphere(pos, radius)) do
-- 		if IsValid(ply) and ply:IsPlayer() and (!filter or !isfunction(filter) or filter(ply)) then
-- 			table_insert(plys, {pos:Distance(ply:GetPos()), ply})
-- 		end
-- 	end
	
-- 	local output = nil
-- 	for _, tbl in ipairs(plys) do
-- 		if !output or (tbl[1] < output[1]) then
-- 			output = tbl
-- 		end
-- 	end

--     local ret = nil
--     for _, tbl in ipairs(output) do
--         if tbl[2]:is
--     end

-- 	return ret
-- end

function LeadBot.PlayerMove(bot, cmd, mv)
    if #HidingSpots < 1 then
        addSpots()
    end

    local controller = bot.ControllerBot

    if !IsValid(controller) then
        bot.ControllerBot = ents.Create("leadbot_navigator")
        bot.ControllerBot:Spawn()
        bot.ControllerBot:SetOwner(bot)
        controller = bot.ControllerBot
    end

    -- force a recompute
    if controller.PosGen and controller.P and controller.TPos ~= controller.PosGen then
        controller.TPos = controller.PosGen
        controller.P:Compute(controller, controller.PosGen)
    end

    if controller:GetPos() ~= bot:GetPos() then
        controller:SetPos(bot:GetPos())
    end

    if controller:GetAngles() ~= bot:EyeAngles() then
        controller:SetAngles(bot:EyeAngles())
    end

    mv:SetForwardSpeed(1200)

    if (bot.NextSpawnTime and bot.NextSpawnTime + 1 > CurTime()) or !IsValid(controller.Target) or controller.ForgetTarget < CurTime() or controller.Target:Health() < 1 then
        controller.Target = nil
    end

    if !IsValid(controller.Target) then
        local tbl = player.findNearest(bot:EyePos(), bot:IsZombie() and nil or 512, function(ply)
            if (ply == bot) or (ply:Team() == bot:Team()) or !ply:Alive() then return false end

            if bot:IsHuman() and !controller:CanSee(ply) then
                return false
            end

            local tr = util.TraceLine({
                start = bot:LocalToWorld(bot:OBBMaxs()),
                endpos = ply:LocalToWorld(ply:OBBCenter()),
                endpos = function()
                    
                end,
            })

            -- ply:SetPos(tr["HitPos"])

            -- debugoverlay.Cross(tr["HitPos"], 5)

            print(tr["Entity"] == ply)

            return true
        end)

        if istable(tbl) and IsValid(tbl[2]) then
            -- print(tbl[2])
            controller.Target = tbl[2]
            controller.ForgetTarget = CurTime() + 2
        end
    elseif controller.ForgetTarget < CurTime() and controller:CanSee(controller.Target) then
        controller.ForgetTarget = CurTime() + 2
    end

    local dt = util.QuickTrace(bot:EyePos(), bot:GetForward() * 45, bot)

    if (bot.doorsDelay or 0) < CurTime() then
        local door = dt.Entity
        if IsValid(door) and (door:GetClass() == "prop_door_rotating") then
            door:SetKeyValue("opendir", 2)
            bot:Freeze(true)

            timer.Simple(1, function()
                if IsValid(door) and IsValid(bot) then
                    if bot:IsZombie() then
                        door:Fire("Unlock")
                    end

                    door:Fire("Open")
                    
                    timer.Simple(1, function()
                        if IsValid(bot) then
                            bot:Freeze(false)
                        end
                    end)
                end
            end)

            -- bot:Freeze(true)
            -- timer.Simple(1, function()
            --     if IsValid(bot) then
            --         bot:Freeze(false)
            --     end
            -- end)
        end

        bot.doorsDelay = CurTime() + 1
    end

    if bot:Team() ~= TEAM_HUMANS and bot.hidingspot then
        bot.hidingspot = nil
    end

    if DEBUG then
        debugoverlay.Text(bot:EyePos(), bot:Nick(), 0.03, false)
        local min, max = bot:GetHull()
        debugoverlay.Box(bot:GetPos(), min, max, 0.03, Color(255, 255, 255, 0))

        if bot.hidingspot then
            debugoverlay.Text(bot.hidingspot, bot:Nick() .. "'s hiding spot!", 0.1, false)
        end
    end

    if !IsValid(controller.Target) and ((bot:Team() ~= TEAM_HUMANS and (!controller.PosGen or (controller.PosGen and bot:GetPos():DistToSqr(controller.PosGen) < 5000))) or bot:Team() == TEAM_HUMANS or controller.LastSegmented < CurTime()) then
        if bot:Team() == TEAM_HUMANS then
            -- hiding ai
            if !bot.hidingspot then
                local area = table.Random(HidingSpots)

                if #area[2] > 0 and controller.loco:IsAreaTraversable(area[1]) then
                    local spot = table.Random(area[2])
                    bot.hidingspot = spot
                end
            else
                local dist = bot:GetPos():DistToSqr(bot.hidingspot)
                if dist < 1200 then -- we're here
                    controller.PosGen = nil
                else -- we need to run...
                    controller.PosGen = bot.hidingspot
                end
            end

            controller.LastSegmented = CurTime() + 3
        else
            -- search all hiding spots we know of...
            local area = table.Random(HidingSpots)

            if #area[2] > 0 and controller.loco:IsAreaTraversable(area[1]) then
                local spot = table.Random(area[2])
                controller.PosGen =  spot
            end

            controller.LastSegmented = CurTime() + 10
        end
    elseif IsValid(controller.Target) then
        -- move to our target
        local distance = controller.Target:GetPos():DistToSqr(bot:GetPos())
        controller.PosGen = controller.Target:GetPos()

        -- back up if the target is really close
        -- TODO: find a random spot rather than trying to back up into what could just be a wall
        -- something like controller.PosGen = controller:FindSpot("random", {pos = bot:GetPos() - bot:GetForward() * 350, radius = 1000})?
        -- if bot:Team() != TEAM_ZOMBIES and distance <= 160000 then
        --     mv:SetForwardSpeed(-1200)
        -- end
    end

    -- movement also has a similar issue, but it's more severe...
    if !controller.P then
        return
    end

    local segments = controller.P:GetAllSegments()

    if !segments then return end

    local cur_segment = controller.cur_segment
    local curgoal = (controller.PosGen and segments[cur_segment])

    -- eyesight
    local lerp = FrameTime() * math.random(8, 10)
    local lerpc = FrameTime() * 8
    local mva

    if !LeadBot.LerpAim then
        lerp = 1
        lerpc = 1
    end

    -- got nowhere to go, why keep moving?
    if curgoal then
        -- think every step of the way!
        if segments[cur_segment + 1] and Vector(bot:GetPos().x, bot:GetPos().y, 0):DistToSqr(Vector(curgoal.pos.x, curgoal.pos.y)) < 100 then
            controller.cur_segment = controller.cur_segment + 1
            curgoal = segments[controller.cur_segment]
        end

        local goalpos = curgoal.pos

        if bot:GetVelocity():Length2DSqr() <= 225 then
            if controller.NextCenter < CurTime() then
                controller.strafeAngle = ((controller.strafeAngle == 1 and 2) or 1)
                controller.NextCenter = CurTime() + math.Rand(0.3, 0.65)
            elseif controller.nextStuckJump < CurTime() then
                if !bot:Crouching() then
                    controller.NextJump = 0
                end
                controller.nextStuckJump = CurTime() + math.Rand(1, 2)
            end
        end

        local runSpeed = bot:GetRunSpeed()
        if controller.NextCenter > CurTime() then
            if controller.strafeAngle == 1 then
                mv:SetSideSpeed(runSpeed)
            elseif controller.strafeAngle == 2 then
                mv:SetSideSpeed(-runSpeed)
            else
                mv:SetForwardSpeed(-runSpeed)
            end
        end

        -- jump
        if controller.NextJump ~= 0 and curgoal.type > 1 and controller.NextJump < CurTime() then
            controller.NextJump = 0
        end

        -- duck
        if curgoal.area:GetAttributes() == NAV_MESH_CROUCH then
            controller.NextDuck = CurTime() + 0.1
        end

        controller.goalPos = goalpos

        if DEBUG then
            controller.P:Draw()
        end

        mva = ((goalpos + bot:GetCurrentViewOffset()) - bot:GetShootPos()):Angle()

        mv:SetMoveAngles(mva)
    else
        mv:SetForwardSpeed(0)
    end

    if IsValid(controller.Target) then
        bot:SetEyeAngles(LerpAngle(lerp, bot:EyeAngles(), (controller.Target:EyePos() - bot:GetShootPos()):Angle()))
        return
    elseif curgoal then
        if controller.LookAtTime > CurTime() then
            local ang = LerpAngle(lerpc, bot:EyeAngles(), controller.LookAt)
            bot:SetEyeAngles(Angle(ang.p, ang.y, 0))
        else
            local ang = LerpAngle(lerpc, bot:EyeAngles(), mva)
            bot:SetEyeAngles(Angle(ang.p, ang.y, 0))
        end
    elseif bot.hidingspot then
        bot.NextSearch = bot.NextSearch or CurTime()
        bot.SearchAngle = bot.SearchAngle or Angle(0, 0, 0)

        if bot.NextSearch < CurTime() then
            bot.NextSearch = CurTime() + math.random(2, 3)
            bot.SearchAngle = Angle(math.random(-40, 40), math.random(-180, 180), 0)
        end

        bot:SetEyeAngles(LerpAngle(lerp, bot:EyeAngles(), bot.SearchAngle))
    end
end

function LeadBot.PostPlayerDeath(bot)
    bot.hidingspot = nil
end

if !DEBUG then return end

concommand.Add("hidingSpot", function(ply, _, args)
    addSpots()
end)