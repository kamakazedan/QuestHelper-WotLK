QuestHelper_File["dodads_triangles.lua"] = "1.4.1"
QuestHelper_Loadtime["dodads_triangles.lua"] = GetTime()

-- I'm really curious what people might make out of this file. I'm not actually open-sourcing it yet, but let's say that if you *were* to come up with a neat idea, and wanted to use this code, I would almost certainly be willing to let you use it. Contact me as ZorbaTHut on EFNet/Freenode/Synirc, or zorba-qh-triangles@pavlovian.net email, or ZorbaTHut on AIM.

local function print()
end

function matrix_create()
  return {1, 0, 0, 0, 1, 0, 0, 0, 1}
end

function matrix_rescale(matrix, x, y)
  matrix[1], matrix[4] = matrix[1] * x, matrix[4] * x
  matrix[2], matrix[5] = matrix[2] * y, matrix[5] * y
end
function matrix_mult(matrix, a, b, c, d, e, f)  -- this is probably buggy
  matrix[1], matrix[2], matrix[3], matrix[4], matrix[5], matrix[6], matrix[7], matrix[8], matrix[9] =
    matrix[1] * a + matrix[4] * b + matrix[7] * c, matrix[2] * a + matrix[5] * b + matrix[8] * c, matrix[3] * a + matrix[6] * b + matrix[9] * c,
    matrix[1] * d + matrix[4] * e + matrix[7] * f, matrix[2] * d + matrix[5] * e + matrix[8] * f, matrix[3] * d + matrix[6] * e + matrix[9] * f,
    matrix[7], matrix[8], matrix[9]
end
function matrix_rotate(matrix, angle)
  matrix_mult(matrix, cos(angle), -sin(angle), 0, sin(angle), cos(angle), 0)
end
function matrix_print(matrix)
  print(string.format("\n%f %f %f\n%f %f %f\n%f %f %f", unpack(matrix)))
end

local function dist(sx, sy, ex, ey)
  local dx = sx - ex
  local dy = sy - ey
  dx, dy = dx * dx, dy * dy
  return math.sqrt(dx + dy)
end

local function testrange(...)
  for k = 1, select("#", ...) do
    if not (select(k, ...) > -60000 and select(k, ...) < 60000) then
      return true
    end
  end
end
-- thoughts about the transformation
-- start with a right triangle, define the top as the base (find a base)
-- rescale Y to get the right height
-- skew X to get the right bottom X position
-- now we have the right shape
-- rotate, rescale, translate?

-- for now, we define a-b as the base, which means c is the peak

local spots = {}
for k = 1, 3 do
  local minbutton = CreateFrame("Button", nil, UIParent)
  minbutton:SetWidth(50)
  minbutton:SetHeight(50)
  
  local minbutton_tex = minbutton:CreateTexture()
  minbutton_tex:SetAllPoints()
  minbutton_tex:SetTexture(1, 0, 0, 0.5)

  minbutton.Moove = function(self, x, y)
    minbutton:ClearAllPoints()
    minbutton:SetPoint("CENTER", UIParent, "TOPLEFT", x, -y)
  end
  table.insert(spots, minbutton)
end

