QuestHelper_File["dodads.lua"] = "1.4.1"
QuestHelper_Loadtime["dodads.lua"] = GetTime()

local ofs = 0.000723339 * (GetScreenHeight()/GetScreenWidth() + 1/3) * 70.4;
local radius = ofs / 1.166666666666667;
local Minimap = _G.Minimap

-- These conversions are nasty, and this entire section needs a serious cleanup.
local function convertLocation(p)
  return QuestHelper.Astrolabe:FromAbsoluteContinentPosition(p.c, p.x, p.y)
end

-- also gives the continent the spot is on, Astrolabe's
local function convertLocationToScreen(p, c, z)
  local pc, _, px, py = convertLocation(p)
  local ox, oy = QuestHelper.Astrolabe:TranslateWorldMapPosition(pc, 0, px, py, c, z)
  --QuestHelper:TextOut(string.format("%f/%f/%f to %f/%f/%f to %f/%f %f/%f", p.c, p.x, p.y, pc, px, py, c, z, ox, oy))
  return ox, oy, pc
end

local function convertRawToScreen(tc, x, y, c, z)
  local rc, _, rx, ry = QuestHelper.Astrolabe:FromAbsoluteContinentPosition(tc, x, y)
  return QuestHelper.Astrolabe:TranslateWorldMapPosition(rc, 0, rx, ry, c, z)
end

-- Everything QuestHelper puts on the world map is drawn on map_overlay, which lies over the map (WorldMapButton), and
-- cropped by the scroll frame holding it. On the game's own map the crop is the map, so nothing spills onto the
-- window round it. A map addon that zooms (BetterMaps, Magnify and the like) puts the map into a scroll frame of its
-- own, and may show more than the map in it: BetterMaps' free camera shows the land round a zone's map. There the
-- crop is that scroll frame, the part of the map in view, so the route and the icons go on past the map's edges over
-- the land shown, and map_overlay is kept on the map by scrolling the crop as far as the map addon scrolls the map.
local scrolf = CreateFrame("SCROLLFRAME", nil, WorldMapButton)
scrolf:SetFrameLevel(WorldMapButton:GetFrameLevel()+1)
scrolf:SetAllPoints()
scrolf:SetFrameStrata("FULLSCREEN")

QuestHelper.map_overlay = CreateFrame("FRAME", nil, scrolf)
scrolf:SetScrollChild(QuestHelper.map_overlay)
QuestHelper.map_overlay:SetAllPoints()

QuestHelper.map_overlay_uncropped = scrolf

local view_frame  -- the map addon's scroll frame, once the crop is its

-- the map addon's scroll frame holding the map, if there is one
local function ZoomScrollFrame()
  local view = WorldMapDetailFrame and WorldMapDetailFrame:GetParent()
  if view and view.GetObjectType and view:GetObjectType() == "ScrollFrame" and view.GetScrollChild
      and view:GetScrollChild() == WorldMapDetailFrame then
    return view
  end
end

-- The crop scrolled as far as the map addon's scroll frame. The two share their corner, so what each holds has its own
-- corner at the same spot then: map_overlay's on the map's. How far is in the units of what is scrolled.
local function FollowView()
  local ratio = WorldMapDetailFrame:GetEffectiveScale() / QuestHelper.map_overlay:GetEffectiveScale()
  scrolf:SetHorizontalScroll(view_frame:GetHorizontalScroll() * ratio)
  scrolf:SetVerticalScroll(view_frame:GetVerticalScroll() * ratio)
end

-- Once a map addon holds the map in a scroll frame, the crop covers that scroll frame and follows its scrolling, and
-- map_overlay keeps to the map: anchored to it, as big as it, and scrolled to it (a scroll frame places what it holds by
-- how far it is scrolled, and may go by its size rather than its anchors).
local function FitOverlay()
  local overlay = QuestHelper.map_overlay
  local w, h = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
  if not view_frame then
    local view = ZoomScrollFrame()
    if not view then return end
    view_frame = view
    scrolf:ClearAllPoints()
    scrolf:SetAllPoints(view)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(WorldMapButton)
    overlay:SetWidth(w)
    overlay:SetHeight(h)
    hooksecurefunc(view, "SetHorizontalScroll", FollowView)
    hooksecurefunc(view, "SetVerticalScroll", FollowView)
    FollowView()
  end
  if overlay:GetWidth() ~= w then overlay:SetWidth(w) end
  if overlay:GetHeight() ~= h then overlay:SetHeight(h) end
end

