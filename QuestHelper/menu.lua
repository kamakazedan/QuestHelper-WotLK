QuestHelper_File["menu.lua"] = "1.4.1"
QuestHelper_Loadtime["menu.lua"] = GetTime()

QuestHelper.active_menu = nil

-- These are drawn to match the game's own right-click menus. They're still our own frames rather than the real thing, because addons that open the real dropdown from their own code can stop Set Focus and friends working in the unit menus.
local menuBackdrop = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 16,
    tile = true,
    tileSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 4 }}
local menuBackdropColor = { 0.09, 0.09, 0.19, 1 }
local menuBackdropBorderColor = { 1, 1, 1, 1 }

local menuPadLeft, menuPadRight, menuPadY = 15, 10, 15
local menuRowHeight = 16
local menuCloseDelay = 2  -- seconds the pointer can be away before the menu closes itself, same as the game's

local function Menu_AddItem(self, item)
  item:ClearAllPoints()
  item:SetParent(self)
  item:SetPoint("TOPLEFT", self, "TOPLEFT")
  item.parent = self
  table.insert(self.items, item)
end

local function Menu_SetCloseFunction(self, ...)
  self.func_arg = {...}
  self.func = table.remove(self.func_arg, 1)
end

-- Is the pointer over this menu, or any submenu hanging off it?
local function Menu_ContainsCursor(self)
  local left, right, top, bottom = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
  if left and right and top and bottom then  -- frames don't always know where they are
    local x, y = GetCursorPosition()
    local scale = self:GetEffectiveScale()
    x, y = x / scale, y / scale
    if x >= left and x <= right and y >= bottom and y <= top then return true end
  end
  
  return self.submenu and self.submenu.showing and Menu_ContainsCursor(self.submenu)
end

local function Menu_OnUpdate(self, elapsed)
  if not self.showing then
    QH_Hook(self, "OnUpdate", nil)
    self:Hide()
    if self.func then
      self.func(unpack(self.func_arg))
    end
    if self.auto_release then
      QuestHelper:ReleaseMenu(self)
    end
    return
  end
  
  if self.parent then  -- the menu at the top looks after its submenus
    QH_Hook(self, "OnUpdate", nil)
    return
  end
  
  if Menu_ContainsCursor(self) then
    self.away = 0
  else
    self.away = self.away + elapsed
    if self.away >= menuCloseDelay then self:DoHide() end
  end
end

local function Menu_DoShow(self)
  self.showing = true
  self.away = 0
  
  local w, h = 0, 0
  
  for i, c in ipairs(self.items) do
    local cw, ch = c:GetSize()
    w = math.max(w, cw)
    h = h + ch
  end
  
  local y = menuPadY
  
  self:SetWidth(w+menuPadLeft+menuPadRight)
  self:SetHeight(h+2*menuPadY)
  self:Show()
  QH_Hook(self, "OnUpdate", self.OnUpdate)
  
  for i, c in ipairs(self.items) do
    local cw, ch = c:GetSize()
    c:ClearAllPoints()
    c:SetSize(w, ch)
    c:SetPoint("TOPLEFT", self, "TOPLEFT", menuPadLeft, -y)
    y = y + ch
  end
  
  if self.parent then
    self.level = self.parent.parent.level + #self.parent.parent.items + 1
    self:SetFrameStrata(self.parent:GetFrameStrata())   -- It should be sufficient to just set all to "TOOLTIP", but this seemed more versatile...
  else
    -- When there's no world map, or the world map is in a window, the menus
    -- are un-parented.  So make sure they're at a sufficient strata to be seen.
    self:SetFrameStrata("TOOLTIP")
  end
  
  self:SetFrameLevel(self.level)
  
  for i, n in ipairs(self.items) do
    n.level = self.level+i
    n:SetFrameLevel(n.level)
    n:SetFrameStrata(self:GetFrameStrata())
    n:DoShow()
  end
end

local function Menu_DoHide(self)
  self.showing = false
  QH_Hook(self, "OnUpdate", self.OnUpdate)
  
  if self.active_item then
    self.active_item.highlighting = false
    QH_Hook(self.active_item, "OnUpdate", self.active_item.OnUpdate)
  end
  
  for i, n in ipairs(self.items) do
    n:DoHide()
  end