local function MakeTriangle(frame)
  tex = frame:CreateTexture()
  tex:SetTexture("Interface\\AddOns\\QuestHelper\\triangle")
  
  tex.parent_frame = frame
  -- relative to 0,1 coordinates relative to parent
  tex.SetTriangle = function(self, ax, ay, bx, by, cx, cy)
    -- do we need to reverse the triangle?
    if ax * by - bx * ay + bx * cy - cx * by + cx * ay - cy * ax < 0 then
      ax, bx = bx, ax
      ay, by = by, ay
    end
    
    print(ax, ay, bx, by, cx, cy)
    ax, bx, cx = ax * frame:GetWidth(), bx * frame:GetWidth(), cx * frame:GetWidth()
    ay, by, cy = ay * frame:GetHeight(), by * frame:GetHeight(), cy * frame:GetHeight()
    print(ax, ay, bx, by, cx, cy)
    self:ClearAllPoints()
    
    local sx = math.min(ax, bx, cx)
    local sy = math.min(ay, by, cy)
    local ex = math.max(ax, bx, cx)
    local ey = math.max(ay, by, cy)
    
    local disty = math.max(ex - sx, ey - sy) / 2
    
    --print("TOPLEFT", frame, "TOPLEFT", math.min(ax, bx, cx) * frame:GetWidth(), math.min(ax, bx, cx) * frame:GetHeight())
    --print("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -math.max(ax, bx, cx) * frame:GetWidth(), -math.max(ax, bx, cx) * frame:GetHeight())
    self:SetPoint("TOPLEFT", frame, "TOPLEFT", (sx + ex) / 2 - disty, -(sy + ey) / 2 + disty)
    self:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", (sx + ex) / 2 + disty, -(sy + ey) / 2 - disty)
    
    local wid = disty * 2
    local hei = disty * 2
    
    local widextra = (wid - (ex - sx)) / 2
    local heiextra = (hei - (ey - sy)) / 2
    
    local base = matrix_create()
    
    matrix_mult(base, 1, 0, -1 / 512, 0, 1, -1 / 512)
    matrix_rescale(base, 512 / 510, 512 / 510)
    
    local lenab = dist(ax, ay, bx, by)
    local lenbc = dist(bx, by, cx, cy)
    local lenca = dist(cx, cy, ax, ay)
    local s = (lenab + lenbc + lenca) / 2
    local area = math.sqrt(s * (s - lenab) * (s - lenbc) * (s - lenca)) -- heron's formula
    -- triangle area=base*height/2, therefore height=area/base*2
    local height = area / lenab * 2
    
    print(wid, hei, disty, ex - sx, ey - sy)
    print(lenab, lenbc, lenca)
    print(area, height)
    print(lenab / wid, height / hei)
    
    matrix_print(base)
    matrix_rescale(base, lenab / wid, height / hei)
    matrix_print(base)
    
    -- now we have it scaled properly, now we have to skew
    -- right now we have:
    --   A----------B
    --                   |
    --                   C
    -- We want:
    --     A------------B
    --
    --  C
    -- Virtual point:
    --  D A------------B
    --
    --  C
    -- So the question is, how long is DB? Find that out, divide by height, and there's our skew constant
    -- unit(A-B) dot (C-B) - does this work? I think so
    -- alternatively, ((A-B) dot (C-B)) / lenab
    
    print("db is", ((ax - bx) * (cx - bx) + (ay - by) * (cy - by)))
    print("height is", height)
    print("lenab is", lenab)
    
    if height == 0 then
      self:SetTexCoord(3, 3, 4, 4)
      return
    end
    
    -- same as matrix_mult(base, 1, (nastything), 0, 1) (I think? maybe not?)
    matrix_mult(base, 1, -((ax - bx) * (cx - bx) + (ay - by) * (cy - by)) / lenab / height, 0, 0, 1, 0)
    --base[2] = base[2] - ((ax - bx) * (cx - bx) + (ay - by) * (cy - by)) / lenab / height * base[5]
    
    matrix_print(base)
    
    -- next: we sit and rotate on it
    
    local angle = atan2(ax - bx, ay - by)
    print(angle)
    
    matrix_rotate(base, -angle - 90) -- this will take adjustment
    
    matrix_print(base)
    
    -- now we translate to the expected position
    
    print(ax - sx, ay - sy, (ax - sx) / lenab, (ay - sy) / lenab, (ax - sx) / wid, (ay - sy) / hei)
    
    matrix_mult(base, 1, 0, tigo or ((ax - sx + widextra) / wid), 0, 1, togo or ((ay - sy + heiextra) / hei))
    --base[3] = base[3] + (ax - sx) / lenab
    --base[6] = base[6] + (ay - sy) / lenab
    
    --[[matrix_rescale(base, 0.5, 0.5)
    base[3] = base[3] + wing
    base[6] = base[6] + wong]]
    
    
    local A, B, C, D, E, F = base[1], base[2], base[3], base[4], base[5], base[6]
    
    local det = A*E - B*D
    local ULx, ULy, LLx, LLy, URx, URy, LRx, LRy
    
    ULx, ULy = ( B*F - C*E ) / det, ( -(A*F) + C*D ) / det
    LLx, LLy = ( -B + B*F - C*E ) / det, ( A - A*F + C*D ) / det
    URx, URy = ( E + B*F - C*E ) / det, ( -D - A*F + C*D ) / det
    LRx, LRy = ( E - B + B*F - C*E ) / det, ( -D + A -(A*F) + C*D ) / det
    
    if testrange(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy) then
      self:SetTexCoord(3, 3, 4, 4)
      return
    end
    
    --QuestHelper:TextOut(string.format("%f %f %f %f %f %f %f %f %f", det, ULx, ULy, LLx, LLy, URx, URy, LRx, LRy))
    --QuestHelper:TextOut(string.format("%f %f %f %f %f %f", A, B, C, D, E, F))
    
    self:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy); -- the sound you hear is vomiting
    
    --[[spots[1]:Moove(ax, ay)
    spots[2]:Moove(bx, by)
    spots[3]:Moove(cx, cy)]]
  end
  
  return tex
