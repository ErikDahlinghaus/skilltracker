addon.name = 'skilltracker'
addon.author = 'gnubeardo'
addon.version = '1.0'
addon.desc = 'Tracks your combat and magic skills against your cap'
addon.link = 'https://github.com/ErikDahlinghaus/skilltracker'

require('common')
local imgui = require('imgui')
local settings = require('settings')
local chat = require('chat')

-- Load our data tables
local jobs = require('jobs')
local skills = require('skills')
local skillranks = require('skillranks')
local skillcaps = require('skillcaps')

-- Ordered skill list for display (grouped by category, alphabetical within each)
local orderedSkills = {
    -- Combat Skills (alphabetical)
    'Axe', 'Club', 'Dagger', 'Great Axe', 'Great Katana', 'Great Sword',
    'Hand-to-Hand', 'Katana', 'Polearm', 'Scythe', 'Staff', 'Sword',

    -- Ranged Skills (alphabetical)
    'Archery', 'Marksmanship', 'Throwing',

    -- Defensive Skills (alphabetical)
    'Evasion', 'Guarding', 'Parrying', 'Shield',

    -- Magic Skills (alphabetical)
    'Blue', 'Dark', 'Divine', 'Elemental', 'Enfeebling', 'Enhancing',
    'Geomancy', 'Handbell', 'Healing', 'Ninjutsu', 'Singing', 'String',
    'Summoning', 'Wind',
}

-- Default configuration
local defaultConfig = T{
    visible = T{true},
    opacity = T{0.8},
    scale = T{1.0},
    showTitleBar = T{true},
    showHeader = T{true},
    showRank = T{true},
    showProgress = T{true},
    showCanSkillUp = T{true},
    -- Skill visibility (all enabled by default)
    showSkills = T{
        ["Hand-to-Hand"] = T{true},
        ["Dagger"] = T{true},
        ["Sword"] = T{true},
        ["Great Sword"] = T{true},
        ["Axe"] = T{true},
        ["Great Axe"] = T{true},
        ["Scythe"] = T{true},
        ["Polearm"] = T{true},
        ["Katana"] = T{true},
        ["Great Katana"] = T{true},
        ["Club"] = T{true},
        ["Staff"] = T{true},
        ["Archery"] = T{true},
        ["Marksmanship"] = T{true},
        ["Throwing"] = T{true},
        ["Guarding"] = T{true},
        ["Evasion"] = T{true},
        ["Shield"] = T{true},
        ["Parrying"] = T{true},
        ["Divine"] = T{true},
        ["Healing"] = T{true},
        ["Enhancing"] = T{true},
        ["Enfeebling"] = T{true},
        ["Elemental"] = T{true},
        ["Dark"] = T{true},
        ["Summoning"] = T{true},
        ["Ninjutsu"] = T{true},
        ["Singing"] = T{true},
        ["String"] = T{true},
        ["Wind"] = T{true},
        ["Blue"] = T{true},
        ["Geomancy"] = T{true},
        ["Handbell"] = T{true},
    },
    expireMobLevelsSeconds = 60
}

local config = settings.load(defaultConfig)

-- Window state
local isOpen = {true}
local configMenuOpen = {false}
local configMenuWasOpen = false

-- Mob level cache (populated from check packets and widescan)
-- Stores: mobLevels[targetIndex] = {name = "Goblin", level = 15, timestamp = os.time()}
-- Entries expire after expireMobLevelsSeconds seconds
local mobLevels = T{}

--------------------------------------------------------------------
-- Get player's current skill level
--------------------------------------------------------------------
local function getSkillLevel(skillId)
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then return 0 end

    return player:GetCombatSkill(skillId):GetSkill()
end

--------------------------------------------------------------------
-- Get player's skill cap for a given skill
--------------------------------------------------------------------
local function getSkillCap(jobAbbr, skillName, level)
    -- Get the rank for this job/skill combo
    local rank = skillranks[jobAbbr] and skillranks[jobAbbr][skillName]
    if not rank then return nil end

    -- Get the cap for this rank/level combo
    local cap = skillcaps[rank] and skillcaps[rank][level]
    return cap
end

