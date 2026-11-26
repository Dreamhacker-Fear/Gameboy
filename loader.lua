-- Game Boy Roblox bootstrap/test loader
-- Fetches the CPU and bus modules directly from this repository.
-- Requires a Luau environment with HttpGet + loadstring.

local BASE = "https://raw.githubusercontent.com/Dreamhacker-Fear/Gameboy/main/"

local function fetch(name)
    local ok, result = pcall(function()
        return game:HttpGet(BASE .. name)
    end)
    assert(ok, "HTTP failed for " .. name .. ": " .. tostring(result))
    assert(type(result) == "string" and #result > 0, "Empty response for " .. name)
    return result
end

local function loadModule(name)
    local source = fetch(name)
    local fn, err = loadstring(source)
    assert(fn, "Compile error in " .. name .. ": " .. tostring(err))
    local ok, result = pcall(fn)
    assert(ok, "Runtime error in " .. name .. ": " .. tostring(result))
    return result
end

local CPU = loadModule("gb_stage1_cpu.lua")
local Bus = loadModule("gb_stage2.lua")

local passed, failed = 0, 0

local function ok(name, condition, detail)
    if condition then
        passed = passed + 1
        print("PASS  " .. name)
    else
        failed = failed + 1
        print("FAIL  " .. name .. (detail and (" :: " .. detail) or ""))
    end
end

local function newCPU()
    local bus = Bus.new()
    local cpu = CPU.new(bus)
    return cpu, bus
end

local function loadProgram(bus, bytes)
    local rom = {}
    for i = 0, 0xFF do rom[i + 1] = 0x00 end
    for i, byte in ipairs(bytes) do rom[0x100 + i] = byte end
    bus:loadROM(rom)
end

do
    local cpu = newCPU()
    ok("register init", cpu.a == 0x01 and cpu.f == 0xB0 and cpu.b == 0 and
        cpu.c == 0x13 and cpu.d == 0 and cpu.e == 0xD8 and
        cpu.h == 0x01 and cpu.l == 0x4D and cpu.sp == 0xFFFE and cpu.pc == 0x0100)
end

do
    local _, bus = newCPU()
    bus:write8(0xC000, 0x42)
    ok("WRAM read/write", bus:read8(0xC000) == 0x42)
    bus:write8(0xFF80, 0x99)
    ok("HRAM read/write", bus:read8(0xFF80) == 0x99)
    bus:write8(0x8000, 0x55)
    ok("VRAM read/write", bus:read8(0x8000) == 0x55)
end

do
    local cpu, bus = newCPU()
    loadProgram(bus, {0x3E, 0x42, 0x06, 0x11, 0x0E, 0x22})
    cpu:step(); cpu:step(); cpu:step()
    ok("LD immediate", cpu.a == 0x42 and cpu.b == 0x11 and cpu.c == 0x22)
end

do
    local cpu, bus = newCPU()
    loadProgram(bus, {0x3E, 0x10, 0x06, 0x05, 0x80})
    cpu:step(); cpu:step(); cpu:step()
    ok("ADD A,B", cpu.a == 0x15 and not cpu:flag(0x80) and not cpu:flag(0x40))
end

do
    local cpu, bus = newCPU()
    loadProgram(bus, {0x3E, 0x10, 0x06, 0x05, 0x90})
    cpu:step(); cpu:step(); cpu:step()
    ok("SUB B", cpu.a == 0x0B and cpu:flag(0x40))
end

do
    local cpu, bus = newCPU()
    loadProgram(bus, {0xC3, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3E, 0x77})
    cpu:step()
    ok("JP nn", cpu.pc == 0x0108)
    cpu:step()
    ok("jump target executes", cpu.a == 0x77)
end

do
    local cpu, bus = newCPU()
    loadProgram(bus, {0xCD, 0x06, 0x01, 0x00, 0x00, 0x00, 0x3E, 0x55, 0xC9})
    cpu:step()
    ok("CALL pushes return", cpu.sp == 0xFFFC and bus:read8(0xFFFC) == 0x03)
    cpu:step()
    ok("CALL target", cpu.a == 0x55)
    cpu:step()
    ok("RET restores PC", cpu.pc == 0x0103 and cpu.sp == 0xFFFE)
end

do
    local cpu, bus = newCPU()
    cpu:setBC(0x1234)
    loadProgram(bus, {0xC5, 0x01, 0x00, 0xC1})
    cpu:step()
    cpu:setBC(0)
    cpu:step()
    cpu:step()
    ok("PUSH/POP BC", cpu:getBC() == 0x1234 and cpu.sp == 0xFFFE)
end

do
    local cpu, bus = newCPU()
    loadProgram(bus, {0x76, 0x3E, 0x99})
    cpu:step()
    local pc = cpu.pc
    cpu:step()
    ok("HALT", cpu.halted and cpu.pc == pc)
end

do
    local bus = Bus.new()
    bus.tac = 0x05
    bus.tima = 0xFE
    bus.tma = 0xA0
    bus:tick(32)
    ok("timer increment", bus.tima == 0x00)
    ok("timer interrupt flag", (bus.iflag & 0x04) ~= 0)
end

print(string.format("\nCPU/BUS TESTS: %d passed, %d failed", passed, failed))
return failed == 0
