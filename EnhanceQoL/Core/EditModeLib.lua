local _, addon = ...

-- Shim to expose LibEditModeImproved to the addon namespace
local LibStub = _G.LibStub
assert(LibStub, "EnhanceQoL requires LibStub to load LibEditModeImproved")

local lib = LibStub("LibEditModeImproved-1.0")
addon.EditModeLib = lib
