--!strict
-- The eight generic campaign issues and nine map regions, in display order.
-- Generic on purpose: no real-world policy positions attach to any of them.

local Types = require("../Types")

local Issues = {}

Issues.list = table.freeze({
	"Jobs",
	"Health",
	"Schools",
	"Environment",
	"Safety",
	"Transit",
	"Technology",
	"Farms",
} :: { Types.Issue })

Issues.displayName = table.freeze({
	Jobs = "Jobs",
	Health = "Health",
	Schools = "Schools",
	Environment = "Environment",
	Safety = "Safety",
	Transit = "Roads & Transit",
	Technology = "Technology",
	Farms = "Farms & Rural",
} :: { [Types.Issue]: string })

Issues.regions = table.freeze({
	"NewEngland",
	"MidAtlantic",
	"GreatLakes",
	"Plains",
	"SouthAtlantic",
	"DeepSouth",
	"SouthCentral",
	"Mountain",
	"Pacific",
} :: { Types.Region })

Issues.regionName = table.freeze({
	NewEngland = "New England",
	MidAtlantic = "Mid-Atlantic",
	GreatLakes = "Great Lakes",
	Plains = "Plains",
	SouthAtlantic = "South Atlantic",
	DeepSouth = "Deep South",
	SouthCentral = "South Central",
	Mountain = "Mountain",
	Pacific = "Pacific",
} :: { [Types.Region]: string })

local isIssue: { [string]: boolean } = {}
for _, issue in Issues.list do
	isIssue[issue] = true
end

function Issues.isIssue(value: string): boolean
	return isIssue[value] == true
end

return table.freeze(Issues)
