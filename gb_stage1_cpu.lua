-- Game Boy LR35902 CPU core
-- Stage 1 scaffold: registers, flags, memory interface, stepping, and core opcodes.
-- Stage 2 can provide the full bus/MMU implementation around this CPU.

local CPU = {}
CPU.__index = CPU

local function u8(v) return v % 0x100 end
local function u16(v) return v % 0x10000 end

function CPU.new(bus)
    local self = setmetatable({}, CPU)
    self.bus = bus or {}
    self.a, self.f = 0x01, 0xB0
    self.b, self.c = 0x00, 0x13
    self.d, self.e = 0x00, 0xD8
    self.h, self.l = 0x01, 0x4D
    self.sp, self.pc = 0xFFFE, 0x0100
    self.ime = false
    self.halted = false
    self.stopped = false
    self.cycles = 0
    return self
end

function CPU:read8(addr)
    if self.bus.read8 then return u8(self.bus:read8(addr)) end
    return 0xFF
end

function CPU:write8(addr, value)
    if self.bus.write8 then self.bus:write8(addr, u8(value)) end
end

function CPU:read16(addr)
    local lo = self:read8(addr)
    local hi = self:read8(u16(addr + 1))
    return lo + hi * 0x100
end

function CPU:write16(addr, value)
    self:write8(addr, value)
    self:write8(u16(addr + 1), math.floor(value / 0x100))
end

function CPU:getBC() return self.b * 0x100 + self.c end
function CPU:getDE() return self.d * 0x100 + self.e end
function CPU:getHL() return self.h * 0x100 + self.l end
function CPU:setBC(v) self.b, self.c = math.floor(v / 0x100), u8(v) end
function CPU:setDE(v) self.d, self.e = math.floor(v / 0x100), u8(v) end
function CPU:setHL(v) self.h, self.l = math.floor(v / 0x100), u8(v) end

function CPU:getAF() return self.a * 0x100 + (self.f & 0xF0) end
function CPU:setAF(v) self.a, self.f = math.floor(v / 0x100), u8(v) & 0xF0 end

function CPU:flag(mask) return (self.f & mask) ~= 0 end
function CPU:setFlag(mask, on)
    if on then self.f = self.f | mask else self.f = self.f & (~mask) end
    self.f = self.f & 0xF0
end

function CPU:push(v)
    self.sp = u16(self.sp - 2)
    self:write16(self.sp, v)
end

function CPU:pop()
    local v = self:read16(self.sp)
    self.sp = u16(self.sp + 2)
    return v
end

function CPU:fetch8()
    local v = self:read8(self.pc)
    self.pc = u16(self.pc + 1)
    return v
end

function CPU:fetch16()
    local v = self:read16(self.pc)
    self.pc = u16(self.pc + 2)
    return v
end

function CPU:addA(v, carry)
    local c = carry and (self:flag(0x10) and 1 or 0) or 0
    local old = self.a
    local r = old + v + c
    self.a = u8(r)
    self.f = 0
    self:setFlag(0x80, self.a == 0)
    self:setFlag(0x20, ((old & 0x0F) + (v & 0x0F) + c) > 0x0F)
    self:setFlag(0x10, r > 0xFF)
end

function CPU:subA(v, carry)
    local c = carry and (self:flag(0x10) and 1 or 0) or 0
    local old = self.a
    local r = old - v - c
    self.a = u8(r)
    self.f = 0x40
    self:setFlag(0x80, self.a == 0)
    self:setFlag(0x20, ((old & 0x0F) - (v & 0x0F) - c) < 0)
    self:setFlag(0x10, r < 0)
end

