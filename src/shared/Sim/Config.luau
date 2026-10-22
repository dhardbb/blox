--!strict
-- Every gameplay tunable lives here, one line comment each.
-- Phase 0 stub: the full table from docs/PLAN.md "Starting tunables" lands in Phase 1.
-- Change a value only with a matching line in docs/DESIGN.md.

local Config = {
	WEEKS = 12, -- campaign length; debates at weeks 4 and 9
}

return table.freeze(Config)
