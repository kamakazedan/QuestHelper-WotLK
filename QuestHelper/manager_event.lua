QuestHelper_File["manager_event.lua"] = "1.4.1"
QuestHelper_Loadtime["manager_event.lua"] = GetTime()

-- zorba why does this file exist, are you a terrible person? you are a terrible person aren't you
-- yep, I'm a terrible person

-- File exists to centralize all the event hooks in one place. QH should never (rarely) eat CPU without going through this file. As a nice side effect, I can use this to measure when QH is using CPU. yaaaaay

local next_started = false

local time_used = 0

local EventRegistrar = {}

local OnUpdate_Keyed = {}

local qh_event_frame = CreateFrame("Frame")

-- One listener raising an error used to abort the whole dispatch loop it was called from, so every listener after it silently never ran (and for the per-frame loop that included the routing thread). QH_SafeCall runs a function, hands any error to the normal error handler, and lets the caller carry on. Returns true if the function finished.
local reported_errors = {}
local reported_error_count = 0

local function ReportError(err)
  local msg = tostring(err)
  local now = GetTime()
  
  -- Something that fails every frame shouldn't bury the client in identical reports.
  if reported_errors[msg] and reported_errors[msg] > now then return err end
  if not reported_errors[msg] then
    if reported_error_count >= 50 then reported_errors, reported_error_count = {}, 0 end
    reported_error_count = reported_error_count + 1
  end
  reported_errors[msg] = now + 30
  
  local handler = geterrorhandler()
  if handler then handler(msg) end
  return err
end

-- xpcall can't take arguments in Lua 5.1. We park the common short cases in upvalues, which keeps the stack trace without making garbage on every call.
local call_func, call_argc, call_a, call_b, call_c

local function CallParked()
  local func, argc, a, b, c = call_func, call_argc, call_a, call_b, call_c  -- read these before calling, since func may well end up back in here
  if argc == 0 then return func() end
  if argc == 1 then return func(a) end
  if argc == 2 then return func(a, b) end
  return func(a, b, c)
end

function QH_SafeCall(func, ...)
  local argc = select("#", ...)
  if argc <= 3 then
    call_func, call_argc, call_a, call_b, call_c = func, argc, ...
    return (xpcall(CallParked, ReportError))
  end
  
  local ok, err = pcall(func, ...)
  if not ok then ReportError(err) end
  return ok
end

function QH_Hook_NotMyFault(func, ...)
  return func(...)
end

local function wraptime(ident, func, ...)
  if QuestHelper then QuestHelper: Assert(ident) end
  local st, qhh_nmf
  local qhh_adj = 0
  if qh_loud_and_annoying then
    qhh_nmf = QH_Hook_NotMyFault
    QH_Hook_NotMyFault = function(func, ...)
      local zst = GetTime()
      --print("a", GetTime())
      return (function(...)
        --print("c", GetTime(), GetTime() - zst, qhh_adj)
        qhh_adj = qhh_adj + (GetTime() - zst)
        --print(qhh_adj)
        return ...
      end)(func(...))
    end
    st = GetTime()
  end
  QH_SafeCall(func, ...)
  if qh_loud_and_annoying then
    if GetTime() - st - qhh_adj > 0.0025 then
      QuestHelper: TextOut(string.format("Took way too long, %4f, at %s (adjusted by %4f)", (GetTime() - st - qhh_adj) * 1000, ident, qhh_adj * 1000))
    end
    QH_Hook_NotMyFault = qhh_nmf
  end
end

local function OnEvent(_, event, ...)
  if not next_started then next_started, time_used = true, 0 end
  
  if not qh_hackery_eventless and EventRegistrar[event] then 
    local tstart = GetTime()
    for _, v in pairs(EventRegistrar[event]) do
      wraptime(v.id, v.func, ...)
    end
    time_used = time_used + (GetTime() - tstart)
  end
end

qh_event_frame:UnregisterAllEvents()
qh_event_frame:RegisterAllEvents() -- I wonder what the performance penalty of this actually is
qh_event_frame:SetScript("OnEvent", OnEvent)

