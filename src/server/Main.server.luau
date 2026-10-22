--!strict
-- Server entry point. Phase 0: proves the Rojo tree wires up and shared code loads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage.Shared.Version)
local Config = require(ReplicatedStorage.Shared.Sim.Config)

print(`[270] server up: v{Version.VERSION} ({Version.PHASE}), {Config.WEEKS} weeks`)