end

local function Menu_ShowAtCursor(self, auto_release)
  auto_release = (auto_release == nil) and true or auto_release
  self.auto_release = auto_release

  -- Set up the menu position, parentage, etc
  local x, y = GetCursorPosition()
  
  local parent = not UIParent:IsVisible() and QuestHelper.map_overlay_uncropped or UIParent
  self:SetParent(parent)
  self.level = (parent or UIParent):GetFrameLevel()+10
  self:ClearAllPoints()
  
  -- Need to call DoShow before setting the position so that the width and height will have been calculated.
  self:DoShow()
  
  -- Like the game's menus, the corner goes at the pointer, and it opens the other way if it would run off the side of the screen.
  local scale = parent and parent:GetEffectiveScale() or 1
  local w, h = self:GetWidth()*scale, self:GetHeight()*scale
  local screen_right, screen_top = UIParent:GetRight()*UIParent:GetEffectiveScale(), UIParent:GetTop()*UIParent:GetEffectiveScale()
  
  local left = x - 3
  if left + w > screen_right then left = x + 3 - w end
  left = math.max(0, math.min(left, screen_right - w))
  local top = math.min(screen_top, math.max(h, y + 3))
  
  self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
  
  if QuestHelper.active_menu and QuestHelper.active_menu ~= self then
    QuestHelper.active_menu:DoHide()
  end
  
  QuestHelper.active_menu = self
end


function QuestHelper:CreateMenu()
  local menu = self:CreateFrame(UIParent)
  menu:Hide()
  
  menu.items = self:CreateTable()
  menu:SetMovable(true)
  menu:SetFrameStrata("TOOLTIP") -- A good default, but we usually re-parent the menus, which clobbers this.
  menu:SetBackdrop(menuBackdrop)
  menu:SetBackdropColor(unpack(menuBackdropColor))
  menu:SetBackdropBorderColor(unpack(menuBackdropBorderColor))
  
  menu.AddItem = Menu_AddItem
  menu.SetCloseFunction = Menu_SetCloseFunction
  menu.OnUpdate = Menu_OnUpdate
  menu.DoShow = Menu_DoShow
  menu.DoHide = Menu_DoHide
  menu.ShowAtCursor = Menu_ShowAtCursor
  
  menu.showing = false
  menu.level = 2
  menu:SetFrameLevel(menu.level)
  
  return menu
end

function QuestHelper:ReleaseMenu(menu)
  while #menu.items > 0 do
    local item = table.remove(menu.items)
    self:ReleaseMenuItem(item)
  end
  
  if self.active_menu == menu then
    self.active_menu = nil
  end
  
  self:ReleaseTable(menu.items)
  self:ReleaseFrame(menu)
end

local function MenuItem_AddTexture(self, tex, before)
  if tex.icon_id == 10 or tex.icon_id == 12 then  -- QH's "this one's selected" marks, which the game draws as a yellow tick
    tex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetWidth(24)
    tex:SetHeight(24)
    tex.menu_slot = 16  -- the picture has empty space around the tick, so text can sit closer than its width would suggest
  end
  
  if before then
    table.insert(self.lchildren, 1, tex)
  else
    table.insert(self.rchildren, tex)
  end
end

local function MenuItem_DoShow(self)
  self.showing = true
  QH_Hook(self, "OnUpdate", self.OnUpdate)
  self:Show()
end

local function MenuItem_DoHide(self)
  if self.submenu then
    self.submenu:DoHide()
  end
  
  self.showing = false
  QH_Hook(self, "OnUpdate", self.OnUpdate)
end

local function MenuItem_OnUpdate(self, elapsed)
  QH_Hook(self, "OnUpdate", nil)
  
  if not self.showing then self:Hide() end
  self:Shade(self.showing and self.highlighting)
end

local function MenuItem_Shade(self, lit)
  if lit then
    self.background:Show()
  else
    self.background:Hide()
  end
end

local function MenuItem_SetFunction(self, ...)
  self.func_arg = {...}
  self.func = table.remove(self.func_arg, 1)
