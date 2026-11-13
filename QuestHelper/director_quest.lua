QuestHelper_File["director_quest.lua"] = "1.4.1"
QuestHelper_Loadtime["director_quest.lua"] = GetTime()

local debug_output = false
if QuestHelper_File["director_quest.lua"] == "Development Version" then debug_output = true end

--[[

Little bit of explanation here.

The db layer dumps things out in DB format. This isn't immediately usable for our routing engine. We convert this to an intermediate "metaobjective" format that the routing engine can use, as well as copying anything that needs to be copied. This also allows us to modify our metaobjective tables as we see fit, rather than doing nasty stuff to keep the original objectives intact.

It's worth mentioning that, completely accidentally, everything it requests from the DB is deallocated rapidly - it doesn't keep any references to the original DB objects around. This is unintentional, but kind of neat. It's not worth preserving, but it doesn't really have to be "fixed" either.

]]

local function copy(tab)
  local tt = {}
  for _, v in ipairs(tab) do
    table.insert(tt, v)
  end
  return tt
end

local function copy_without_last(tab)
  local tt = {}
  for _, v in ipairs(tab) do
    table.insert(tt, v)
  end
  table.remove(tt)
  return tt
end

local function AppendObjlinks(target, source, tooltips, icon, last_name, map_lines, tooltip_lines, seen)
  if not seen then seen = {} end
  if not map_lines then map_lines = {} end
  if not tooltip_lines then tooltip_lines = {} end
  
  if seen[source] then return end  -- a loop in the database, nothing more we can get out of this branch
  
  seen[source] = true
  if source.loc then
    if target then
      for m, v in ipairs(source.loc) do
        QuestHelper: Assert(target)
        QuestHelper: Assert(QuestHelper_ParentLookup)
        QuestHelper: Assert(QuestHelper_ParentLookup[v.p], v.p)
        table.insert(target, {loc = {x = v.x, y = v.y, c = QuestHelper_ParentLookup[v.p], p = v.p}, path_desc = copy(map_lines), icon_id = icon or 6})
      end
    end
    
    target = nil  -- if we have a "source" as well, then we want to plow through it for tooltip data, but we don't want to add targets for it
  end
  
  for _, v in ipairs(source) do
    local dbgi = DB_GetItem(v.sourcetype, v.sourceid, true, true)
    
    if dbgi then  -- the database can point at things it doesn't contain
      local licon
      
      --print(v.sourcetype, v.sourceid, v.type)
      
      if v.sourcetype == "monster" then
        table.insert(map_lines, QHFormat("OBJECTIVE_SLAY", dbgi.name or QHText("OBJECTIVE_UNKNOWN_MONSTER")))
        table.insert(tooltip_lines, 1, QHFormat("TOOLTIP_SLAY", source.name or "nothing"))
        licon = 1
      elseif v.sourcetype == "item" then
        table.insert(map_lines, QHFormat("OBJECTIVE_LOOT", dbgi.name or QHText("OBJECTIVE_ITEM_UNKNOWN")))
        table.insert(tooltip_lines, 1, QHFormat("TOOLTIP_LOOT", source.name or "nothing"))
        licon = 2
      elseif v.sourcetype == "object" then
        table.insert(map_lines, QHFormat("OBJECTIVE_OPEN", dbgi.name or QHText("OBJECTIVE_ITEM_UNKNOWN")))
        table.insert(tooltip_lines, 1, QHFormat("TOOLTIP_OPEN", source.name or "nothing"))
        licon = 2
      else
        table.insert(map_lines, string.format("unknown %s (%s/%s)", tostring(dbgi.name), tostring(v.sourcetype), tostring(v.sourceid)))
        table.insert(tooltip_lines, 1, string.format("unknown %s (%s/%s)", tostring(last_name), tostring(v.sourcetype), tostring(v.sourceid)))
        licon = 3
      end
      
      tooltips[string.format("%s@@%s", v.sourcetype, v.sourceid)] = copy_without_last(tooltip_lines)
      
      AppendObjlinks(target, dbgi, tooltips, icon or licon, source.name, map_lines, tooltip_lines, seen)
      table.remove(tooltip_lines, 1)
      table.remove(map_lines)
      
      DB_ReleaseItem(dbgi)
    end
  end

  seen[source] = false
end


local function horribledupe(from)
  if not from then return nil end
  
  local rv = {}
  for k, v in pairs(from) do
    if k == "__owner" then
    elseif type(v) == "table" then
      rv[k] = horribledupe(v)
    else
      rv[k] = v
    end
  end
  return rv
end

 
local quest_list = setmetatable({}, {__mode="k"})

local QuestCriteriaWarningBroadcast

