--!strict
-- Client entry point and (from Phase 3) the screen router.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage.Shared.Version)

print(`[270] client up: v{Version.VERSION} ({Version.PHASE})`)
