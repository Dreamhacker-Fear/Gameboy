-- Game Boy Stage 2: memory bus + cartridge loader
-- Designed to be connected to gb_stage1_cpu.lua.
-- This layer owns the 64 KiB address space and basic DMG memory mapping.

local Bus = {}
Bus.__index = Bus

local function u8(v) return v % 0x100 end
local function u16(v) return v % 0x10000 end

function Bus.new(rom)
    local self = setmetatable({}, Bus)
    self.rom = rom or {}
    self.vram = {}
    self.wram = {}
    self.oam = {}
    self.io = {}
    self.hram = {}
    self.ie = 0

    for i = 0, 0x1FFF do self.vram[i] = 0 end
    for i = 0, 0x1FFF do self.wram[i] = 0 end
    for i = 0, 0x9F do self.oam[i] = 0 end
    for i = 0, 0x7F do self.hram[i] = 0 end

    self.joypad = 0xCF
    self.div = 0
    self.tima = 0
    self.tma = 0
    self.tac = 0
    self.iflag = 0xE1
    self.lcdc = 0x91
    self.stat = 0x85
    self.ly = 0
    self.lyc = 0
    self.bgp = 0xFC
    self.obp0 = 0xFF
    self.obp1 = 0xFF
    self.wy = 0
    self.wx = 0

    return self
end

function Bus:loadROM(data)
    self.rom = {}
    for i = 1, #data do self.rom[i - 1] = data[i] end
end

function Bus:read8(addr)
    addr = u16(addr)

    if addr <= 0x7FFF then
        return u8(self.rom[addr] or 0xFF)
    elseif addr <= 0x9FFF then
        return u8(self.vram[addr - 0x8000] or 0)
    elseif addr <= 0xBFFF then
        return 0xFF -- external cartridge RAM placeholder
    elseif addr <= 0xDFFF then
        return u8(self.wram[addr - 0xC000] or 0)
    elseif addr <= 0xFDFF then
        return u8(self.wram[addr - 0xE000] or 0)
    elseif addr <= 0xFE9F then
        return u8(self.oam[addr - 0xFE00] or 0)
    elseif addr <= 0xFEFF then
        return 0xFF
    elseif addr == 0xFF00 then
        return self.joypad
    elseif addr == 0xFF04 then
        return self.div
    elseif addr == 0xFF05 then
        return self.tima
    elseif addr == 0xFF06 then
        return self.tma
    elseif addr == 0xFF07 then
        return self.tac
    elseif addr == 0xFF0F then
        return self.iflag
    elseif addr == 0xFF40 then
        return self.lcdc
    elseif addr == 0xFF41 then
        return self.stat
    elseif addr == 0xFF44 then
        return self.ly
    elseif addr == 0xFF45 then
        return self.lyc
    elseif addr == 0xFF47 then
        return self.bgp
    elseif addr == 0xFF48 then
        return self.obp0
    elseif addr == 0xFF49 then
        return self.obp1
    elseif addr == 0xFF4A then
        return self.wy
    elseif addr == 0xFF4B then
        return self.wx
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        return u8(self.hram[addr - 0xFF80] or 0)
    elseif addr == 0xFFFF then
        return self.ie
    end

    return 0xFF
end

function Bus:write8(addr, value)
    addr, value = u16(addr), u8(value)

    if addr >= 0x8000 and addr <= 0x9FFF then
        self.vram[addr - 0x8000] = value
    elseif addr >= 0xC000 and addr <= 0xDFFF then
        self.wram[addr - 0xC000] = value
    elseif addr >= 0xE000 and addr <= 0xFDFF then
        self.wram[addr - 0xE000] = value
    elseif addr >= 0xFE00 and addr <= 0xFE9F then
        self.oam[addr - 0xFE00] = value
    elseif addr == 0xFF00 then
        self.joypad = value
    elseif addr == 0xFF04 then
        self.div = 0
    elseif addr == 0xFF05 then
        self.tima = value
    elseif addr == 0xFF06 then
        self.tma = value
    elseif addr == 0xFF07 then
        self.tac = value & 0x07
    elseif addr == 0xFF0F then
        self.iflag = value | 0xE0
    elseif addr == 0xFF40 then
        self.lcdc = value
    elseif addr == 0xFF41 then
        self.stat = (value & 0x78) | 0x80
    elseif addr == 0xFF45 then
        self.lyc = value
    elseif addr == 0xFF47 then
        self.bgp = value
    elseif addr == 0xFF48 then
        self.obp0 = value
    elseif addr == 0xFF49 then
        self.obp1 = value
    elseif addr == 0xFF4A then
        self.wy = value
    elseif addr == 0xFF4B then
        self.wx = value
    elseif addr >= 0xFF80 and addr <= 0xFFFE then
        self.hram[addr - 0xFF80] = value
    elseif addr == 0xFFFF then
        self.ie = value
    end
end

function Bus:tick(cycles)
    -- Basic timer progression. A complete emulator should use the exact
    -- TAC-selected frequency and handle overflow/reload timing.
    local divTicks = math.floor(cycles / 256)
    self.div = u8(self.div + divTicks)

    if (self.tac & 0x04) ~= 0 then
        local period
        local mode = self.tac & 0x03
        if mode == 0 then period = 1024
        elseif mode == 1 then period = 16
        elseif mode == 2 then period = 64
        else period = 256 end

        local increments = math.floor(cycles / period)
        for _ = 1, increments do
            self.tima = u8(self.tima + 1)
            if self.tima == 0 then
                self.tima = self.tma
                self.iflag = self.iflag | 0x04
            end
        end
    end
end

return Bus