end

local function MenuItem_SetSubmenu(self, menu)
  --[[ assert(not self.submenu and menu) ]]
  menu:ClearAllPoints()
  menu:SetParent(self)
  menu:SetPoint("TOPLEFT", self, "TOPLEFT")
  menu.parent = self
  self.submenu = menu
  
  local arrow = QuestHelper:CreateTexture(self, "Interface\\ChatFrame\\ChatFrameExpandArrow")
  arrow:SetWidth(16)
  arrow:SetHeight(16)
  self:AddTexture(arrow)
end

local function MenuItem_OnEnter(self)
  self.highlighting = true
  QH_Hook(self, "OnUpdate", self.OnUpdate)
  
  if self.parent.active_item and self.parent.active_item ~= self then
    self.parent.active_item.highlighting = false
    QH_Hook(self.parent.active_item, "OnUpdate", self.parent.active_item.OnUpdate)
  end
  
  self.parent.active_item = self
  
  if self.parent.submenu and self.parent.submenu ~= self.submenu then
    self.parent.submenu:DoHide()
    self.parent.submenu = nil
  end
  
  if self.submenu then
    self.parent.submenu = self.submenu
    self.submenu:ClearAllPoints()
    
    local v, h1, h2 = "TOP", "LEFT", "RIGHT"
    
    self.submenu:DoShow()
    
    local scale = self:GetEffectiveScale()
    
    if (self:GetRight()+self.submenu:GetWidth())*scale > UIParent:GetRight()*UIParent:GetEffectiveScale() then
      h1, h2 = h2, h1
    end
    
    if (self:GetTop()+menuPadY-self.submenu:GetHeight())*scale < 0 then
      v = "BOTTOM"
    end
    
    -- Lines the submenu's first row up with this one.
    self.submenu:SetPoint(v..h1, self, v..h2, 0, (v == "TOP") and menuPadY or -menuPadY)
    self.submenu:DoShow()
  end
end

local function MenuItem_OnLeave(self)
  if not self.submenu then  -- a row stays lit while its submenu's open
    self.highlighting = false
    QH_Hook(self, "OnUpdate", self.OnUpdate)
  end
end

local function MenuItem_GetSize(self)
  self.text:SetParent(UIParent) -- Remove the text's parent so that it doesn't inherit scaling and mess up the dimensions.
  self.text:ClearAllPoints()
  self.text:SetWidth(0)
  self.text:SetHeight(0)
  
  self.text_w = self.text:GetStringWidth()+2
  if self.text_w >= 320 then
    -- Clamp width to 320, then ballance the two rows (using a binary search)
    self.text:SetWidth(320)
    self.text_h = self.text:GetHeight()+1
    local mn, mx = 100, 321
    while mn ~= mx do
      local w = math.floor((mn+mx)*0.5)
      self.text:SetWidth(w-1)
      if self.text:GetHeight() <= self.text_h then
        mx = w
      else
        mn = w+1
      end
    end
    
    self.text_w = mn+1
    self.text:SetWidth(self.text_w)
  else
    self.text:SetWidth(self.text_w)
    self.text_h = self.text:GetHeight()+1
  end
  
  self.text:SetParent(self)
  
  local w, h = self.text_w, math.max(self.text_h+2, menuRowHeight)
  
  for i, f in ipairs(self.lchildren) do
    w = w + (f.menu_slot or f:GetWidth()) + 4
  end
  
  for i, f in ipairs(self.rchildren) do
    w = w + (f.menu_slot or f:GetWidth()) + 4
  end
  
  self.needed_width = w
  
  return w, h
end

local function MenuItem_SetSize(self, w, h)
  self:SetWidth(w)
  self:SetHeight(h)
  
  local x = 0
  
  for i, f in ipairs(self.lchildren) do
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(h-f:GetHeight())*0.5)
    x = x + (f.menu_slot or f:GetWidth()) + 4
  end
  
  local text_x = x
  x = w
  
  for i, f in ipairs(self.rchildren) do
    x = x - (f.menu_slot or f:GetWidth())
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", self, "TOPLEFT", x, -(h-f:GetHeight())*0.5)
    x = x - 4
  end
  
  self.text:ClearAllPoints()
  self.text:SetPoint("TOPLEFT", self, "TOPLEFT", text_x, -(h-self.text_h)*0.5)