function QH_Event(event, func, identifier)
  QuestHelper: Assert(func)
  if type(event) == "table" then
    for _, v in ipairs(event) do
      QH_Event(v, func, identifier)
    end
  else
    if not identifier then identifier = "(unknown event " .. event .. ")" end
    if not EventRegistrar[event] then
      --qh_event_frame:RegisterEvent(event)
      EventRegistrar[event] = {}
    end
    table.insert(EventRegistrar[event], {func = func, id = identifier})
  end
end

local tls = GetTime()

-- I'm just putting this here so I can stop rewriting it

--[[
Try "/script qh_hackery_no_work = true". See if that fixes things.

Whether it does or not, log out, log back in, then do "/qh hackery_event_timing = true". Wait a few seconds, then take a screenshot. Post that here.
]]

local last_frame = GetTime()
local time_per_frame = 0.01 -- Assume 100fps so we don't fuck with people's framerate

local OnUpdate = {}
local OnUpdateHigh = {}

-- Adding a new key to a table while pairs() is walking it is undefined behaviour in Lua, and handlers in the loop below do exactly that (the tracker hooks new rows from inside its own update). Those additions wait here until the walk is over.
local walking_onupdate = false
local OnUpdate_deferred = {}

local function OnUpdateTrigger(_, ...)
  if not QuestHelper then return end
  
  if not next_started then next_started, time_used = true, 0 end
  
  do
    local tstart = GetTime()
    for _, v in pairs(OnUpdateHigh) do
      wraptime(v.id, v.func, ...)
    end
    
    walking_onupdate = true
    for _, v in pairs(OnUpdate) do
      if v.func then wraptime(v.id, v.func, ...) end
    end
    walking_onupdate = false
    
    for k, v in pairs(OnUpdate_deferred) do
      OnUpdate[k] = v
      OnUpdate_deferred[k] = nil
    end
    time_used = time_used + (GetTime() - tstart)
  end
  
  local tframe = GetTime()
  local tplf = math.max(tframe - last_frame, 0)  -- GetTime can step backwards on some systems
  tplf = math.min(time_per_frame + 0.1, tplf)
  local tplf_weight = tplf * 20
  time_per_frame = (time_per_frame * (1 / (tplf_weight + 0.0005)) + tplf) / (1 + 1 / (tplf_weight + 0.0005))
  
  -- This was an assert. A bad value never recovers by itself, so the assert then fired every frame, forever.
  if not (time_per_frame > 0 and time_per_frame < 10000) then time_per_frame = 0.01 end
  
  local verbose = false
  if qh_hackery_event_timing and tls < GetTime() - 1 then
    tls = GetTime()
    print(string.format("Avg TPF %f, current TPLF %f, time_used %f, this adjustment %f, bonus time %f", time_per_frame, tplf, time_used, time_per_frame - tplf - time_used, math.min(time_per_frame - tplf, (time_per_frame - tplf) * 0.8, 0.05)))
    verbose = true
  end
  if not qh_hackery_no_work then
    QH_SafeCall(QH_Timeslice_Work, time_used, time_per_frame, math.min(time_per_frame - tplf, (time_per_frame - tplf) * 0.8, 0.05), verbose)
  end
  last_frame = GetTime()
  
  next_started = false
end

function QH_OnUpdate(func, identifier)
  if not identifier then identifier = "(unknown onupdate)" end
  table.insert(OnUpdate, {func = func, id = identifier})
end

function QH_OnUpdate_High(func, identifier)
  if not identifier then identifier = "(unknown high-onupdate)" end
  table.insert(OnUpdateHigh, {func = func, id = identifier})
end

qh_event_frame:SetScript("OnUpdate", OnUpdateTrigger)


function QH_Hook(target, hookname, func, identifier)
  if not identifier then identifier = string.format("(unknown hook %s/%s)", hookname, tostring(target)) end
  if hookname == "OnUpdate" then
    if not func then
      OnUpdate[target] = nil
      OnUpdate_deferred[target] = nil
    else
      local entry = {func = function (...) func(target, ...) end, id = identifier}
      if walking_onupdate and OnUpdate[target] == nil then
        OnUpdate_deferred[target] = entry
      else
        OnUpdate[target] = entry
      end
    end
  else
    if not func then
      target:SetScript(hookname, nil)
    else
      target:SetScript(hookname, function (...) wraptime(identifier, func, ...) end)
    end
  end
end