--------------------------------------------------------------------
-- Get current target information if it's a mob
--------------------------------------------------------------------
local function getTargetMob()
    local memMgr = AshitaCore:GetMemoryManager()
    local entMgr = memMgr:GetEntity()
    local targetMgr = memMgr:GetTarget()
    local targetIndex = targetMgr:GetTargetIndex(targetMgr:GetIsSubTargetActive())

    if targetIndex > 0 then
        -- Check if target is a mob (spawn flag 0x10)
        if bit.band(entMgr:GetSpawnFlags(targetIndex), 0x10) ~= 0 then
            local mobName = entMgr:GetName(targetIndex)
            local cachedData = mobLevels[targetIndex]

            -- Check if we have cached level data AND name matches AND not expired
            local level = nil
            if cachedData and cachedData.name == mobName and cachedData.level > 0 then
                local age = os.time() - cachedData.timestamp
                if age < config.expireMobLevelsSeconds then  -- Expire after expireMobLevelsSeconds seconds
                    level = cachedData.level
                end
            end

            -- Always return mob info, level may be nil if not checked yet
            return {
                name = mobName,
                level = level,
                index = targetIndex
            }
        end
    end

    return nil
end

--------------------------------------------------------------------
-- Check if a mob can give skill ups for a given skill level
-- Formula: Find the minimum level where skill cap exceeds current skill
--------------------------------------------------------------------
local function canSkillUp(jobAbbr, skillName, mobLevel, currentSkill, playerCap)
    if currentSkill >= playerCap then
        return false -- Already at cap for player's level
    end

    -- Get the rank for this job/skill combo
    local rank = skillranks[jobAbbr] and skillranks[jobAbbr][skillName]
    if not rank then return false end

    -- Get the skill caps for this rank
    local rankCaps = skillcaps[rank]
    if not rankCaps then return false end

    -- Find the minimum level where the cap exceeds current skill
    -- Start from level 1 and find where cap first exceeds current skill
    for level = 1, 99 do
        local cap = rankCaps[level]
        if cap and cap > currentSkill then
            -- This is the minimum level needed for skill ups
            return mobLevel >= level
        end
    end

    return false
end

