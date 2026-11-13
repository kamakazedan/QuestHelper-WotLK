QuestHelper_File["collect_util.lua"] = "1.4.1"
QuestHelper_Loadtime["collect_util.lua"] = GetTime()

local function IsMonsterGUID(guid)
  if not guid then return false end  -- it's gone already
  QuestHelper: Assert(#guid == 18, "guid len " .. guid) -- 64 bits, plus the 0x prefix
  QuestHelper: Assert(guid:sub(1, 2) == "0x", "guid 0x-prefix " .. guid)
  return guid:sub(5, 5) == "3" or guid:sub(5, 5) == "5"
end

local function GetMonsterUID(guid)
  QuestHelper: Assert(#guid == 18, "guid len " .. guid) -- 64 bits, plus the 0x prefix
  QuestHelper: Assert(guid:sub(1, 2) == "0x", "guid 0x-prefix " .. guid)
  QuestHelper: Assert(guid:sub(5, 5) == "3" or guid:sub(5, 5) == "5", "guid 3-prefix " .. guid)  -- It *shouldn't* be a player or a pet by the time we've gotten here. If so, something's gone wrong.
  return guid:sub(9, 18)  -- here's our actual identifier
end

local function GetMonsterType(guid)
  QuestHelper: Assert(#guid == 18, "guid len " .. guid) -- 64 bits, plus the 0x prefix
  QuestHelper: Assert(guid:sub(1, 2) == "0x", "guid 0x-prefix " .. guid)
  QuestHelper: Assert(guid:sub(5, 5) == "3" or guid:sub(5, 5) == "5", "guid 3-prefix " .. guid)  -- It *shouldn't* be a player or a pet by the time we've gotten here. If so, something's gone wrong.
  if GetBuildInfo():sub(1, 3) == "3.2" then
    return tonumber(guid:sub(9, 12), 16)  -- here's our actual identifier
  else
    return tonumber(guid:sub(7, 10), 16)  -- 3.3 and in the future, including 0.3.0
  end
end

local function GetItemType(link, vague)
  if not link then return nil end
  return tonumber(string.match(link, "|Hitem:(%d+):"))  -- not anchored to the name, which can contain brackets of its own
end
  
local function GetQuestType(link)
  return tonumber(string.match(link, "|Hquest:(%d+):[%d-]+|h")), tonumber(string.match(link, "|Hquest:%d+:([%d-]+)|h"))
end

function QH_Collect_Util_Init(_, API)
  API.Utility_IsMonsterGUID = IsMonsterGUID
  API.Utility_GetMonsterUID = GetMonsterUID
  API.Utility_GetMonsterType = GetMonsterType
  API.Utility_GetItemType = GetItemType
  API.Utility_GetQuestType = GetQuestType
end
