local Merits = nil;

local function getMerits()
    if Merits then
        return Merits
    end

    local inv = AshitaCore:GetPointerManager():Get('inventory');
    if (inv == 0) then
        return;
    end
    local ptr = ashita.memory.read_uint32(inv);
    if (ptr == 0) then
        return;
    end
    ptr = ashita.memory.read_uint32(ptr);
    if (ptr == 0) then
        return;
    end
    ptr = ptr + 0x28A44;
    local count = ashita.memory.read_uint16(ptr + 2);
    local meritptr = ashita.memory.read_uint32(ptr + 4);
    if (count > 0) then
        for i = 1,count do
            local meritId = ashita.memory.read_uint16(meritptr + 0);
            local meritUpgrades = ashita.memory.read_uint8(meritptr + 3);
            Merits[meritId] = meritUpgrades;
            meritptr = meritptr + 4;
        end
    end

    return Merits
end

local skillIdtoMeritId = {
    [1] = 192,   -- Hand-to-Hand
    [2] = 194,   -- Dagger
    [3] = 196,   -- Sword
    [4] = 198,   -- Great Sword
    [5] = 200,   -- Axe
    [6] = 202,   -- Great Axe
    [7] = 204,   -- Scythe
    [8] = 206,   -- Polearm
    [9] = 208,   -- Katana
    [10] = 210,  -- Great Katana
    [11] = 212,  -- Club
    [12] = 214,  -- Staff
    [25] = 216,  -- Archery
    [26] = 218,  -- Marksmanship
    [27] = 220,  -- Throwing
    [28] = 222,  -- Guarding
    [29] = 224,  -- Evasion
    [30] = 226,  -- Shield
    [31] = 228,  -- Parrying
    [32] = 256,  -- Divine
    [33] = 258,  -- Healing
    [34] = 260,  -- Enhancing
    [35] = 262,  -- Enfeebling
    [36] = 264,  -- Elemental
    [37] = 266,  -- Dark
    [38] = 268,  -- Summoning
    [39] = 270,  -- Ninjutsu
    [40] = 272,  -- Singing
    [41] = 274,  -- String
    [42] = 276,  -- Wind
    [43] = 278,  -- Blue
    [44] = 280,  -- Geomancy
    [45] = 282,  -- Handbell
}

local function getMeritsBonusForSkill(skillId)
    local merits = getMerits();
    if (merits == nil) then
        return 0;
    end
    
    -- Each merit point gives you +2 skill bonus
    local bonusFromMerit = merits[skillId] * 2;
    return bonusFromMerit
end

return {
    getMeritsBonusForSkill = getMeritsBonusForSkill,
}