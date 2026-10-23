--!strict
-- What the game sells on Roblox (D-055). Not gameplay numbers, so not in
-- Sim/Config: nothing here changes a rule. The server checks ownership
-- (server/PassService) and tells each client what it may show (the lobby
-- status's `colorPass`); Sim only ever sees the color a player ends up with.
--
-- Left unfrozen on purpose: the headless specs set COLOR_PASS_ID on a test
-- server (FakeRoblox.setColorPass). Game code only reads it.

local Products = {}

-- The "Pick Your Color" pass (permanent): its owners choose their color from
-- the six. 0 = not set up yet: the color option is hidden everywhere and every
-- match deals red and blue. THE DESIGNERS FILL THIS IN after creating the pass
-- (Creator Dashboard > Monetization > Passes; the pass's ⋯ menu > Copy Asset
-- ID gives the number; docs/TESTING.md, "Setting up the Color Pass").
Products.COLOR_PASS_ID = 0

return Products