--------------------------------------------------------------------
-- Render the skill tracker window
--------------------------------------------------------------------
local function renderSkillTracker()
    -- Get player info
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    if player == nil then return end

    local mainJobId = player:GetMainJob()
    local mainJobLevel = player:GetMainJobLevel()
    local jobAbbr = jobs[mainJobId]

    if not jobAbbr then return end

    -- Get skills for this job
    local jobSkills = skillranks[jobAbbr]
    if not jobSkills then return end

    -- Set window properties
    imgui.SetNextWindowBgAlpha(config.opacity[1])
    imgui.SetNextWindowSize({-1, -1}, ImGuiCond_Always)

    -- Build window flags
    local windowFlags = ImGuiWindowFlags_AlwaysAutoResize
    if not config.showTitleBar[1] then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoTitleBar)
    end

    if imgui.Begin(string.format('%s v%s', addon.name, addon.version), isOpen, windowFlags) then
        imgui.SetWindowFontScale(config.scale[1])

        -- Get target mob info (needed even if header is hidden)
        local targetMob = getTargetMob()

        -- Header (optional)
        if config.showHeader[1] then
            imgui.Text(string.format('Job: %s    Level: %d', jobAbbr, mainJobLevel))
            imgui.SameLine()
            imgui.SetCursorPosX(imgui.GetWindowWidth() - 80)
            if imgui.SmallButton('Config') then
                configMenuOpen[1] = not configMenuOpen[1]
            end

            -- Display targeted mob info
            if targetMob then
                if targetMob.level then
                    imgui.Text(string.format('Target: %s (Lv. %d)', targetMob.name, targetMob.level))
                else
                    imgui.Text('Target: ' .. targetMob.name)
                    imgui.SameLine()
                    imgui.TextColored({1.0, 0.8, 0.0, 1.0}, ' (use /check to see skill ups)')
                end
            else
                imgui.TextColored({0.7, 0.7, 0.7, 1.0}, 'Target: None (target a mob)')
            end

            imgui.Separator()
            imgui.Text('')
        end

        -- Column headers
        local currentPos = 160
        imgui.Text('Skill')

        if config.showRank[1] then
            imgui.SameLine()
            imgui.SetCursorPosX(currentPos)
            imgui.Text('Rank')
            currentPos = currentPos + 55
        end

        imgui.SameLine()
        imgui.SetCursorPosX(currentPos)
        imgui.Text('Current')
        currentPos = currentPos + 70

        imgui.SameLine()
        imgui.SetCursorPosX(currentPos)
        imgui.Text('Cap')
        currentPos = currentPos + 50

        if config.showProgress[1] then
            imgui.SameLine()
            imgui.SetCursorPosX(currentPos)
            imgui.Text('Progress')
            currentPos = currentPos + 160
        end

        if config.showCanSkillUp[1] then
            imgui.SameLine()
            imgui.SetCursorPosX(currentPos)
            imgui.Text('Can Skill Up?')
        end

        imgui.Separator()

        -- Display each skill (only if enabled in config)
        for _, skillName in ipairs(orderedSkills) do
            local rank = jobSkills[skillName]
            local skillId = skills[skillName]
            -- Check if this skill should be shown
            local shouldShow = config.showSkills[skillName] and config.showSkills[skillName][1]
            if shouldShow == nil then shouldShow = true end -- Default to true if not in configs

            if rank and skillId and shouldShow then
                local currentSkill = getSkillLevel(skillId)
                local cap = getSkillCap(jobAbbr, skillName, mainJobLevel)

                if cap then
                    local canGainSkill = targetMob and targetMob.level and canSkillUp(jobAbbr, skillName, targetMob.level, currentSkill, cap)

                    -- Calculate column positions dynamically
                    local colPos = 160

                    -- Color code the skill name based on whether we can skill up
                    if targetMob and targetMob.level and canGainSkill then
                        imgui.TextColored({0.0, 1.0, 0.0, 1.0}, skillName) -- Green if can skill up
                    else
                        imgui.Text(skillName)
                    end

                    -- Rank (optional)
                    if config.showRank[1] then
                        imgui.SameLine()
                        imgui.SetCursorPosX(colPos)
                        imgui.Text(rank)
                        colPos = colPos + 55
                    end

                    -- Current skill
                    imgui.SameLine()
                    imgui.SetCursorPosX(colPos)
                    imgui.Text(string.format('%d', currentSkill))
                    colPos = colPos + 70

                    -- Cap
                    imgui.SameLine()
                    imgui.SetCursorPosX(colPos)
                    imgui.Text(string.format('%d', cap))
                    colPos = colPos + 50

                    -- Progress bar (optional)
                    if config.showProgress[1] then
                        imgui.SameLine()
                        imgui.SetCursorPosX(colPos)
                        local progress = math.min(currentSkill / cap, 1.0)
                        imgui.ProgressBar(progress, {150, 0})
                        colPos = colPos + 160
                    end

                    -- Skill up indicator (optional)
                    if config.showCanSkillUp[1] then
                        imgui.SameLine()
                        imgui.SetCursorPosX(colPos)
                        if targetMob and targetMob.level then
                            if canGainSkill then
                                imgui.TextColored({0.0, 1.0, 0.0, 1.0}, 'YES')
                            else
                                imgui.TextColored({1.0, 0.3, 0.3, 1.0}, 'NO')
                            end
                        else
                            imgui.TextColored({0.5, 0.5, 0.5, 1.0}, '-')
                        end
                    end
                end
            end
        end

        imgui.SetWindowFontScale(1.0)
    end
    imgui.End()

    -- Update visibility
    config.visible[1] = isOpen[1]
end