-- Builds the routing data for objective number i of a quest.
local function BuildQuestCriteria(ite, q, questid, i)
  local ttx = {}
  --QuestHelper:TextOut(string.format("critty %d %d", k, c.loc and #c.loc or -1))
  
  ttx.tooltip_canned = {}
  
  if q and q.criteria and q.criteria[i] then
    --print("Appending criteria", questid, i)
    AppendObjlinks(ttx, q.criteria[i], ttx.tooltip_canned)
    --print("Done")
    
    if debug_output and q.criteria[i].loc and #q.criteria[i] > 0 then
      QuestHelper:TextOut(string.format("Wackyquest %d/%d", questid, i))
    end
    
    ttx.solid = horribledupe(q.criteria[i].solid)
  end
  
  if #ttx == 0 then
    table.insert(ttx, {loc = {x = 5000, y = 5000, c = 0, p = 2}, icon_id = 7, type_quest_unknown = true, map_desc = {"Unknown"}})  -- this is Ashenvale, for no particularly good reason
    ttx.type_quest_unknown = true
  end
  
  for idx, v in ipairs(ttx) do
    v.desc = string.format("Criteria %d", i)
    v.why = ite
    v.cluster = ttx
    v.type_quest = ite.type_quest
    v.tracker_order = i
  end
  
  for k, v in pairs(ttx.tooltip_canned) do
    ttx.tooltip_canned[k] = {ttx.tooltip_canned[k], ttx} -- we're gonna be handing out this table to other modules, so this isn't as dumb as it looks
  end
  
  ite[i] = ttx
end

local function GetQuestMetaobjective(questid, lbcount)
  if not quest_list[questid] then
    local q = DB_GetItem("quest", questid, true, true)
    
    if not lbcount then
      QuestHelper: TextOut("Missing lbcount, guessing wildly")
      if q and q.criteria then
        lbcount = 0
        for k, v in ipairs(q.criteria) do
          lbcount = math.max(lbcount, k)
        end
      else
        lbcount = 0 -- heh
      end
    end
    
    -- just doublechecking here
    if not QuestCriteriaWarningBroadcast and q and q.criteria then for k, v in pairs(q.criteria) do
      if type(k) == "number" and k > lbcount then
        --QuestHelper:TextOut(string.format("Too many stored objectives for this quest, please report on the Questhelper homepage (%s %s %s)", questid, lbcount, k))  -- we're just going to hide this for now
        QuestHelper_ErrorCatcher_ExplicitError(false, string.format("Too many stored objectives (%s %s %s)", questid, lbcount, k))
        QuestCriteriaWarningBroadcast = true
      end
    end end
    
    local ite = {type_quest = {__backlink = ite}} -- we don't want to mutate the existing quest data. backlink exists only for nasty GC reasons
    ite.desc = string.format("Quest %s", q and q.name or "(unknown)")  -- this gets changed later anyway
    
    for i = 1, lbcount do
      BuildQuestCriteria(ite, q, questid, i)
    end
    ite.criteria_built = lbcount
    
    do
      local ttx = {type_quest_finish = true}
      --QuestHelper:TextOut(string.format("finny %d", q.finish.loc and #q.finish.loc or -1))
      if q and q.finish and q.finish.loc then
        ttx.solid = horribledupe(q.finish.solid)
        for m, v in ipairs(q.finish.loc) do
          --print(v.rc, v.rz)
          --print(QuestHelper_IndexLookup[v.rc])
          --print(QuestHelper_IndexLookup[v.rc][v.rz])
          table.insert(ttx, {desc = "Turn in quest", why = ite, loc = {x = v.x, y = v.y, c = QuestHelper_ParentLookup[v.p], p = v.p}, tracker_hidden = true, cluster = ttx, icon_id = 7, type_quest = ite.type_quest})
        end
      end
      
      if #ttx == 0 then
        table.insert(ttx, {desc = "Turn in quest", why = ite, loc = {x = 5000, y = 5000, c = 0, p = 2}, tracker_hidden = true, cluster = ttx, icon_id = 7, type_quest = ite.type_quest, type_quest_unknown = true})  -- this is Ashenvale, for no particularly good reason
        ttx.type_quest_unknown = true
      end
      
      ite.finish = ttx
    end
    
    quest_list[questid] = ite
    
    if q then DB_ReleaseItem(q) end
  elseif lbcount and lbcount > quest_list[questid].criteria_built then
    -- The client can report fewer objectives than a quest really has while its data is still on the way from the server, and we remember what we built the first time. This used to fail an assert the moment the real objectives showed up.
    local ite = quest_list[questid]
    local q = DB_GetItem("quest", questid, true, true)
    
    for i = ite.criteria_built + 1, lbcount do
      BuildQuestCriteria(ite, q, questid, i)
    end
    ite.criteria_built = lbcount
    
    if q then DB_ReleaseItem(q) end
  end
  
  return quest_list[questid]
end


local function GetQuestType(link)
  return tonumber(string.match(link, "|Hquest:(%d+):[%d-]+|h")), tonumber(string.match(link, "|Hquest:%d+:([%d-]+)|h"))  -- not anchored to the title, which can contain brackets of its own
end

local update = true
local function UpdateTrigger()
  update = true
end

-- It's possible that things end up garbage-collected and we end up with different tables than we expect. This is something that the entire system is kind of prone to. The solution's pretty easy - we just have to store them ourselves while we're using them.
local active_db = {}

local objective_parse_table = {
  item = function (txt) return QuestHelper:convertPattern(QUEST_OBJECTS_FOUND)(txt) end,
  object = function (txt) return QuestHelper:convertPattern(QUEST_OBJECTS_FOUND)(txt) end,  -- why does this even exist
  monster = function (txt) return QuestHelper:convertPattern(QUEST_MONSTERS_KILLED)(txt) end,
  event = function (txt, done) return txt, (done and 1 or 0), 1 end, -- It appears that events are only used for things which can only happen once.
  reputation = function (txt) return QuestHelper:convertPattern(QUEST_FACTION_NEEDED)(txt) end, -- :ughh:
  player = function (txt) return QuestHelper:convertPattern(QUEST_MONSTERS_KILLED)(txt) end, -- We're using monsters here in the hopes that it follows the same pattern. I'd rather not try to find the exact right version of "player" in the locale files, though PLAYER might be it.
}

local function objective_parse(typ, txt, done)
  txt = txt or ""
  
  local pt, target, have, need = typ
  if objective_parse_table[typ] then  -- objective types we've never heard of fall through to the generic parsing below
    target, have, need = objective_parse_table[typ](txt, done)
  end
  
  if not target then
    -- well, that didn't work
    target, have, need = string.match(txt, "^%s*(.-)%s*:%s*(.-)%s*/%s*(.-)%s*$")
    pt = "fallback"
    --QuestHelper:TextOut(string.format("%s rebecomes %s/%s/%s", tostring(title), tostring(target), tostring(have), tostring(need)))
  end
  
  if not target then
    target, have, need = string.match(txt, "^%s*(.-)%s*$"), (done and 1 or 0), 1
    --QuestHelper:TextOut(string.format("%s rerebecomes %s/%s/%s", tostring(title), tostring(target), tostring(have), tostring(need)))
  end
  
  QuestHelper: Assert(target) -- This will fail repeatedly. Come on. We all know it.
  QuestHelper: Assert(have)
  QuestHelper: Assert(need) -- As will these.
  
  if tonumber(have) then have = tonumber(have) end
  if tonumber(need) then need = tonumber(need) end

  return pt, target, have, need
end

local function clamp(v)
  if v < 0 then return 0 elseif v > 255 then return 255 else return v end
end

local function colorlerp(position, r1, g1, b1, r2, g2, b2)
  local antip = 1 - position
  return string.format("|cff%02x%02x%02x", clamp((r1 * antip + r2 * position) * 255), clamp((g1 * antip + g2 * position) * 255), clamp((b1 * antip + b2 * position) * 255))
end

-- We're just gonna do the same thing QH originally did - red->yellow->green.
local function difficulty_color(position)
  if position < 0 then position = 0 end
  if position > 1 then position = 1 end
  return (position < 0.5) and colorlerp(position * 2, 1, 0, 0, 1, 1, 0) or colorlerp(position * 2 - 1, 1, 1, 0, 0, 1, 0)
end

local function MakeQuestTitle(title, level)
  if type(level) ~= "number" then return title end  -- from a party member, could be anything
  
  local plevel = QuestHelper:PlayerLevel()
  local grayd
  
  if plevel >= 60 then
    grayd = 9
  elseif plevel >= 40 then
    grayd = plevel / 5 + 1
  else
    grayd = plevel / 10 + 5
  end
  
  local isgray = (plevel - floor(grayd) >= level)
  
  local ccode = isgray and "|cffb0b0b0" or difficulty_color(1 - ((level - plevel) / grayd + 1) / 2)
  local qlevel = string.format("[%d] ", level)
  
  local ret = title
  if QuestHelper_Pref.track_level then ret = qlevel .. ret end
  if QuestHelper_Pref.track_qcolour then ret = ccode .. ret end
  
  return ret
end

local function MakeQuestObjectiveTitle(progress, target)
  if not progress or not target then return nil end
  
  local player = UnitName("player")
  
  local pt, pd = 0, 0
  for _, v in pairs(progress) do
    pt = pt + 1
    if v[3] == 1 then pd = pd + 1 end
  end

  local ccode
  local status
  local party
  local party_show = false
  local party_compact = false
  
  -- Only one person's on this and it isn't us, so their actual numbers say more than "Party 0/1" would.
  local shown = progress[player]
  if not shown and pt == 1 then
    local _, only = next(progress)
    shown = only
  end
  
  if shown then
    local have, need = tonumber(shown[1]), tonumber(shown[2])
    
    ccode = difficulty_color(shown[3])
    
    if have and need then
      if need > 1 then
        status = string.format("%d/%d", have, need)
        party_compact = true
      end
    else
      status = string.format("%s/%s", shown[1], shown[2])
      party_compact = true
    end
    
    if pt > 1 then party_show = true end
  elseif pt == 0 then
    ccode = difficulty_color(1) -- probably just in the process of being removed from the tracker
    status = "Complete"
  else
    ccode = difficulty_color(pd / pt)
    
    party_show = true
  end
  
  if party_show then
    if party_compact then
      party = string.format("(P: %d/%d)", pd, pt)
    else
      party = string.format("Party %d/%d", pd, pt)
    end
  end
  
  if QuestHelper_Pref.track_ocolour then
    target = ccode .. target
  end
  
  if status or party then
    target = target .. ":"
  end
  
  if status then
    target = target .. " " .. status
  end
  
  if party then
    target = target .. " " .. party
  end
  
  return target
end

local function Clicky(index)
  ShowUIPanel(QuestLogFrame)
  QuestLog_SetSelection(index)
  QuestLog_Update()
end

local dontknow  = {
  name = "director_quest_unknown_objective",
  no_exception = true,
  no_disable = true,
  friendly_reason = QHText("UNKNOWN_OBJ"),
}

-- InsertedItem[item] = {"list", "of", "reasons"}
local InsertedItems = {}
local TooltipType = {}
local Unknowning = {}
local Unknowned = {}
local in_pass = nil

local function SetTooltip(item, typ)
  --print("stt", item, typ, item.tooltip_defer_questobjective)
  if TooltipType[item] == typ and typ ~= "defer" and not item.tooltip_defer_questobjective_last then return end
  if TooltipType[item] == "defer" and typ == "defer" and (not item.tooltip_defer_questobjective_last or item.tooltip_defer_questobjective_last == item.tooltip_defer_questobjective) then return end -- sigh
  
  if TooltipType[item] == "canned" then
    QuestHelper: Assert(item.tooltip_canned)
    QH_Tooltip_Canned_Remove(item.tooltip_canned)
  elseif TooltipType[item] == "defer" then
    QuestHelper: Assert(item.tooltip_defer_questname_last)
    --print("remove", item.tooltip_defer_questname_last, item.tooltip_defer_questobjective_last, item.tooltip_defer_questobjective)
    if item.tooltip_defer_questobjective_last then
      QH_Tooltip_Defer_Remove(item.tooltip_defer_questname_last, item.tooltip_defer_questobjective_last, item.tooltip_defer_token_last)
    else
      QH_Tooltip_Defer_Remove(item.tooltip_defer_questname_last, item.tooltip_defer_questobjective, item.tooltip_defer_token_last)
    end
  elseif TooltipType[item] == nil then
  else
    QuestHelper: Assert(false)
  end
  
  item.tooltip_defer_questobjective_last = nil
  item.tooltip_defer_questname_last = nil  -- if it was anything, it is not now
  item.tooltip_defer_token_last = nil
  
  if typ == "canned" then
    QuestHelper: Assert(item.tooltip_canned)
    QH_Tooltip_Canned_Add(item.tooltip_canned)
  elseif typ == "defer" then
    QuestHelper: Assert(not not item.tooltip_defer_questobjective == not item.type_quest_finish)  -- hmmm
    --print("add", item.tooltip_defer_questname, item.tooltip_defer_questobjective)
    QuestHelper: Assert(item.tooltip_defer_questname)
    item.tooltip_defer_token_last = {{}, item}
    QH_Tooltip_Defer_Add(item.tooltip_defer_questname, item.tooltip_defer_questobjective, item.tooltip_defer_token_last)
    item.tooltip_defer_questname_last = item.tooltip_defer_questname
    item.tooltip_defer_questobjective_last = item.tooltip_defer_questobjective
  elseif typ == nil then
  else
    QuestHelper: Assert(false)
  end
  TooltipType[item] = typ
end

-- Gets out of an insertion pass that didn't make it to the end. Anything it didn't reach is still in InsertedItems, and the next pass sorts that out. Without this, the next pass would refuse to start, and so would every pass after it.
local function AbortInsertionPass()
  in_pass = nil
  QH_Timeslice_PopUnyieldable()
end

local own_name  -- the name our own quest log is filed under

-- A quest has left our log. It may well carry on as a party member's quest, but nothing about our log applies to it any more.
local function ForgetQuestFromLog(quest)
  QH_Tracker_Unpin(quest.finish[1], true)
  for i = 1, quest.criteria_built or 0 do
    if quest[i] and quest[i][1] then QH_Tracker_Unpin(quest[i][1], true) end
  end
  quest.type_quest.index, quest.tracker_clicked, quest.tracker_zone, quest.tracker_in_collapsed, quest.tracker_minimised_under = nil, nil, nil, nil, nil
end

-- Who a quest belongs to if it isn't in our own log: the names of the party members who have it. Nil when it's ours, even if they have it too.
function QH_Quest_SharedBy(quest)
  local users = InsertedItems[quest.finish]
  if not users or users[own_name] then return nil end
  
  local names = QuestHelper:CreateTable("quest owners")
  for name in pairs(users) do table.insert(names, name) end
  table.sort(names)
  local owners = (#names > 0) and table.concat(names, ", ") or nil
  QuestHelper:ReleaseTable(names)
  return owners
end

local function StartInsertionPass(id)
  if in_pass then AbortInsertionPass() end
  in_pass = id
  QH_Timeslice_PushUnyieldable()
  for k, v in pairs(InsertedItems) do
    v[id] = nil
    
    if k.progress then
      k.progress[id] = nil
      local desc = MakeQuestObjectiveTitle(k.progress, k.target)
      for _, v in ipairs(k) do
        v.tracker_desc = desc or "(no description available)"
      end
    end
    
    -- if these are needed to remove, they'll be stored in last, and this way they'll be obliterated if the user doesn't have that actual quest
    if id == UnitName("player") then
      k.tooltip_defer_questname = nil
      k.tooltip_defer_questobjective = nil
    end
  end
end
local function RefreshItem(id, item, required)
  --if not required and math.random() < 0.2 then return false end -- ha ha bzzzzt
  
  QuestHelper: Assert(in_pass == id)
  local added = false
  if not InsertedItems[item] then
    QH_Route_ClusterAdd(item)
    --QH_Route_SetClusterPriority(item, math.random(5))
    added = true
    InsertedItems[item] = {}
  end
  InsertedItems[item][id] = true
  
  if item.tooltip_defer_questname then
    SetTooltip(item, "defer")
  elseif item.tooltip_canned then
    SetTooltip(item, "canned")
  else
    SetTooltip(item, nil)
  end
  
  if item.type_quest_unknown then table.insert(Unknowning, item) end
  
  local desc = MakeQuestObjectiveTitle(item.progress, item.target)
  for _, v in ipairs(item) do
    v.tracker_desc = desc or "(no description available)"
  end
  
  return added
end
local function EndInsertionPass(id)
  QuestHelper: Assert(in_pass == id)
  local rem = QuestHelper:CreateTable("ip rem")
  for k, v in pairs(InsertedItems) do
    local has = false
    for _, _ in pairs(v) do
      has = true
      break
    end
    if not has then
      QH_Tracker_Unpin(k[1], true)
      QH_Route_ClusterRemove(k)
      rem[k] = true
      
      QH_SafeCall(SetTooltip, k, nil)
    end
    
    if id == own_name and not v[id] and k[1] and k[1].why and k[1].why.finish == k then
      ForgetQuestFromLog(k[1].why)  -- every quest we hold has its turn-in filed under our name, so this one's gone
    end
  end
  
  QH_SafeCall(QH_Tracker_Rescan)
  
  for k, _ in pairs(rem) do
    InsertedItems[k] = nil
  end
  QuestHelper:ReleaseTable(rem)
  
  -- this is all so we don't spam the system with multiple ignores, since that currently causes an early routing exit
  for k in pairs(Unknowned) do
    Unknowned[k] = false
  end
  for _, v in ipairs(Unknowning) do
    if Unknowned[v] == nil then
      QH_Route_IgnoreCluster(v, dontknow)
    end
    Unknowned[v] = true
  end
  while table.remove(Unknowning) do end
  local need_rescan = false
  local new_unknowned = QuestHelper:CreateTable("unk")
  for k, v in pairs(Unknowned) do
    if v then new_unknowned[k] = true end
  end
  QuestHelper:ReleaseTable(Unknowned)
  Unknowned = new_unknowned
  
  QH_Timeslice_PopUnyieldable()
  in_pass = nil
  
  --QH_Tooltip_Defer_Dump()
end

function QuestProcessor(user_id, db, title, level, group, variety, groupsize, watched, complete, lbcount, timed)
  db.desc = title
  db.tracker_desc = MakeQuestTitle(title, level)
  
  db.type_quest.objectives = lbcount
  db.type_quest.level = level
  db.type_quest.done = (complete == 1)
  db.type_quest.variety = variety
  db.type_quest.groupsize = groupsize
  db.type_quest.title = title
  
  local turnin
  local turnin_new
  
  -- This is our "quest turnin" objective, which is currently being handled separately for no particularly good reason.
  if db.finish and #db.finish > 0 then
    for _, v in ipairs(db.finish) do
      v.map_highlight = (complete == 1)
    end
    
    turnin = db.finish
    --print("turnin:", turnin.tooltip_defer_questname)
    if RefreshItem(user_id, turnin, true) then
      turnin_new = true
      for k, v in ipairs(turnin) do
        v.tracker_clicked = function () if db.tracker_clicked then db.tracker_clicked() end end  -- looked up when clicked, since the quest's log index moves around
        
        v.map_desc = {QHFormat("OBJECTIVE_REASON_TURNIN", title)}
      end
    end
    if watched ~= "(ignore)" then QH_Tracker_SetPin(db.finish[1], watched, true) end
  end
  
  -- These are the individual criteria of the quest. Remember that each criteria can be represented by multiple routing objectives.
  for i = 1, lbcount do
    if db[i] then
      local pt, pd, have, need = objective_parse(db[i].temp_typ, db[i].temp_desc, db[i].temp_done)
      local dline
      if pt == "item" or pt == "object" then
        dline = QHFormat("OBJECTIVE_REASON", QHText("ACQUIRE_VERB"), pd, title)
      elseif pt == "monster" then
        dline = QHFormat("OBJECTIVE_REASON", QHText("SLAY_VERB"), pd, title)
      else
        dline = QHFormat("OBJECTIVE_REASON_FALLBACK", pd, title)
      end
      
      if not db[i].progress then
        db[i].progress = {}
      end
      
      if type(have) == "number" and type(need) == "number" then
        db[i].progress[db[i].temp_person] = {have, need, need > 0 and have / need or 0}
      else
        db[i].progress[db[i].temp_person] = {have, need, db[i].temp_done and 1 or 0}  -- it's only used for the coloring anyway
      end
      
      local _, target = objective_parse(db[i].temp_typ, db[i].temp_desc)
      db[i].target = target
      
      db[i].desc = QHFormat("TOOLTIP_QUEST", title)
      
      for k, v in ipairs(db[i]) do
        v.desc = db[i].temp_desc
        v.tracker_clicked = db.tracker_clicked
        
        v.progress = db[i].progress
        
        if v.path_desc then
          v.map_desc = copy(v.path_desc)
          v.map_desc[1] = dline
        else
          v.map_desc = {dline}
        end
      end
      
      -- This is the snatch of code that actually adds it to routing.
      if not db[i].temp_done and #db[i] > 0 then
        if RefreshItem(user_id, db[i]) then
          if turnin then QH_Route_ClusterRequires(turnin, db[i]) end
        end
        if watched ~= "(ignore)" then QH_Tracker_SetPin(db[i][1], watched, true) end
      end
      
      db[i].temp_desc, db[i].temp_typ, db[i].temp_done = nil, nil, nil
    end
  end
  
  if turnin_new and timed then
    QH_Route_SetClusterPriority(turnin, -1)
  end
end

function SerItem(item)
  local rtx
  if type(item) == "boolean" then
    rtx = "b" .. (item and "t" or "f")
  elseif type(item) == "number" then
    rtx = "n" .. tostring(item)
  elseif type(item) == "string" then
    rtx = "s" .. item:gsub("\\", "\\\\"):gsub(":", "\\;")
  elseif type(item) == "nil" then
    rtx = "0"
  else
    print(type(item), item)
    QuestHelper: Assert()
  end
  return rtx
end

function DeSerItem(item)
  local t = item:sub(1, 1)
  local d = item:sub(2)
  if t == "b" then
    return (d == "t")
  elseif t == "n" then
    return tonumber(d)
  elseif t == "s" then
    return d:gsub("\\;", ":"):gsub("\\\\", "\\")
  elseif t == "0" then
    return nil
  else
    QuestHelper: Assert()
  end
end

local function Serialize(...)
  local sx
  for i = 1, select("#", ...) do
    if sx then sx = sx .. ":" else sx = "" end
    sx = sx .. SerItem(select(i, ...))
  end
  QuestHelper: Assert(sx)
  return sx
end

local function SAM(msg, chattype, target)
  --QuestHelper: TextOut(string.format("%s/%s: %s", chattype, tostring(target), msg))
  
  local thresh = 245
  local msgsize = 240
  if #msg > thresh then
    for i = 1, #msg, msgsize do
      local prefx = "x:"
      if i == 1 then prefx = "v:" elseif i + msgsize > #msg then prefx = "X:" end
      SAM(prefx .. msg:sub(i, i + msgsize - 1), chattype, target)
    end
  else
    ChatThrottleLib:SendAddonMessage("BULK", "QHpr", msg, chattype, target, "QHpr")
  end
end

-- sigh.
function is_uncached(typ, txt, done)
  if not txt then return true end
  if txt == "" then return true end
  if txt:match("^ : %d+/%d+$") then return true end
  local _, target = objective_parse(typ, txt, done)
  if target == "" or target == " " then return true end
  return false
end

-- qid, chunk
local current_chunks = {}

-- "log" is a synthetic objective that Blizzard tossed in for god only knows what reason, so we just pretend it doesn't exist
local function GetEffectiveNumQuestLeaderBoards(index)
  local v = GetNumQuestLeaderBoards(index) or 0
  if v ~= 1 then return v end
  if select(2, GetQuestLogLeaderBoard(1, index)) == "log" then return 0 end
  return 1
end

-- What the quest log looks like right now, boiled down to a string. Used to spot changes we weren't told about.
local function DescribeQuestLog()
  local parts = QuestHelper:CreateTable("quest log description")
  
  local index = 1
  while true do
    local title, _, _, _, is_header, is_collapsed, complete = GetQuestLogTitle(index)
    if not title then break end
    
    table.insert(parts, title)
    if is_header then
      table.insert(parts, tostring(is_collapsed))  -- minimising the last heading doesn't move anything, so this is the only sign of it
    else
      table.insert(parts, tostring(complete))
      for i = 1, (GetNumQuestLeaderBoards(index) or 0) do
        local desc, _, done = GetQuestLogLeaderBoard(i, index)
        table.insert(parts, tostring(desc))
        table.insert(parts, tostring(done))
      end
    end
    
    index = index + 1
  end
  
  local description = table.concat(parts, "\001")
  QuestHelper:ReleaseTable(parts)
  return description
end

local last_log_description
local scan_player, scan_chunks
local scan_memory, scan_ids, scan_lone_collapsed

-- Which quest log heading each of this character's quests sits under, by quest ID. Saved, so it's still known after a reload with the heading minimised.
local function HeadingMemory(player)
  local all = rawget(QuestHelper_Pref, "quest_headings")
  if type(all) ~= "table" then
    all = {}
    QuestHelper_Pref.quest_headings = all
  end
  local key = (GetRealmName() or "") .. "/" .. player
  if type(all[key]) ~= "table" then all[key] = {} end
  return all[key]
end

-- Handles one quest from the log. "zone" is the quest log heading it's sitting under, and "hidden" means that heading is minimised.
local function ScanQuestLogEntry(index, zone, hidden)
  local title, level, variety, groupsize, _, _, complete = GetQuestLogTitle(index)
  
  title = title:match("^%[[^%]]*%] (.*)") or title  -- some addons put the level in front of the name
  
  local qlink = GetQuestLink(index)
  if not qlink then return end -- If we don't have a quest link, it's not really a quest
  
  local id = GetQuestType(qlink)
  if not id then return end -- If we don't have a *valid* quest link, give up
  
  local player = scan_player
  local lbcount = GetEffectiveNumQuestLeaderBoards(index)
  local db = GetQuestMetaobjective(id, lbcount) -- This generates the above-mentioned metaobjective, including doing the database lookup.
  
  QuestHelper: Assert(db)
  
  local watched = IsQuestWatched(index)
  
  -- The section in here, in other words, is: we have a metaobjective (which may be a new one, or may not be), and we're trying to attach things to our routing engine. Now is where the real work begins! (many conditionals deep)
  local lindex = index
  db.tracker_clicked = function () Clicky(lindex) end
  db.tracker_zone = zone
  db.tracker_in_collapsed = hidden or nil
  
  -- The game won't say which heading a quest under a minimised heading belongs to, so it's remembered from whenever that heading was open.
  if hidden then
    if not scan_memory[id] and scan_lone_collapsed then scan_memory[id] = scan_lone_collapsed end
    db.tracker_minimised_under = scan_memory[id]
  else
    db.tracker_minimised_under = nil
    if zone then scan_memory[id] = zone end
  end
  scan_ids[id] = true
  
  db.type_quest.index = index
  
  local timidx = 1
  while true do
    local timer = GetQuestIndexForTimer(timidx)
    if not timer then timidx = nil break end
    if timer == index then break end
    timidx = timidx + 1
  end
  local timed = not not timidx
  
  --print(id, title, level, groupsize, variety, groupsize, complete, timed)
  local chunk = "q:" .. Serialize(id, title, level, groupsize, variety, groupsize, complete, timed)
  for i = 1, lbcount do
    db[i].temp_desc, db[i].temp_typ, db[i].temp_done = GetQuestLogLeaderBoard(i, index)
    if not db[i].temp_desc or db[i].temp_desc == "" then
      db[i].temp_desc = "(loading...)"  -- the client hasn't got this one yet. CheckForMissedUpdates will pick up the real text when it arrives.
    end
    db[i].temp_person = player
    
    db[i].tooltip_defer_questname = title
    db[i].tooltip_defer_questobjective = db[i].temp_desc -- yoink
    
    chunk = chunk .. ":" .. Serialize(db[i].temp_desc, db[i].temp_typ, db[i].temp_done)
  end
  
  db.finish.tooltip_defer_questname = title -- we're using this as our fallback right now
  
  scan_chunks[id] = chunk
  
  QuestProcessor(player, db, title, level, groupsize, variety, groupsize, watched, complete, lbcount, timed)
end

-- The quest log's headings as of the last scan, top to bottom.
local quest_log_headings, quest_log_heading_by_name = {}, {}

function QH_QuestLog_Headings()
  return quest_log_headings
end

-- {name =, index =, collapsed =}, or nil if the quest log has no heading by that name.
function QH_QuestLog_Heading(name)
  return quest_log_heading_by_name[name]
end

-- Minimises or opens a quest log heading, the same as clicking it in the quest log. Returns false if there's no heading by that name.
function QH_QuestLog_ToggleHeading(name)
  local visible = GetNumQuestLogEntries() or 0
  for index = 1, visible do
    local title, _, _, _, is_header, is_collapsed = GetQuestLogTitle(index)
    if is_header and title == name then
      -- Found fresh every time, because handed anything that isn't a heading, these two act on every heading at once.
      if is_collapsed then ExpandQuestHeader(index) else CollapseQuestHeader(index) end
      if QuestLogFrame and QuestLogFrame:IsShown() then QuestLog_Update() end
      QH_UpdateQuests(true)
      return true
    end
  end
  return false
end

local function ScanQuestLog(player)
  own_name = player
  StartInsertionPass(player)
  scan_memory, scan_ids, scan_lone_collapsed = HeadingMemory(player), {}, nil
  
  scan_player, scan_chunks = player, {}
  local failed = false
  
  -- The log lists each heading followed by its quests, except that quests under a minimised heading come after everything else, with no headings, so there's no telling which heading they belong to.
  local visible = GetNumQuestLogEntries()
  if not visible or visible < 1 then visible = math.huge end
  local headings, heading_by_name = {}, {}
  
  -- This begins the main update loop that loops through all of the quests
  local zone, zone_collapsed
  local index = 1
  while true do
    local title, _, _, _, is_header, is_collapsed = GetQuestLogTitle(index)
    if not title then break end
    
    if is_header then
      zone, zone_collapsed = title, not not is_collapsed
      if index <= visible and not heading_by_name[title] then
        heading_by_name[title] = {name = title, index = index, collapsed = zone_collapsed}
        table.insert(headings, heading_by_name[title])
      end
    else
      local hidden = index > visible or zone_collapsed
      if hidden and scan_lone_collapsed == nil then
        -- With only one minimised heading, everything hidden has to be under it.
        scan_lone_collapsed = false
        for _, heading in ipairs(headings) do
          if heading.collapsed then
            if scan_lone_collapsed then scan_lone_collapsed = false break end
            scan_lone_collapsed = heading.name
          end
        end
      end
      if not QH_SafeCall(ScanQuestLogEntry, index, (not hidden) and zone or nil, hidden) then
        failed = true  -- one quest going wrong is no reason to stop updating all the others
      end
    end
    
    index = index + 1
  end
  
  quest_log_headings, quest_log_heading_by_name = headings, heading_by_name
  
  if not failed then
    for id in pairs(scan_memory) do
      if not scan_ids[id] then scan_memory[id] = nil end  -- no longer in the log
    end
  end
  
  EndInsertionPass(player)
  
  QH_Route_Filter_Rescan(nil, true)  -- 'cause filters may also change, but let's not bother getting too excited about it
  
  local next_chunks = scan_chunks
  
  if not QuestHelper_Pref.solo and QuestHelper_Pref.share then
    for k, v in pairs(next_chunks) do
      if current_chunks[k] ~= v then
        SAM(v, "PARTY")
      end
    end
    
    for k, v in pairs(current_chunks) do
      if not next_chunks[k] then
        SAM(string.format("q:n%d", k), "PARTY")
      end
    end
  end
  
  current_chunks = next_chunks
  
  last_log_description = (not failed) and DescribeQuestLog() or ""  -- if something failed, CheckForMissedUpdates will see a difference and try again shortly
  --update = false
end

-- Here's the core update function
function QH_UpdateQuests(force)
  if not DB_Ready() then return end
  if in_pass then return end  -- already busy
  
  local player = UnitName("player")
  if not player or player == UNKNOWNOBJECT then return end -- bzzt, try again later
  
  QH_Timeslice_PushUnyieldable()

  if update or force then  -- Sometimes (usually) we don't actually update
    QH_SafeCall(ScanQuestLog, player)
    if in_pass then AbortInsertionPass() end  -- whatever went wrong, the next update has to be able to run
  end
  
  QH_Timeslice_PopUnyieldable()
end

-- comm_packets[user][qid] = data
local comm_packets = {}

local function RefreshUserCommPacket(user, dat)
  local id, title, level, group, variety, groupsize, complete, timed = dat[1], dat[2], dat[3], dat[4], dat[5], dat[6], dat[7], dat[8]
  local objstart = 9
  
  if type(id) ~= "number" or type(title) ~= "string" or type(level) ~= "number" then return end  -- the routing filters rely on these
  
  local obj = {}
  while true do
    if dat[#obj * 3 + objstart] == nil and dat[#obj * 3 + objstart + 1] == nil and dat[#obj * 3 + objstart + 2] == nil then break end
    table.insert(obj, {dat[#obj * 3 + objstart], dat[#obj * 3 + objstart + 1], dat[#obj * 3 + objstart + 2]})
  end
  
  local lbcount = #obj
  local db = GetQuestMetaobjective(id, lbcount) -- This generates the above-mentioned metaobjective, including doing the database lookup.

  QuestHelper: Assert(db)
  
  for i = 1, lbcount do
    db[i].temp_desc, db[i].temp_typ, db[i].temp_done, db[i].temp_person = obj[i][1], obj[i][2], obj[i][3], user
  end
  
  QuestProcessor(user, db, title, level, group, variety, groupsize, "(ignore)", complete, lbcount, false)
end

local function RefreshUserCommsPass(user)
  StartInsertionPass(user)
  
  if comm_packets[user] then for _, dat in pairs(comm_packets[user]) do
    QH_SafeCall(RefreshUserCommPacket, user, dat)  -- a garbled packet from someone else's client shouldn't affect us
  end end

  EndInsertionPass(user)
  
  QH_Route_Filter_Rescan()  -- 'cause filters may also change
end

local function RefreshUserComms(user)
  QH_SafeCall(RefreshUserCommsPass, user)
  if in_pass then AbortInsertionPass() end
end

function QH_InsertCommPacket(user, data)
  local q, chunk = data:match("([^:]+):(.*)")
  if q ~= "q" then return end
  
  local dat = {}
  local idx = 1
  for item in chunk:gmatch("([^:]+)") do
    dat[idx] = DeSerItem(item)
    idx = idx + 1
  end
  
  if dat[1] == nil then return end
  
  if not comm_packets[user] then comm_packets[user] = {} end
  if idx == 2 then
    comm_packets[user][dat[1]] = nil
  else
    comm_packets[user][dat[1]] = dat
  end
  
  -- refresh the comms
  RefreshUserComms(user)
end

local function QH_DumpCommUser(user)
  comm_packets[user] = nil
  RefreshUserComms(user)
end

QH_Event("PLAYER_ENTERING_WORLD", UpdateTrigger)
QH_Event("UNIT_QUEST_LOG_CHANGED", UpdateTrigger)
QH_Event("QUEST_LOG_UPDATE", QH_UpdateQuests)

-- We don't return anything here, but I don't think that's actually an issue - those functions don't return anything anyway. Someday I'll regret writing this. Delay because of beql which is a bitch.
QH_AddNotifier(GetTime() + 5, function ()
  local aqw_orig = AddQuestWatch
  AddQuestWatch = function(...)
    aqw_orig(...)
    QH_UpdateQuests(true)
  end
  local rqw_orig = RemoveQuestWatch
  RemoveQuestWatch = function(...)
    rqw_orig(...)
    QH_UpdateQuests(true)
  end
end)

-- We seem to end up out of sync sometimes. Why? I'm not sure. Maybe my current events aren't reliable. So every few seconds we compare the quest log with what we last saw, and only do a real update if it's different - a real update makes the router start over.
local function CheckForMissedUpdates()
  QH_AddNotifier(GetTime() + 3, CheckForMissedUpdates)  -- before anything else, so that nothing below can end the cycle
  
  if last_log_description and DescribeQuestLog() ~= last_log_description then
    QH_UpdateQuests(true)
  end
end
QH_AddNotifier(GetTime() + 30, CheckForMissedUpdates)

local old_playerlist = {}

function QH_Questcomm_Sync()
  if not (not QuestHelper_Pref.solo and QuestHelper_Pref.share) then
    old_playerlist = {}
    return
  end
  
  local playerlist = {}
  --[[if GetNumRaidMembers() > 0 then
    for i = 1, 40 do
      local liv = UnitName(string.format("raid%d", i))
      if liv then playerlist[liv] = true end
    end
  elseif]] if GetNumPartyMembers() > 0 then
    -- we is in a party
    for i = 1, 4 do
      local targ = string.format("party%d", i)
      local liv, relm = UnitName(targ)
      if liv and not relm and liv ~= UNKNOWNOBJECT and UnitIsConnected(targ) then playerlist[liv] = true end
    end
  end
  local me = UnitName("player")
  if me then playerlist[me] = nil end
  
  local additions = {}
  for k, v in pairs(playerlist) do
    if not old_playerlist[k] then
      --print("new player:", k)
      table.insert(additions, k)
    end
  end
  
  local removals = {}
  for k, v in pairs(old_playerlist) do
    if not playerlist[k] then
      --print("lost player:", k)
      table.insert(removals, k)
    end
  end
  
  old_playerlist = playerlist
  
  for _, v in ipairs(removals) do
    QH_DumpCommUser(v)
  end
  
  if #additions == 0 then return end
  
  if #additions == 1 then
    SAM("syn:2", "WHISPER", additions[1])
  else
    SAM("syn:2", "PARTY")
  end
end

local aku = {}

local newer_reported = false
local older_reported = false
function QH_Questcomm_Msg(data, from)
  if data:match("syn:0") then
    QH_DumpCommUser(from)
    return
  end
  if QuestHelper_Pref.solo then return end
  
  --print("received", from, data)
  do
    local cont = true
    
    local key, value = data:match("(.):(.*)")
    if key == "v" then
      aku[from] = value
    elseif key == "x" then
      if aku[from] then
        aku[from] = aku[from] .. value
      end
    elseif key == "X" then
      if aku[from] then
        aku[from] = aku[from] .. value
        data = aku[from]
        aku[from] = nil
        cont = true
      end
    else
      cont = true
    end
    
    if not cont then return end
  end
  
  --print("packet received", from, data)
  if data:match("syn:.*") then
    local synv = data:match("syn:([0-9]*)")
    if synv then synv = tonumber(synv) end
    if synv and synv ~= 2 then
      if synv > 2 and not newer_reported then
        QuestHelper:TextOut(QHFormat("PEER_NEWER", from))
        newer_reported = true
      elseif synv < 2 and not older_reported then
        QuestHelper:TextOut(QHFormat("PEER_OLDER", from))
        older_reported = true
      end
    end
    
    if synv and synv >= 2 then
      SAM("hello:2", "WHISPER", from)
    end
  elseif data == "hello:2" or data == "retrieve:2" then
    if data == "hello:2" then SAM("retrieve:2", "WHISPER", from) end  -- requests their info as well, needed to deal with UI reloading/logon/logoff properly
    
    for k, v in pairs(current_chunks) do
      SAM(v, "WHISPER", from)
    end
  else
    if old_playerlist[from] then
      QH_InsertCommPacket(from, data)
    end
  end
end

function QuestHelper:SetShare(flag)
  if flag then
    QH_Questcomm_Sync()
  else
    SAM("syn:0", "PARTY")
    local cpb = comm_packets
    comm_packets = {}
    for k in pairs(cpb) do RefreshUserComms(k) end
  end
end