end

local alloc = {}

function CreateTriangle(frame)
  if alloc[frame] and #alloc[frame] > 0 then
    return table.remove(alloc[frame])
  else
    return MakeTriangle(frame)
  end
end

function ReleaseTriangle(tri)
  if not alloc[tri.parent_frame] then alloc[tri.parent_frame] = {} end
  table.insert(alloc[tri.parent_frame], tri)
  tri:Hide()
end





local function MakeLine(frame)
  local tex = frame:CreateTexture()
  tex:SetTexture("Interface\\AddOns\\QuestHelper\\line")
  
  tex.parent_frame = frame
  -- A band thickness wide (in the frame's units, 2 if not given) along the line from (ax, ay) to (bx, by), given from
  -- 0 to 1 across and down the frame. The texture is opaque but for a clear edge: it goes over a box round the band,
  -- with coordinates that put its opaque part on the band and its clear edge everywhere else.
  tex.SetLine = function(self, ax, ay, bx, by, thickness)
    local w, h = frame:GetWidth(), frame:GetHeight()
    ax, ay, bx, by = ax * w, ay * h, bx * w, by * h
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    local t = thickness or 2
    self:ClearAllPoints()
    if not (len > 1e-6 and t > 0) then
      self:SetPoint("TOPLEFT", frame, "TOPLEFT", ax, -ay)
      self:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", ax + 1, -ay - 1)
      self:SetTexCoord(3, 3, 3, 4, 4, 3, 4, 4)  -- all clear edge
      return
    end
    local ex, ey = dx / len, dy / len  -- along the line
    local nx, ny = -ey, ex             -- across it
    local hx, hy = nx * t / 2, ny * t / 2
    local left, right = math.min(ax - hx, ax + hx, bx - hx, bx + hx), math.max(ax - hx, ax + hx, bx - hx, bx + hx)
    local top, bottom = math.min(ay - hy, ay + hy, by - hy, by + hy), math.max(ay - hy, ay + hy, by - hy, by + hy)
    self:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
    self:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", right, -bottom)
    -- where each corner of the box is: how far along the line, and how far across the band
    local function at(x, y)
      local rx, ry = x - ax, y - ay
      return (rx * ex + ry * ey) / len, 0.5 + (rx * nx + ry * ny) / t
    end
    local ulx, uly = at(left, top)
    local llx, lly = at(left, bottom)
    local urx, ury = at(right, top)
    local lrx, lry = at(right, bottom)
    self:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
  end
  
  return tex
end



-- haha
-- yeeeeaah, I just overrode a local variable with another near-identical local variable
-- that's gonna bite me someday
local alloc = {}

-- guess whether I changed this code after copying it
-- hint:
-- I didn't change this code after copying it
-- are you shocked
-- man, if you've read this far in the QH sourcecode, you sure as hell better not be shocked
-- 'cause
-- yeah
-- that'd be kind of sad.
function CreateLine(frame)
  if alloc[frame] and #alloc[frame] > 0 then
    return table.remove(alloc[frame])
  else
    return MakeLine(frame)
  end
end

function ReleaseLine(tri)
  if not alloc[tri.parent_frame] then alloc[tri.parent_frame] = {} end
  table.insert(alloc[tri.parent_frame], tri)
  tri:Hide()
end

-- note: variable name is "tritest". try to guess why
function testit()
  if tritest then tritest:Hide() end
  tritest = CreateLine(UIParent)
  tritest:SetLine(0.5, 0.6, 0.8, 0.7)
  tritest:Show()
end