-- Whether things on a continent (Astrolabe's) show past the edges of the map shown, of continent c: on the land a map
-- addon shows round a zone's or a continent's map, the map's own continent's. Not on the game's own map, and not things
-- on another continent, which Astrolabe puts where they are on the map of the whole world: out at sea for the land shown.
local function OnLandShown(continent, c)
  return view_frame ~= nil and c ~= nil and c > 0 and continent == c
end

-- whether something at a spot of the map shown (0-1 across and down) shows there: on the map, or on the land round it
local function ShowsAt(continent, x, y, c)
  if not (x and y) then return false end
  return (x > 0 and x <= 1 and y > 0 and y <= 1) or OnLandShown(continent, c)
end

-- An icon put on the map shown at a spot of the world (Astrolabe's continent, zone and 0-1 position on that zone), or
-- hidden where it doesn't show. On the game's own map this is Astrolabe's PlaceIconOnWorldMap, which shows only what is
-- on the map; with a map addon's view an icon also shows on the land round the map.
local function PlaceIcon(icon, continent, zone, x, y)
  FitOverlay()
  local astrolabe, overlay = QuestHelper.Astrolabe, QuestHelper.map_overlay
  if not view_frame then
    return astrolabe:PlaceIconOnWorldMap(overlay, icon, continent, zone, x, y)
  end
  local c, z = astrolabe:GetCurrentVirtualMapCZ()
  local nx, ny
  if continent and x and y then
    nx, ny = astrolabe:TranslateWorldMapPosition(continent, zone, x, y, c, z)
  end
  if ShowsAt(continent, nx, ny, c) then
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", overlay, "TOPLEFT", nx * overlay:GetWidth(), -ny * overlay:GetHeight())
    icon:Show()
  else
    icon:Hide()
  end
  return nx, ny
end

local poi = {}
local poi_changed = false

-- The route's dots: twice as close together as 1.4.1 drew them, and green on the way to the objective you are being
-- taken to (through any flight masters, portals or zone borders on the way), the faint black of 1.4.1 after it.
local DOT_SPACING = .0125
local DOT_NEXT = { 0.25, 1, 0.25, 0.8 }
local DOT_LATER = { 0, 0, 0, 0.35 }

local poi_dodads = {}

function QH_POI_Reset()
  while poi[1] do
    QuestHelper:ReleaseTable(table.remove(poi))
  end
  poi_changed = true
end
function QH_POI_Add(p, x, y, d)
  local tab = QuestHelper:CreateTable("dodads_poi")
  tab.p = p
  tab.x = x
  tab.y = y
  tab.desc = d
  table.insert(poi, tab)
  poi_changed = true
end


local walker_loc

-- How far a map addon has zoomed the world map in, and the part of the map in view (from 0 to 1 across and down, past
-- that where the view goes past the map's edges). Zooming map addons (BetterMaps, Magnify and the like) put
-- WorldMapDetailFrame in a scroll frame and scale it in there, up, or down where BetterMaps' free camera shows a zone's
-- map smaller than the window; with the game's own map nothing is zoomed and all of it is in view.
local MIN_ZOOM = 0.01
local function MapView()
  local overlay = QuestHelper.map_overlay
  local view = ZoomScrollFrame()
  if not view then return 1, 0, 0, 1, 1 end
  local oscale, vscale = overlay:GetEffectiveScale(), view:GetEffectiveScale()
  local ol, ot, ow, oh = overlay:GetLeft(), overlay:GetTop(), overlay:GetWidth(), overlay:GetHeight()
  local vl, vt, vw, vh = view:GetLeft(), view:GetTop(), view:GetWidth(), view:GetHeight()
  if not (oscale and vscale and ol and ot and ow and oh and vl and vt and vw and vh) or oscale <= 0 or vscale <= 0 or ow <= 0 or oh <= 0 then
    return 1, 0, 0, 1, 1
  end
  ow, oh = ow * oscale, oh * oscale
  local left, top = (vl * vscale - ol * oscale) / ow, (ot * oscale - vt * vscale) / oh
  return math.max(oscale / vscale, MIN_ZOOM), left, top, left + vw * vscale / ow, top + vh * vscale / oh
end

-- one edge of a rectangle cutting down how far along a line is inside it (Liang-Barsky)
local function ClipToEdge(p, q, t0, t1)
  if p == 0 then
    if q < 0 then return end
  elseif p < 0 then
    local r = q / p
    if r > t1 then return end
    if r > t0 then t0 = r end
  else
    local r = q / p
    if r < t0 then return end
    if r < t1 then t1 = r end
  end
  return t0, t1
end

-- the part of the line from (x1, y1) to (x2, y2) inside a rectangle, as how far along the line it starts and ends
local function LineInView(x1, y1, x2, y2, left, top, right, bottom)
  local dx, dy = x2 - x1, y2 - y1
  local t0, t1 = ClipToEdge(-dx, x1 - left, 0, 1)
  if t0 then t0, t1 = ClipToEdge(dx, right - x1, t0, t1) end
  if t0 then t0, t1 = ClipToEdge(-dy, y1 - top, t0, t1) end
  if t0 then t0, t1 = ClipToEdge(dy, bottom - y1, t0, t1) end
  return t0, t1
end

-- Objective areas: outlines this thick on screen (in the map's own units when it isn't zoomed), rounded off at least
-- once and until they have about this many corners.
local AREA_LINE = 2
local AREA_POINTS = 256

-- An area's outline with its corners rounded off (Chaikin's corner cutting: each pass cuts every corner down to two,
-- a quarter of the way along each side), repeated points dropped first.
local function SmoothOutline(xs, ys)
  local px, py = {}, {}
  for i = 1, #xs do
    local j = #px
    if j == 0 or math.abs(xs[i] - px[j]) > 1e-9 or math.abs(ys[i] - py[j]) > 1e-9 then
      px[j + 1], py[j + 1] = xs[i], ys[i]
    end
  end
  while #px > 1 and math.abs(px[#px] - px[1]) <= 1e-9 and math.abs(py[#py] - py[1]) <= 1e-9 do
    px[#px], py[#py] = nil, nil
  end
  if #px < 3 then return px, py end
  local passes = 0
  while passes < 3 and (passes == 0 or #px * 2 <= AREA_POINTS) do
    local nx, ny, n = {}, {}, #px
    for i = 1, n do
      local j = i % n + 1
      nx[2 * i - 1], ny[2 * i - 1] = px[i] * 0.75 + px[j] * 0.25, py[i] * 0.75 + py[j] * 0.25
      nx[2 * i], ny[2 * i] = px[i] * 0.25 + px[j] * 0.75, py[i] * 0.25 + py[j] * 0.75
    end
    px, py, passes = nx, ny, passes + 1
  end
  return px, py
end

local function InTriangle(px, py, ax, ay, bx, by, cx, cy)  -- edges count as in
  local d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by)
  local d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy)
  local d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay)
  return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
end

-- Triangles covering an outline, as indexes into it three at a time: a fan if it's convex, else ears cut off one at
-- a time. Nil if it can't be done (an outline that crosses itself).
local function TriangulateOutline(xs, ys)
  local n = #xs
  if n < 3 then return end
  local area = 0
  for i = 1, n do
    local j = i % n + 1
    area = area + xs[i] * ys[j] - xs[j] * ys[i]
  end
  if math.abs(area) < 1e-12 then return end
  local sign = area > 0 and 1 or -1
  local function turn(a, b, c)  -- above 0 where a, b, c turn the way the outline goes round
    return ((xs[b] - xs[a]) * (ys[c] - ys[b]) - (ys[b] - ys[a]) * (xs[c] - xs[b])) * sign
  end
  local out = {}
  local convex = true
  for i = 1, n do
    if turn(i, i % n + 1, (i + 1) % n + 1) < 0 then convex = false break end
  end
  if convex then
    for i = 2, n - 1 do
      out[#out + 1], out[#out + 2], out[#out + 3] = 1, i, i + 1
    end
    return out
  end
  local idx = {}
  for i = 1, n do idx[i] = i end
  local k, misses = 1, 0
  while #idx > 3 do
    local m = #idx
    if k > m then k = 1 end
    local a, b, c = idx[(k - 2) % m + 1], idx[k], idx[k % m + 1]
    local ear = turn(a, b, c) > 0
    if ear then
      for t = 1, m do
        local p = idx[t]
        if p ~= a and p ~= b and p ~= c and InTriangle(xs[p], ys[p], xs[a], ys[a], xs[b], ys[b], xs[c], ys[c]) then
          ear = false
          break
        end
      end
    end
    if ear then
      out[#out + 1], out[#out + 2], out[#out + 3] = a, b, c
      table.remove(idx, k)
      misses = 0
    else
      k, misses = k + 1, misses + 1
      if misses > m then return end  -- all the way round without an ear
    end
  end
  out[#out + 1], out[#out + 2], out[#out + 3] = idx[1], idx[2], idx[3]
  return out
end

-- outlines redrawn as thick as the zoom needs
local function Rethicken(lines, zoom)
  if not lines then return end
  for _, line in ipairs(lines) do
    if line.ax then line:SetLine(line.ax, line.ay, line.bx, line.by, AREA_LINE / zoom) end
  end
end

QH_AreaShape = {SmoothOutline = SmoothOutline, TriangulateOutline = TriangulateOutline}  -- for the tests

function QuestHelper:CreateWorldMapWalker()
  if not self.Astrolabe or not QuestHelper then return end
  QuestHelper: Assert(self == QuestHelper)
  QuestHelper: Assert(self.Astrolabe)
  
  local walker = CreateFrame("Button", nil, QuestHelper.map_overlay)
  walker_loc = walker
  walker:SetWidth(0)
  walker:SetHeight(0)
  walker:SetPoint("CENTER", QuestHelper.map_overlay, "TOPLEFT", 0, 0)
  walker:Show()
  
  walker.phase = 0.0
  walker.dots = {}
  walker.points = {}
  walker.origin = {}
  walker.frame = self
  walker.map_dodads = {}
  walker.used_map_dodads = 0
  
  function walker:OnUpdate(elapsed)
    if poi_changed then self:RouteChanged() end   -- bzzzzt
    FitOverlay()
    
    local out = 0
    
    if QuestHelper_Pref.show_ants then
      local points = self.points
      
      self.phase = self.phase + elapsed * 0.66
      while self.phase > 1 do self.phase = self.phase - 1 end
      
      local w, h = QuestHelper.map_overlay:GetWidth(), -QuestHelper.map_overlay:GetHeight()
      
      local c, z = QuestHelper.Astrolabe:GetCurrentVirtualMapCZ()
      
      local last_x, last_y = self.frame.Astrolabe:TranslateWorldMapPosition(self.frame.c, self.frame.z, self.frame.x, self.frame.y, c, z)
      local remainder = self.phase
      
      -- On a map a map addon has zoomed, the dots are as far apart on screen as on the whole map, and only the part in
      -- view gets any (a dot's width round it, so none goes missing at its edge). Where the map addon shows the land
      -- round the map, the route goes on over it past the map's edges; a stretch to or from another continent (a boat,
      -- a portal) stops at the map's edges, as everything does on the game's own map.
      local zoom, view_l, view_t, view_r, view_b = MapView()
      local spacing = DOT_SPACING / zoom
      view_l, view_t, view_r, view_b = view_l - spacing, view_t - spacing, view_r + spacing, view_b + spacing
      local map_l, map_t, map_r, map_b = math.max(view_l, 0), math.max(view_t, 0), math.min(view_r, 1), math.min(view_b, 1)
      local last_continent = self.frame.c
      
      for i, pos in ipairs(points) do
        local x1, y1, x2, y2 = last_x, last_y, pos[1], pos[2]
        local on_land = OnLandShown(last_continent, c) and OnLandShown(pos.continent, c)
        last_x, last_y, last_continent = x2, y2, pos.continent
        local next_leg = i <= (self.next_leg or 0)
        
        if x1 and y1 and x2 and y2 then
          local len = math.sqrt((x1-x2)*(x1-x2)*16/9+(y1-y2)*(y1-y2))
          
          if len > 0.0001 then
            local interval = spacing/len
            local start = remainder*interval
            local p, last = start, -1
            local first, upto
            if on_land then
              first, upto = LineInView(x1, y1, x2, y2, view_l, view_t, view_r, view_b)
            else
              first, upto = LineInView(x1, y1, x2, y2, map_l, map_t, map_r, map_b)
            end
            if first then
              last = upto
              -- counted from the start of the line, so the dots don't slide along it as the view moves
              if p < first then p = p + math.ceil((first - p)/interval)*interval end
            end
            
            while p < 1 and p <= last do
              out = out + 1
              local dot = self.dots[out]
              if not dot then
                dot = QuestHelper:CreateDotTexture(self)
                dot:SetDrawLayer("BACKGROUND")
                self.dots[out] = dot
              elseif not dot:IsShown() then
                dot:Show()
              end
              
              -- coloured only when it changes, so a map addon that restyles the dots sees each change once
              if dot.on_next_leg ~= next_leg then
                dot.on_next_leg = next_leg
                dot:SetVertexColor(unpack(next_leg and DOT_NEXT or DOT_LATER))
              end
              
              dot:ClearAllPoints()
              dot:SetPoint("CENTER", QuestHelper.map_overlay, "TOPLEFT", x1*w*(1-p)+x2*w*p, y1*h*(1-p)+y2*h*p)
              
              p = p + interval
            end
            
            -- the next line carries on from where this one's dots would have ended, whatever part of it was in view
            remainder = (start + math.max(math.ceil((1 - start)/interval), 0)*interval - 1)/interval
          end
        end
      end
    end
    
    -- dots not needed now are hidden, not given back: they are wanted again as the route or the view moves, and a map
    -- addon that restyles the dots keeps its style on them
    for i = out + 1, #self.dots do
      local dot = self.dots[i]
      if dot:IsShown() then dot:Hide() end
    end
  end
  
  function walker:RouteChanged(route)
    if route then self.route = route end -- we cache it so we can refer to it later when the world map changes
    if not self.route then return end
    
    local dbgstr = string.format("%s %s %s %s", tostring(self), tostring(self.frame), tostring(QuestHelper), tostring(QuestHelper and QuestHelper.Astrolabe))
    QuestHelper: Assert(self.frame == QuestHelper, dbgstr)
    QuestHelper: Assert(QuestHelper.Astrolabe, dbgstr)
    
    if self.next_item then
      self.next_item:MarkAsNext(false)
      self.next_item = nil
    end
    
    if self.frame.Astrolabe.WorldMapVisible then
      FitOverlay()
      local points = self.points
      local cur = self.frame.pos
      
      while #points > 0 do self.frame:ReleaseTable(table.remove(points)) end
      
      local c, z = QuestHelper.Astrolabe:GetCurrentVirtualMapCZ()
      
      -- how many of the stretches between the points lead to the next objective: the waypoints on the way (the ignored
      -- points) and the stretch to the objective itself
      self.next_leg = 0
      for i = 2, #self.route do
        if not self.route[i].ignore then
          self.next_leg = i - 1
          break
        end
      end
      
      for i, obj in ipairs(self.route) do
        --QuestHelper:TextOut(string.format("%s", tostring(obj)))
        
        --[[
        local t = QuestHelper:CreateTable()
        t[1], t[2] = convertLocationToScreen(obj.loc, c, z)
        
        table.insert(list, t)]]
        
        -- We're ignoring travel time for now.
        --[[
        travel_time = travel_time + 60
        obj.travel_time = travel_time]]
        if i > 1 then -- skip the start location
          local t = self.frame:CreateTable()
          t[1], t[2], t.continent = convertLocationToScreen(obj.loc, c, z)
          
          table.insert(points, t)
          
          --if lotsup then print(obj.ignore, obj.loc.x, obj.loc.y, obj.loc.c) end
        end
        --QuestHelper:TextOut(string.format("%s/%s/%s to %s/%s", tostring(obj.c), tostring(obj.x), tostring(obj.y), tostring(t[1]), tostring(t[2])))
      end
      --lotsup = false
      
      local cur_dodad = 1
      for i = 2, #self.route do -- 2 because we're skipping the player
        if not self.route[i].ignore or qh_hackery_show_all_map_nodes then
          local dodad = self.map_dodads[cur_dodad]
          if not dodad then
            self.map_dodads[cur_dodad] = self.frame:CreateWorldMapDodad(self.route[i], i == 2)
          else
            self.map_dodads[cur_dodad]:SetObjective(self.route[i], i == 2)
          end
          
          if cur_dodad == 1 then
            self.map_dodads[cur_dodad]:MarkAsNext(true)
            self.next_item = self.map_dodads[cur_dodad]
          end
          cur_dodad = cur_dodad + 1
        end
      end

      if cur_dodad <= self.used_map_dodads then for i = cur_dodad,self.used_map_dodads do
        self.map_dodads[i]:SetObjective(nil, false)
      end end

      self.used_map_dodads = cur_dodad - 1
      
      while #poi > #poi_dodads do
        table.insert(poi_dodads, self.frame:CreateWorldMapMinidad())
      end
      
      for i = 1, #poi do
        poi_dodads[i]:SetPosition(poi[i])
      end
      for i = #poi + 1, #poi_dodads do
        poi_dodads[i]:SetPosition()
      end
    end
  end
  
  QH_Event("WORLD_MAP_UPDATE", function () walker:RouteChanged() end)
  
  QH_Hook(walker, "OnUpdate", walker.OnUpdate)
  
  return walker
end



function QuestHelper:GetOverlapObjectives(obj)
  local w, h = self.map_overlay:GetWidth(), self.map_overlay:GetHeight()
  local c, z = QuestHelper.Astrolabe:GetCurrentVirtualMapCZ()
  
  local list = self.overlap_list
  
  if not list then
    list = {}
    self.overlap_list = list
  else
    while table.remove(list) do end
  end
  
  local cx, cy = GetCursorPosition()
  
  local es = QuestHelper.map_overlay:GetEffectiveScale()
  local ies = 1/es
  
  cx, cy = (cx-self.map_overlay:GetLeft()*es)*ies, (self.map_overlay:GetTop()*es-cy)*ies
  
  local s = 10*QuestHelper_Pref.scale
  
  for i, o in ipairs(walker_loc.route) do
    --QuestHelper: Assert(o, string.format("nil dodads pos issue, o %s", tostring(o)))
    --QuestHelper: Assert(o.pos, string.format("nil dodads pos issue, pos %s", QuestHelper:StringizeTable(o)))
    if not o.ignore or qh_hackery_show_all_map_nodes then
      if o == obj then
        table.insert(list, o)
      else
        local x, y, continent = convertLocationToScreen(o.loc, c, z)
        
        if ShowsAt(continent, x, y, c) then
          x, y = x*w, y*h
          
          if cx >= x-s and cy >= y-s and cx <= x+s and cy <= y+s then
            table.insert(list, o)
          end
        end
      end
    end
  end
  
  table.sort(list, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
  
  return list
end

function QuestHelper:AppendObjectiveProgressToTooltip(o, tooltip, font, depth)
  if o.progress then
    local prog_sort_table = {}
  
    local theme = self:GetColourTheme()
    
    local indent = ("  "):rep(depth or 0)
    
    for user, progress in pairs(o.progress) do
      table.insert(prog_sort_table, user)
    end
    
    table.sort(prog_sort_table, function(a, b)
      if o.progress[a][3] < o.progress[b][3] then
        return true
      elseif o.progress[a][3] == o.progress[b][3] then
        return a < b
      end
      return false
    end)
    
    for i, u in ipairs(prog_sort_table) do
      tooltip:AddDoubleLine(indent..QHFormat("PEER_PROGRESS", u),
                            self:ProgressString(o.progress[u][1].."/"..o.progress[u][2],
                            o.progress[u][3]), unpack(theme.tooltip))
      
      if font then
        local last, name = tooltip:NumLines(), tooltip:GetName()
        local left, right = _G[name.."TextLeft"..last], _G[name.."TextRight"..last]
        
        left:SetFont(font, 13)
        right:SetFont(font, 13)
      end
    end
    
    while table.remove(prog_sort_table) do end
  end
end

function QuestHelper:AppendObjectiveToTooltip(o)
  local theme = self:GetColourTheme()
  
  QuestHelper: Assert(o.map_desc)
  for _, v in ipairs(o.map_desc) do
    self.tooltip:AddLine(v, unpack(theme.tooltip))
    self.tooltip:GetPrevLines():SetFont(self.font.serif, 14)
  end
  
  if o.map_desc_chain then
    self:AppendObjectiveToTooltip(o.map_desc_chain)
  else
    self:AppendObjectiveProgressToTooltip(o, self.tooltip, QuestHelper.font.sans)
    
    if QuestHelper_Pref.travel_time then
      self.tooltip:AddDoubleLine(QHText("TRAVEL_ESTIMATE"), QHFormat("TRAVEL_ESTIMATE_VALUE", o.distance or 0), unpack(theme.tooltip))
      self.tooltip:GetPrevLines():SetFont(self.font.sans, 11)
    end
  end
end

globx = 0.5
globy = 0.5

function QH_Append_NextObjective(menu)
  local obj = QuestHelper.minimap_marker.obj
  if not obj then return end
  
  QuestHelper:AddObjectiveOptionsToMenu(obj, menu)
end

local function rightclick_menu(obj)
  if obj then
    local menu = QuestHelper:CreateMenu()
    local list = QuestHelper:GetOverlapObjectives(obj)
    local item
    
    if #list > 1 then
      QuestHelper:CreateMenuTitle(menu, "Objectives")
      
      for i, o in ipairs(list) do
        local submenu = QuestHelper:CreateMenu()
        item = QuestHelper:CreateMenuItem(menu, o.map_desc[1])
        item:SetSubmenu(submenu)
        item:AddTexture(QuestHelper:CreateIconTexture(item, o.icon_id or 8), true)
        QuestHelper:AddObjectiveOptionsToMenu(o, submenu)
      end
    else
      QuestHelper:CreateMenuTitle(menu, obj.map_desc[1])
      QuestHelper:AddObjectiveOptionsToMenu(obj, menu)
    end
    
    menu:ShowAtCursor()
  end
end

function QuestHelper:CreateWorldMapDodad(objective, nxt)
  local icon = CreateFrame("Button", nil, QuestHelper.map_overlay)
  icon:SetFrameStrata("FULLSCREEN")
  
  function icon:SetTooltip(list)
    QuestHelper.tooltip:SetOwner(self, "ANCHOR_CURSOR")
    QuestHelper.tooltip:ClearLines()
    
    local first = true
    
    for i, o in ipairs(list) do
      if first then
        first = false
      else
        QuestHelper.tooltip:AddLine("|c80ff0000  .  .  .  .  .  .|r")
        QuestHelper.tooltip:GetPrevLines():SetFont(QuestHelper.font.sans, 8)
      end
      
      QuestHelper:AppendObjectiveToTooltip(o)
    end
    
    QuestHelper.tooltip:Show()
  end
  
  function icon:MarkAsNext(nxt)
    self.next = nxt
    
    QH_Hook(self, "OnUpdate", self.OnUpdate)
  end
  
  function icon:SetObjective(objective, nxt)
    self:SetHeight(20*QuestHelper_Pref.scale)
    self:SetWidth(20*QuestHelper_Pref.scale)
    
    if self.dot then
      QuestHelper:ReleaseTexture(self.dot)
      self.dot = nil
    end
    
    if self.bg then
      QuestHelper:ReleaseTexture(self.bg)
      self.bg = nil
    end
    
    if objective then
      self.objective = objective
      
      if nxt then
        self.bg = QuestHelper:CreateIconTexture(self, 13)
      elseif objective.map_highlight then
        self.bg = QuestHelper:CreateIconTexture(self, 14)
      else
        self.bg = QuestHelper:CreateIconTexture(self, 16)
      end
      
      self.dot = QuestHelper:CreateIconTexture(self, objective.icon_id or 8)
      
      self.bg:SetDrawLayer("BACKGROUND")
      self.bg:SetAllPoints()
      self.dot:SetPoint("TOPLEFT", self, "TOPLEFT", 3*QuestHelper_Pref.scale, -3*QuestHelper_Pref.scale)
      self.dot:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -3*QuestHelper_Pref.scale, 3*QuestHelper_Pref.scale)
      
      PlaceIcon(self, convertLocation(objective.loc))
      --QuestHelper.Astrolabe:PlaceIconOnWorldMap(QuestHelper.map_overlay, self, 0, 0, globx, globy)
    else
      self.objective = nil
      self:Hide()
      self.next = false
      self:OnUpdate(0)
    end
  end
  
  local triangle_r, triangle_g, triangle_b = 1.0, 0.3, 0
  local triangle_opacity = 0.6
  
  function icon:CreateTriangles(solid, tritarget, tristartat, linetarget, linestartat, parent)
    local c, z = QuestHelper.Astrolabe:GetCurrentVirtualMapCZ()
    local thickness = AREA_LINE / MapView()
    
    local function maketriangle(ax, ay, bx, by, cx, cy)
      local tri = tritarget[tristartat]
      if not tri then
        tri = CreateTriangle(parent)
        table.insert(tritarget, tri)
      end
      tristartat = tristartat + 1
      
      tri:SetTriangle(ax, ay, bx, by, cx, cy)
      tri:SetVertexColor(0, 0, 0, 0)
      tri:Show()
    end
    
    local function makeline(ax, ay, bx, by)
      local tri = linetarget[linestartat]
      if not tri then
        tri = CreateLine(parent)
        table.insert(linetarget, tri)
      end
      linestartat = linestartat + 1
      
      tri.ax, tri.ay, tri.bx, tri.by = ax, ay, bx, by  -- to be redrawn as the zoom changes
      tri:SetLine(ax, ay, bx, by, thickness)
      tri:SetVertexColor(0, 0, 0, 0)
      tri:Show()
    end
    
    for _, v in ipairs(solid) do
      -- Each piece is triangles fanned out from a corner (more than one fan after a "d"), then after an "l" its
      -- outline. The outline is drawn rounded off, and filled to match; the piece's own triangles are kept for an
      -- outline that can't be filled.
      local adjx, adjy = v[1], v[2]
      local x, y = convertRawToScreen(v.continent, v[1], v[2], c, z)
      --print("matchup", c, v.continent, x, y)
      -- With a map addon's view round a zone's or continent's map, a piece on another continent would show out at sea
      -- (on the game's own map the crop keeps it off the map).
      if view_frame and c and c > 0 and not OnLandShown(v.continent, c) then
        x, y = nil, nil
      end
      if x and y then
        local lx, ly = convertRawToScreen(v.continent, adjx + v[3], adjy + v[4], c, z)
        local linemode, missing = false, not (lx and ly)
        local fans, xs, ys = {}, {}, {}
        
        local lidx = 5
        while lidx <= #v do
          if type(v[lidx]) == "string" then
            if v[lidx] == "d" then
              QuestHelper: Assert(type(lidx) == "number") -- what
              lidx = lidx + 1
              x, y = convertRawToScreen(v.continent, adjx + v[lidx], adjy + v[lidx + 1], c, z)
              lx, ly = convertRawToScreen(v.continent, adjx + v[lidx + 2], adjy + v[lidx + 3], c, z)
              missing = missing or not (x and y and lx and ly)
              lidx = lidx + 4
            elseif v[lidx] == "l" then
              linemode = true
              lidx = lidx + 1
              x, y = convertRawToScreen(v.continent, adjx + v[lidx], adjy + v[lidx + 1], c, z)
              missing = missing or not (x and y)
              table.insert(xs, x or 0)
              table.insert(ys, y or 0)
              lidx = lidx + 2
            else
              QuestHelper: Assert(false)
            end
          else
            local tx, ty = convertRawToScreen(v.continent, adjx + v[lidx], adjy + v[lidx + 1], c, z)
            missing = missing or not (tx and ty)
            if not linemode then
              table.insert(fans, {x, y, lx, ly, tx, ty})
              lx, ly = tx, ty
            else
              table.insert(xs, tx or 0)
              table.insert(ys, ty or 0)
            end
            lidx = lidx + 2
          end
        end
        
        if not missing then
          local sx, sy = SmoothOutline(xs, ys)
          local tris = TriangulateOutline(sx, sy)
          if tris then
            for i = 1, #tris, 3 do
              local a, b, d = tris[i], tris[i + 1], tris[i + 2]
              maketriangle(sx[a], sy[a], sx[b], sy[b], sx[d], sy[d])
            end
          else
            for _, f in ipairs(fans) do maketriangle(unpack(f)) end
          end
          
          if #sx >= 2 then
            for i = 1, #sx do
              local j = i % #sx + 1
              makeline(sx[i], sy[i], sx[j], sy[j])
            end
          end
        end
      end
    end
    
    return tristartat, linestartat
  end
  
  function icon:SetGlow(list)
    local w, h = QuestHelper.map_overlay:GetWidth(), QuestHelper.map_overlay:GetHeight()
    local c, z = QuestHelper.Astrolabe:GetCurrentVirtualMapCZ()
    local zw = QuestHelper.Astrolabe:GetZoneWidth(c, z)
    
    local solids = {}
    
    local gid = 1
    for _, v in ipairs(list) do 
      --print(v.cluster, v.cluster and v.cluster.solid)
      if v.cluster and v.cluster.solid then
        --print("solidified", #v.cluster.solid)
        solids[v.cluster.solid] = true
      else
        local x, y = convertLocationToScreen(v.loc, c, z)
        if x and y then
          if not self.glow_list then
            self.glow_list = QuestHelper:CreateTable()
          end
          local glo = self.glow_list[gid]
          if not glo then
            -- The map's, as the areas are, not the icon's: a map addon that zooms in shrinks the icons to keep them one
            -- size on screen, and a glow belonging to an icon would be pulled towards the map's corner with it.
            glo = QuestHelper:CreateGlowTexture(QuestHelper.map_overlay)
            self.glow_list[gid] = glo
          end
          gid = gid + 1
          
          local size = h / 20 / MapView()  -- one size on screen however far the map's zoomed in, like the icon it's under
          glo:ClearAllPoints()
          glo:SetPoint("CENTER", QuestHelper.map_overlay, "TOPLEFT", x*w, -y*h)
          glo:SetVertexColor(triangle_r, triangle_g, triangle_b, 1)
          glo:SetWidth(size)
          glo:SetHeight(size)
          glo:Show()
        end
      end
    end
    
    local tid = 1
    local lid = 1
    
    for k, _ in pairs(solids) do
      if not self.triangle_list then
        self.triangle_list = QuestHelper:CreateTable()
      end
      if not self.line_list then
        self.line_list = QuestHelper:CreateTable()
      end
      
      tid, lid = self:CreateTriangles(k, self.triangle_list, tid, self.line_list, lid, QuestHelper.map_overlay)
    end
    -- call triangle maker here!
    
    if self.triangle_list then
      while #self.triangle_list >= tid do
        ReleaseTriangle(table.remove(self.triangle_list))
      end
      
      if #self.triangle_list == 0 then
        QuestHelper:ReleaseTable(self.triangle_list)
        self.triangle_list = nil
      end
    end
    
    if self.glow_list then
      while #self.glow_list >= gid do
        QuestHelper:ReleaseTexture(table.remove(self.glow_list))
      end
      
      if #self.glow_list == 0 then
        QuestHelper:ReleaseTable(self.glow_list)
        self.glow_list = nil
      end
    end
    
    if self.line_list then
      while #self.line_list >= lid do
        ReleaseLine(table.remove(self.line_list))
      end
      
      if #self.line_list == 0 then
        QuestHelper:ReleaseTable(self.line_list)
        self.line_list = nil
      end
    end
  end
  
  icon.show_glow = false
  icon.glow_pct = 0.0
  icon.phase = 0.0
  icon.old_count = 0
  
  function icon:OnUpdate(elapsed)
    self.phase = (self.phase + elapsed)%6.283185307179586476925286766559005768394338798750211641949889185
    
    -- outlines as thick on screen however far a map addon zooms in
    local zoom = MapView()
    if zoom ~= self.line_zoom then
      self.line_zoom = zoom
      Rethicken(self.line_list, zoom)
      Rethicken(self.local_line_list, zoom)
    end
    
    if self.next and self.objective and self.objective.cluster.solid and QuestHelper_Pref.zones == "next" then
      
      local c, z = QuestHelper.Astrolabe:GetCurrentVirtualMapCZ()
      if self.tri_c ~= c or self.tri_z ~= z then
        -- not entirely happy with this being here, but, welp
        if not self.local_triangle_list then
          self.local_triangle_list = QuestHelper:CreateTable()
        end
        if not self.local_line_list then
          self.local_line_list = QuestHelper:CreateTable()
        end
        
        local tid, lid = self:CreateTriangles(self.objective.cluster.solid, self.local_triangle_list, 1, self.local_line_list, 1, QuestHelper.map_overlay)
        
        if self.local_triangle_list then
          while #self.local_triangle_list >= tid do
            ReleaseTriangle(table.remove(self.local_triangle_list))
          end
        end
        
        if self.local_line_list then
          while #self.local_line_list >= lid do
            ReleaseLine(table.remove(self.local_line_list))
          end
        end
      end
      
      self.tri_c, self.tri_z = c, z
    else
      if self.local_triangle_list then
        while #self.local_triangle_list > 0 do
          ReleaseTriangle(table.remove(self.local_triangle_list))
        end
        QuestHelper:ReleaseTable(self.local_triangle_list)
        self.local_triangle_list = nil
      end
      
      if self.local_line_list then
        while #self.local_line_list > 0 do
          ReleaseLine(table.remove(self.local_line_list))
        end
        QuestHelper:ReleaseTable(self.local_line_list)
        self.local_line_list = nil
      end
      
      self.tri_c, self.tri_z = nil, nil
    end
    
    if self.old_count > 0 then
      local list = QuestHelper:GetOverlapObjectives(self.objective)
      
      if #list ~= self.old_count then
        self:SetTooltip(list)
        self.old_count = #list
        self:SetGlow(list)
      end
    end
    
    if self.show_glow then
      self.glow_pct = math.min(1, self.glow_pct+elapsed*1.5)
    else
      self.glow_pct = math.max(0, self.glow_pct-elapsed*0.5)
      
      if self.glow_pct == 0 then
        if self.triangle_list then
          while #self.triangle_list > 0 do
            ReleaseTriangle(table.remove(self.triangle_list))
          end
          QuestHelper:ReleaseTable(self.triangle_list)
          self.triangle_list = nil
        end
        
        if self.glow_list then
          while #self.glow_list > 0 do
            QuestHelper:ReleaseTexture(table.remove(self.glow_list))
          end
          QuestHelper:ReleaseTable(self.glow_list)
          self.glow_list = nil
        end
        
        if self.line_list then
          while #self.line_list > 0 do
            ReleaseLine(table.remove(self.line_list))
          end
          QuestHelper:ReleaseTable(self.line_list)
          self.line_list = nil
        end
        
        if not self.next then
          QH_Hook(self, "OnUpdate", nil)
        end
      end
    end
    
    if self.triangle_list then
      for _, tri in ipairs(self.triangle_list) do
        tri:SetVertexColor(triangle_r, triangle_g, triangle_b, self.glow_pct*triangle_opacity/2)
      end
    end
    if self.line_list then
      for _, tri in ipairs(self.line_list) do
        tri:SetVertexColor(triangle_r, triangle_g, triangle_b, self.glow_pct*triangle_opacity)
      end
    end
    if self.glow_list then
      for _, tri in ipairs(self.glow_list) do
        tri:SetVertexColor(triangle_r, triangle_g, triangle_b, self.glow_pct*triangle_opacity)
      end
    end
    if self.local_triangle_list then
      for _, tri in ipairs(self.local_triangle_list) do
        tri:SetVertexColor(triangle_b, triangle_g, triangle_r, triangle_opacity/2)
      end
    end
    if self.local_line_list then
      for _, tri in ipairs(self.local_line_list) do
        tri:SetVertexColor(triangle_b, triangle_g, triangle_r, triangle_opacity)
      end
    end
  end
  
  function icon:OnEnter()
    local list = QuestHelper:GetOverlapObjectives(self.objective)
    self:SetTooltip(list)
    self.old_count = #list
    
    icon.show_glow = true
    
    self:SetGlow(list)
    
    QH_Hook(self, "OnUpdate", self.OnUpdate)
  end
  
  function icon:OnLeave()
    QuestHelper.tooltip:Hide()
    self.show_glow = false
    self.old_count = 0
  end
  
  function icon:OnEvent()
    if self.objective then
      PlaceIcon(self, convertLocation(self.objective.loc))
    else
      self.objective = nil
      self:Hide()
    end
  end
  
  function icon:OnClick()
    rightclick_menu(self.objective)
  end
  
  QH_Hook(icon, "OnClick", icon.OnClick)
  QH_Hook(icon, "OnEnter", icon.OnEnter)
  QH_Hook(icon, "OnLeave", icon.OnLeave)
  QH_Hook(icon, "OnEvent", icon.OnEvent)
  
  icon:RegisterForClicks("RightButtonUp")
  
  QH_Event("WORLD_MAP_UPDATE", function () icon:OnEvent() end)
  
  icon:SetObjective(objective, nxt)
  return icon
end


function QuestHelper:CreateWorldMapMinidad(objective, nxt)
  local icon = CreateFrame("Button", nil, QuestHelper.map_overlay)
  icon:SetFrameStrata("FULLSCREEN")
    
  function icon:SetPosition(objective)
    self:SetHeight(16*QuestHelper_Pref.scale)
    self:SetWidth(16*QuestHelper_Pref.scale)
    
    if self.dot then
      QuestHelper:ReleaseTexture(self.dot)
      self.dot = nil
    end
    
    if objective then
      self.objective = objective
      
      self.dot = QuestHelper:CreateIconTexture(self, 15)
      self.dot:SetAllPoints()
      self.dot:SetDrawLayer("BACKGROUND")
      
      PlaceIcon(self, QuestHelper.Astrolabe:FromAbsoluteContinentPosition(QuestHelper_ParentLookup[self.objective.p], self.objective.x, self.objective.y))
    else
      self.objective = nil
      self:Hide()
    end
  end
  
  
  function icon:OnEnter()
    local list = QuestHelper:GetOverlapObjectives(self.objective)
    self.old_count = #list
    QuestHelper.tooltip:SetOwner(self, "ANCHOR_CURSOR")
    QuestHelper.tooltip:ClearLines()
    
    QuestHelper.tooltip:AddLine(self.objective.desc)
    
    QuestHelper.tooltip:Show()
  end
  
  function icon:OnLeave()
    QuestHelper.tooltip:Hide()
  end
  
  function icon:OnEvent()
    if self.objective then
      PlaceIcon(self, QuestHelper.Astrolabe:FromAbsoluteContinentPosition(QuestHelper_ParentLookup[self.objective.p], self.objective.x, self.objective.y))
    else
      self.objective = nil
      self:Hide()
    end
  end
  
  --function icon:OnClick()
    --rightclick_menu(self.objective)
  --end
  
  --QH_Hook(icon, "OnClick", icon.OnClick)
  QH_Hook(icon, "OnEnter", icon.OnEnter)
  QH_Hook(icon, "OnLeave", icon.OnLeave)
  QH_Hook(icon, "OnEvent", icon.OnEvent)
  
  --icon:RegisterForClicks("RightButtonUp")
  
  QH_Event("WORLD_MAP_UPDATE", function () icon:OnEvent() end)
  
  icon:SetPosition(objective)
  return icon
end

local callbacks = {}
local last_c, last_z, last_x, last_y, last_desc

function QuestHelper:AddWaypointCallback(func, ...)
  local cb = self:CreateTable()
  callbacks[cb] = true
  local len = select("#", ...)
  cb.len = len
  cb.func = func
  for i = 1,len do cb[i] = select(i, ...) end
  cb[len+1] = last_c
  cb[len+2] = last_z
  cb[len+3] = last_x
  cb[len+4] = last_y
  cb[len+5] = last_desc
  
  if last_c then
    func(unpack(cb, 1, len+5))
  end
  
  return cb
end

function QuestHelper:RemoveWaypointCallback(cb)
  callbacks[cb] = nil
  self:ReleaseTable(cb)
end

function QuestHelper:InvokeWaypointCallbacks(c, z, x, y, desc)
  QuestHelper: Assert(not c or type(c) == "number")
  QuestHelper: Assert(not z or type(z) == "number")
  QuestHelper: Assert(not x or type(x) == "number")
  QuestHelper: Assert(not y or type(y) == "number")
  if c == last_c and z == last_z and desc == last_desc and not x and not y then x, y = last_x, last_y end -- sometimes we may not have up-to-date location, but could still in theory be pointing at the same spot
  
  if not c or (x and y) then
    if c ~= last_c or z ~= last_z or x ~= last_x or y ~= last_y or desc ~= last_desc then
      last_c, last_z, last_x, last_y, last_desc = c, z, x, y, desc
      for cb in pairs(callbacks) do
        local len = cb.len
        cb[len+1] = c
        cb[len+2] = z
        cb[len+3] = x
        cb[len+4] = y
        cb[len+5] = desc
        cb.func(unpack(cb, 1, len+5))
      end
    end
  end
end

function QuestHelper:SetMinimapObject(minimap)
	Minimap = minimap
	QuestHelper.Astrolabe:SetMinimapObject(minimap)
	QuestHelper.minimap_marker:SetParent(minimap)
	QuestHelper.Astrolabe.processingFrame:SetParent(minimap)
end

--[[ Small parts of the arrow rendering code are thanks to Tomtom, with the following license:

-------------------------------------------------------------------------
  Copyright (c) 2006-2007, James N. Whitehead II
  All rights reserved.

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are
  met:

      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.
      * Redistributions in binary form must reproduce the above
        copyright notice, this list of conditions and the following
        disclaimer in the documentation and/or other materials provided
        with the distribution.
      * The name or alias of the copyright holder may not be used to endorse 
        or promote products derived from this software without specific prior
        written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
---------------------------------------------------------------------------]]

function QuestHelper:CreateMipmapDodad()
  local icon = CreateFrame("Button", nil, Minimap)
  icon:Hide()
  icon.recalc_timeout = 0
  
  icon.arrow = icon:CreateTexture("BACKGROUND")
  icon.arrow:SetHeight(40)
  icon.arrow:SetWidth(40)
  icon.arrow:SetPoint("CENTER", 0, 0)
  icon.arrow:SetTexture("Interface\\AddOns\\QuestHelper\\MinimapArrow")
  icon.arrow:Hide()
  
  icon.phase = 0
  icon.target = {0, 0, 0, 0}
  
  icon.bg = QuestHelper:CreateIconTexture(icon, 16)
  icon.bg:SetDrawLayer("BACKGROUND")
  icon.bg:SetAllPoints()
  
  function icon:OnUpdate(elapsed)
    local c, z, x, y, textdesc
    if self.obj then
      c, z = QuestHelper.collect_rc, QuestHelper.collect_rz
      if c and z then
        x, y = convertLocationToScreen(self.obj.loc, c, z)
      end
    
      if self.obj.map_desc_chain then
        -- the first line will just be an "enroute" line
        textdesc = (self.obj.arrow_desc or self.obj.map_desc[1]) .. "\n" .. (self.obj.map_desc_chain.arrow_desc or self.obj.map_desc_chain.map_desc[1])
      else
        textdesc = (self.obj.arrow_desc or self.obj.map_desc[1])
      end
      
      if self.obj.arrow_desc then
        textdesc = self.obj.arrow_desc
      end
    end
    
    QuestHelper: Assert(not c or type(c) == "number")
    QuestHelper: Assert(not z or type(z) == "number")
    
    -- Deal with waypoint callbacks
    if QuestHelper_Pref.hide or UnitIsDeadOrGhost("player") and not QuestHelper.InBrokenInstance then
      QuestHelper:InvokeWaypointCallbacks()
    else
      QuestHelper:InvokeWaypointCallbacks(c, z, x, y, textdesc)
    end
    
    if self.obj and not QuestHelper.InBrokenInstance then
      self:Show() -- really only triggers if the non-broken-instance code is being poked
      
      if not QuestHelper_Pref.hide and QuestHelper.Astrolabe:PlaceIconOnMinimap(self, convertLocation(self.obj.loc)) ~= -1 then
        local edge = QuestHelper.Astrolabe:IsIconOnEdge(self)
        
        if edge then
          self.arrow:Show()
          self.dot:Hide()
          self.bg:Hide()
        else
          self.arrow:Hide()
          self.dot:Show()
          self.bg:Show()
          
          self.dot:SetAlpha(QuestHelper_Pref.mini_opacity)
          self.bg:SetAlpha(QuestHelper_Pref.mini_opacity)
        end
        
        if edge then
          local angle = QuestHelper.Astrolabe:GetDirectionToIcon(self)
          if GetCVar("rotateMinimap") == "1" then
            angle = angle + QuestHelper.Astrolabe:GetFacing()
          end
          
          if elapsed then
            if self.phase > 6.283185307179586476925 then
              self.phase = self.phase-6.283185307179586476925+elapsed*3.5
            else
              self.phase = self.phase+elapsed*3.5
            end
          end
          
          local scale = 1.0 + 0.1 * math.sin(self.phase)
        
          local x, y = scale * math.sin(angle + 3.14159 * 0.75) * math.sqrt(0.5), scale * math.cos(angle + 3.14159 * 0.75) * math.sqrt(0.5)
          self.arrow:SetTexCoord(0.5 - x, 0.5 + y, 0.5 + y, 0.5 + x, 0.5 - y, 0.5 - x, 0.5 + x, 0.5 - y)
        end
      else
        self:Hide()
      end
    else
      self:Hide()
    end
  end
  
  function icon:SetObjective(obj)
    self:SetHeight(20*QuestHelper_Pref.scale)
    self:SetWidth(20*QuestHelper_Pref.scale)
    
    if obj ~= self.obj then
      self.obj = obj
      
      self.recalc_timeout = 0
      
      if self.dot then QuestHelper:ReleaseTexture(self.dot) self.dot = nil end
      
      if self.obj then
        self.dot = QuestHelper:CreateIconTexture(self, self.obj.icon_id or 8)
        self.dot:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
        self.dot:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
      end
      
      self:OnUpdate(0)
    end
  end
  
  function icon:OnEnter()
    if self.obj then
      QuestHelper.tooltip:SetOwner(self, "ANCHOR_CURSOR")
      QuestHelper.tooltip:ClearLines()
      
      --[[if self.target[5] then
        QuestHelper.tooltip:AddLine(QHFormat("WAYPOINT_REASON", self.target[5]), unpack(QuestHelper:GetColourTheme().tooltip))
        QuestHelper.tooltip:GetPrevLines():SetFont(QuestHelper.font.serif, 14)
      end]]
      
      QuestHelper:AppendObjectiveToTooltip(self.obj)
      QuestHelper.tooltip:Show()
    end
  end
  
  function icon:OnLeave()
    QuestHelper.tooltip:Hide()
  end
  
  function icon:OnClick()
    rightclick_menu(self.obj)
  end
  
  function icon:OnEvent()
    if self.obj then
      self:Show()
    else
      self:Hide()
    end
  end
  
  QH_Hook(icon, "OnUpdate", icon.OnUpdate)
  QH_Hook(icon, "OnEnter", icon.OnEnter)
  QH_Hook(icon, "OnLeave", icon.OnLeave)
  QH_Hook(icon, "OnClick", icon.OnClick)
  
  icon:RegisterForClicks("RightButtonUp")
  
  QH_Event("PLAYER_ENTERING_WORLD", function () icon:OnEvent() end)
  
  return icon
end