function CPU:step()
    if self.stopped then return 4 end
    if self.halted then return 4 end

    local op = self:fetch8()
    local cycles = 4

    if op == 0x00 then
        cycles = 4

    elseif op == 0x3E then
        self.a = self:fetch8(); cycles = 8
    elseif op == 0x06 then
        self.b = self:fetch8(); cycles = 8
    elseif op == 0x0E then
        self.c = self:fetch8(); cycles = 8
    elseif op == 0x16 then
        self.d = self:fetch8(); cycles = 8
    elseif op == 0x1E then
        self.e = self:fetch8(); cycles = 8
    elseif op == 0x26 then
        self.h = self:fetch8(); cycles = 8
    elseif op == 0x2E then
        self.l = self:fetch8(); cycles = 8

    elseif op == 0x7F then self.a = self.a
    elseif op == 0x78 then self.a = self.b
    elseif op == 0x79 then self.a = self.c
    elseif op == 0x7A then self.a = self.d
    elseif op == 0x7B then self.a = self.e
    elseif op == 0x7C then self.a = self.h
    elseif op == 0x7D then self.a = self.l
    elseif op == 0x0A then self.a = self:read8(self:getBC()); cycles = 8
    elseif op == 0x1A then self.a = self:read8(self:getDE()); cycles = 8
    elseif op == 0x7E then self.a = self:read8(self:getHL()); cycles = 8

    elseif op == 0x77 then self:write8(self:getHL(), self.a); cycles = 8
    elseif op == 0x70 then self:write8(self:getHL(), self.b); cycles = 8
    elseif op == 0x71 then self:write8(self:getHL(), self.c); cycles = 8
    elseif op == 0x72 then self:write8(self:getHL(), self.d); cycles = 8
    elseif op == 0x73 then self:write8(self:getHL(), self.e); cycles = 8
    elseif op == 0x36 then self:write8(self:getHL(), self:fetch8()); cycles = 12

    elseif op == 0xAF then self.a = self.a ~ self.a; self.f = 0x80
    elseif op == 0xA7 then self.a = self.a & self.a; self.f = (self.a == 0) and 0xA0 or 0x20
    elseif op == 0xB7 then self.f = (self.a == 0) and 0x80 or 0

    elseif op == 0x80 then self:addA(self.b, false)
    elseif op == 0x81 then self:addA(self.c, false)
    elseif op == 0x82 then self:addA(self.d, false)
    elseif op == 0x83 then self:addA(self.e, false)
    elseif op == 0x87 then self:addA(self.a, false)
    elseif op == 0xC6 then self:addA(self:fetch8(), false); cycles = 8

    elseif op == 0x90 then self:subA(self.b, false)
    elseif op == 0x91 then self:subA(self.c, false)
    elseif op == 0x92 then self:subA(self.d, false)
    elseif op == 0x93 then self:subA(self.e, false)
    elseif op == 0x97 then self:subA(self.a, false)
    elseif op == 0xD6 then self:subA(self:fetch8(), false); cycles = 8

    elseif op == 0xC3 then
        self.pc = self:fetch16(); cycles = 16
    elseif op == 0x18 then
        local n = self:fetch8(); if n >= 0x80 then n = n - 0x100 end
        self.pc = u16(self.pc + n); cycles = 12
    elseif op == 0xCD then
        local addr = self:fetch16(); self:push(self.pc); self.pc = addr; cycles = 24
    elseif op == 0xC9 then
        self.pc = self:pop(); cycles = 16
    elseif op == 0xC5 then self:push(self:getBC()); cycles = 16
    elseif op == 0xD5 then self:push(self:getDE()); cycles = 16
    elseif op == 0xE5 then self:push(self:getHL()); cycles = 16
    elseif op == 0xF5 then self:push(self:getAF()); cycles = 16
    elseif op == 0xC1 then self:setBC(self:pop()); cycles = 12
    elseif op == 0xD1 then self:setDE(self:pop()); cycles = 12
    elseif op == 0xE1 then self:setHL(self:pop()); cycles = 12
    elseif op == 0xF1 then self:setAF(self:pop()); cycles = 12

    elseif op == 0xF3 then self.ime = false
    elseif op == 0xFB then self.ime = true
    elseif op == 0x76 then self.halted = true

    elseif op == 0xCB then
        local cb = self:fetch8()
        -- Basic CB register rotates/bit operations.
        if cb == 0x07 then
            local c = (self.a & 0x80) ~= 0
            self.a = u8((self.a << 1) | (c and 1 or 0))
            self.f = c and 0x10 or 0
            if self.a == 0 then self.f = self.f | 0x80 end
        elseif cb >= 0x40 and cb <= 0x7F then
            local bit = math.floor((cb - 0x40) / 8)
            local reg = (cb - 0x40) % 8
            local vals = {self.b,self.c,self.d,self.e,self.h,self.l,self:read8(self:getHL()),self.a}
            local v = vals[reg + 1]
            self.f = 0x20 | (self.f & 0x10)
            self:setFlag(0x80, (v & (1 << bit)) == 0)
            if reg == 6 then cycles = 12 end
        else
            error(string.format("Unimplemented CB opcode %02X at %04X", cb, u16(self.pc - 2)))
        end
    else
        error(string.format("Unimplemented opcode %02X at %04X", op, u16(self.pc - 1)))
    end

    self.cycles = self.cycles + cycles
    return cycles
end

function CPU:runCycles(target)
    local used = 0
    while used < target and not self.stopped do
        used = used + self:step()
    end
    return used
end

return CPU