end

local function MenuItem_OnClick(self, btn)
  if btn == "RightButton" then
    local parent = self.parent
    while parent.parent do
      parent = parent.parent
    end
    parent:DoHide()
  elseif btn == "LeftButton" and self.func then
    self.func(unpack(self.func_arg))
    local parent = self.parent
    while parent.parent do
      parent = parent.parent
    end
    parent:DoHide()
  end
end

function QuestHelper:CreateMenuItem(menu, text)
  item = self:CreateFrame(menu)
  item:Hide()
  
  item.lchildren = self:CreateTable()
  item.rchildren = self:CreateTable()
  item.text = self:CreateText(item, text, 10, self.font.serif)
  item.text:SetJustifyH("LEFT")
  item.text:SetShadowColor(0, 0, 0, 1)
  item.background = self:CreateTexture(item, "Interface\\QuestFrame\\UI-QuestTitleHighlight")
  item.background:SetBlendMode("ADD")
  item.background:SetDrawLayer("BACKGROUND")
  item.background:SetAllPoints()
  item.background:Hide()
  
  item.showing = false
  item.highlighting = false
  
  item.AddTexture = MenuItem_AddTexture
  item.DoShow = MenuItem_DoShow
  item.DoHide = MenuItem_DoHide
  item.OnUpdate = MenuItem_OnUpdate
  item.Shade = MenuItem_Shade
  item.SetFunction = MenuItem_SetFunction
  item.SetSubmenu = MenuItem_SetSubmenu
  item.OnEnter = MenuItem_OnEnter
  item.OnLeave = MenuItem_OnLeave
  item.GetSize = MenuItem_GetSize
  item.SetSize = MenuItem_SetSize
  item.OnClick = MenuItem_OnClick
  
  item:RegisterForClicks("LeftButtonUp", "RightButtonDown")
  QH_Hook(item, "OnEnter", item.OnEnter)
  QH_Hook(item, "OnLeave", item.OnLeave)
  QH_Hook(item, "OnClick", item.OnClick)
  
  menu:AddItem(item)
  
  return item
end

function QuestHelper:ReleaseMenuItem(item)
  item:Hide()
  
  while #item.lchildren > 0 do
    local child = table.remove(item.lchildren)
    self:ReleaseTexture(child)
  end
  
  while #item.rchildren > 0 do
    local child = table.remove(item.rchildren)
    self:ReleaseTexture(child)
  end
  
  if item.submenu then
    self:ReleaseMenu(item.submenu)
    item.submenu = nil
  end
  
  self:ReleaseTable(item.lchildren)
  self:ReleaseTable(item.rchildren)
  self:ReleaseText(item.text)
  self:ReleaseTexture(item.background)
  self:ReleaseFrame(item)
end

local function MenuTitle_OnDragStart(self)
  local parent = self.parent
  
  while parent.parent do
    parent = parent.parent
  end
  
  parent:StartMoving()
end

local function MenuTitle_OnDragStop(self)
  local parent = self.parent
  
  while parent.parent do
    parent = parent.parent
  end
  
  parent:StopMovingOrSizing()
end

local function MenuTitle_OnClick(self)
  local parent = self.parent
  
  while parent.parent do
    parent = parent.parent
  end
  
  parent:DoHide()
end

function QuestHelper:CreateMenuTitle(menu, title)
  local item = self:CreateMenuItem(menu, title)
  
  item.text:SetTextColor(1, 0.82, 0)
  
  item.OnDragStart = MenuTitle_OnDragStart
  item.OnDragStop = MenuTitle_OnDragStop
  item.Shade = QuestHelper.nop
  item.OnClick = MenuTitle_OnClick
  
  item:RegisterForClicks("RightButtonDown")
  QH_Hook(item, "OnClick", item.OnClick)
  QH_Hook(item, "OnDragStart", item.OnDragStart)
  QH_Hook(item, "OnDragStop", item.OnDragStop)
  item:RegisterForDrag("LeftButton")
end