--------------------------------------------------------------------
-- Render the configuration window
--------------------------------------------------------------------
local function renderConfigMenu()
    imgui.SetNextWindowSize({550, 700}, ImGuiCond_FirstUseEver)

    if imgui.Begin(string.format('%s v%s Configuration', addon.name, addon.version), configMenuOpen, ImGuiWindowFlags_NoCollapse) then
        imgui.Text('Skill Tracker Configuration')
        imgui.Separator()
        imgui.Text('')

        -- Window Settings
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Window Settings')
        imgui.Separator()

        imgui.SliderFloat('Window Opacity', config.opacity, 0.1, 1.0, '%.2f')
        imgui.ShowHelp('Set the window background opacity.')

        imgui.SliderFloat('Window Scale', config.scale, 0.5, 2.0, '%.2f')
        imgui.ShowHelp('Scale the window size.')

        imgui.Text('')

        imgui.Checkbox('Show Title Bar', config.showTitleBar)
        imgui.ShowHelp('Show window title bar with X and minimize buttons. Use /st config to open settings when hidden.')

        imgui.Checkbox('Show Header', config.showHeader)
        imgui.ShowHelp('Show job/level, target info, and config button. Use /st config to open settings when hidden.')

        imgui.Checkbox('Show Rank Column', config.showRank)
        imgui.ShowHelp('Show skill rank (A+, B-, etc.) for your job.')

        imgui.Checkbox('Show Progress Bar Column', config.showProgress)
        imgui.ShowHelp('Show progress bars for each skill.')

        imgui.Checkbox('Show "Can Skill Up?" Column', config.showCanSkillUp)
        imgui.ShowHelp('Show which skills can gain skillups from targeted mob. Skill will still turn green if you can skill up.')

        imgui.Text('')
        imgui.Separator()
        imgui.Text('')

        -- Combat Skills
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Combat Skills')
        imgui.SameLine()
        imgui.SetCursorPosX(200)
        if imgui.SmallButton('Select All##combat') then
            local combatSkills = {
                'Axe', 'Club', 'Dagger', 'Great Axe', 'Great Katana', 'Great Sword',
                'Hand-to-Hand', 'Katana', 'Polearm', 'Scythe', 'Staff', 'Sword'
            }
            for _, skillName in ipairs(combatSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = true
                end
            end
        end
        imgui.SameLine()
        if imgui.SmallButton('Select None##combat') then
            local combatSkills = {
                'Axe', 'Club', 'Dagger', 'Great Axe', 'Great Katana', 'Great Sword',
                'Hand-to-Hand', 'Katana', 'Polearm', 'Scythe', 'Staff', 'Sword'
            }
            for _, skillName in ipairs(combatSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = false
                end
            end
        end
        imgui.Separator()

        local combatSkills = {
            'Axe', 'Club', 'Dagger', 'Great Axe', 'Great Katana', 'Great Sword',
            'Hand-to-Hand', 'Katana', 'Polearm', 'Scythe', 'Staff', 'Sword'
        }

        imgui.Columns(3, nil, false)
        for _, skillName in ipairs(combatSkills) do
            if config.showSkills[skillName] then
                imgui.Checkbox(skillName, config.showSkills[skillName])
                imgui.NextColumn()
            end
        end
        imgui.Columns(1)

        imgui.Text('')
        imgui.Separator()
        imgui.Text('')

        -- Ranged Skills
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Ranged Skills')
        imgui.SameLine()
        imgui.SetCursorPosX(200)
        if imgui.SmallButton('Select All##ranged') then
            local rangedSkills = {'Archery', 'Marksmanship', 'Throwing'}
            for _, skillName in ipairs(rangedSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = true
                end
            end
        end
        imgui.SameLine()
        if imgui.SmallButton('Select None##ranged') then
            local rangedSkills = {'Archery', 'Marksmanship', 'Throwing'}
            for _, skillName in ipairs(rangedSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = false
                end
            end
        end
        imgui.Separator()

        local rangedSkills = {'Archery', 'Marksmanship', 'Throwing'}

        imgui.Columns(3, nil, false)
        for _, skillName in ipairs(rangedSkills) do
            if config.showSkills[skillName] then
                imgui.Checkbox(skillName, config.showSkills[skillName])
                imgui.NextColumn()
            end
        end
        imgui.Columns(1)

        imgui.Text('')
        imgui.Separator()
        imgui.Text('')

        -- Defensive Skills
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Defensive Skills')
        imgui.SameLine()
        imgui.SetCursorPosX(200)
        if imgui.SmallButton('Select All##defensive') then
            local defensiveSkills = {'Evasion', 'Guarding', 'Parrying', 'Shield'}
            for _, skillName in ipairs(defensiveSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = true
                end
            end
        end
        imgui.SameLine()
        if imgui.SmallButton('Select None##defensive') then
            local defensiveSkills = {'Evasion', 'Guarding', 'Parrying', 'Shield'}
            for _, skillName in ipairs(defensiveSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = false
                end
            end
        end
        imgui.Separator()

        local defensiveSkills = {'Evasion', 'Guarding', 'Parrying', 'Shield'}

        imgui.Columns(3, nil, false)
        for _, skillName in ipairs(defensiveSkills) do
            if config.showSkills[skillName] then
                imgui.Checkbox(skillName, config.showSkills[skillName])
                imgui.NextColumn()
            end
        end
        imgui.Columns(1)

        imgui.Text('')
        imgui.Separator()
        imgui.Text('')

        -- Magic Skills
        imgui.TextColored({0.4, 0.8, 1.0, 1.0}, 'Magic Skills')
        imgui.SameLine()
        imgui.SetCursorPosX(200)
        if imgui.SmallButton('Select All##magic') then
            local magicSkills = {
                'Blue', 'Dark', 'Divine', 'Elemental', 'Enfeebling', 'Enhancing',
                'Geomancy', 'Handbell', 'Healing', 'Ninjutsu', 'Singing', 'String',
                'Summoning', 'Wind'
            }
            for _, skillName in ipairs(magicSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = true
                end
            end
        end
        imgui.SameLine()
        if imgui.SmallButton('Select None##magic') then
            local magicSkills = {
                'Blue', 'Dark', 'Divine', 'Elemental', 'Enfeebling', 'Enhancing',
                'Geomancy', 'Handbell', 'Healing', 'Ninjutsu', 'Singing', 'String',
                'Summoning', 'Wind'
            }
            for _, skillName in ipairs(magicSkills) do
                if config.showSkills[skillName] then
                    config.showSkills[skillName][1] = false
                end
            end
        end
        imgui.Separator()

        local magicSkills = {
            'Blue', 'Dark', 'Divine', 'Elemental', 'Enfeebling', 'Enhancing',
            'Geomancy', 'Handbell', 'Healing', 'Ninjutsu', 'Singing', 'String',
            'Summoning', 'Wind'
        }

        imgui.Columns(3, nil, false)
        for _, skillName in ipairs(magicSkills) do
            if config.showSkills[skillName] then
                imgui.Checkbox(skillName, config.showSkills[skillName])
                imgui.NextColumn()
            end
        end
        imgui.Columns(1)

        imgui.Text('')
        imgui.Separator()

        if imgui.Button('  Save  ') then
            settings.save()
            configMenuOpen[1] = false
        end

        imgui.SameLine()
        if imgui.Button('  Reset  ') then
            settings.reset()
        end
        imgui.ShowHelp('Reset all settings to default values.')

        imgui.Separator()
    end
    imgui.End()
end

--------------------------------------------------------------------
-- Event: load
--------------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
end)

--------------------------------------------------------------------
-- Event: unload
--------------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
    settings.save()
end)

--------------------------------------------------------------------
-- Event: command
--------------------------------------------------------------------
ashita.events.register('command', 'command_cb', function(e)
    local args = e.command:args()
    if #args == 0 or not args[1]:any('/skilltracker', '/st') then
        return
    end

    -- Block the command
    e.blocked = true

    -- Check for subcommands
    if #args == 1 then
        -- Toggle main window
        isOpen[1] = not isOpen[1]
        config.visible[1] = isOpen[1]
        settings.save()
    elseif args[2]:any('config', 'settings') then
        -- Open config menu
        configMenuOpen[1] = not configMenuOpen[1]
    elseif args[2]:any('help') then
        print(chat.header(addon.name):append(chat.message('Commands:')))
        print(chat.header(addon.name):append(chat.message('  /skilltracker or /st - Toggle main window')))
        print(chat.header(addon.name):append(chat.message('  /skilltracker config - Open configuration menu')))
        print(chat.header(addon.name):append(chat.message('  /skilltracker help - Show this help')))
    end
end)

--------------------------------------------------------------------
-- Event: packet_in (capture mob levels from check/widescan)
--------------------------------------------------------------------
ashita.events.register('packet_in', 'packet_in_cb', function(e)
    -- Packet: Zone Enter / Zone Leave - clear mob level cache
    if e.id == 0x000A or e.id == 0x000B then
        mobLevels:clear()
        return
    end

    -- Packet: Message Basic (Check packet)
    if e.id == 0x0029 then
        local level = struct.unpack('l', e.data, 0x0C + 0x01) -- Param 1 (Level)
        local targetIndex = struct.unpack('H', e.data, 0x16 + 0x01) -- Target index

        -- Get the mob name for validation
        local entity = GetEntity(targetIndex)
        if entity and level > 0 then
            mobLevels[targetIndex] = {
                name = entity.Name,
                level = level,
                timestamp = os.time()
            }
        end
        return
    end

    -- Packet: Widescan Results
    if e.id == 0x00F4 then
        local idx = struct.unpack('H', e.data, 0x04 + 0x01)
        local lvl = struct.unpack('b', e.data, 0x06 + 0x01)

        -- Get the mob name for validation
        local entity = GetEntity(idx)
        if entity and lvl > 0 then
            mobLevels[idx] = {
                name = entity.Name,
                level = lvl,
                timestamp = os.time()
            }
        end
        return
    end
end)

--------------------------------------------------------------------
-- Event: d3d_present (render)
--------------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function()
    -- Render main window
    if config.visible[1] then
        renderSkillTracker()
    end

    -- Render config menu
    if configMenuOpen[1] then
        renderConfigMenu()
    end

    -- Save settings when config menu is closed
    if configMenuWasOpen and not configMenuOpen[1] then
        settings.save()
    end
    configMenuWasOpen = configMenuOpen[1]
end)

--------------------------------------------------------------------
-- Settings callback
--------------------------------------------------------------------
settings.register('settings', 'settings_update', function(s)
    if s ~= nil then
        config = s
    end
end)

