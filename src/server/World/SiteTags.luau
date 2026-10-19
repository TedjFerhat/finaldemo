--[[
	SiteTags
	Marks a part as an interactive search/excavation site. DiscoveryService
	and ExcavationService find these by CollectionService tag.
]]

local CollectionService = game:GetService("CollectionService")

local SiteTags = {}

local counter = 0

export type SiteOptions = {
	MinTool: number?,
	DisplayName: string?,
	Id: string?,
	Fragile: boolean?, -- excavation: favour fragile finds
	Heavy: boolean?, -- excavation: needs a pick
	Special: string?, -- handled by PuzzleService (e.g. sanctum stones)
}

function SiteTags.Register(part: BasePart, siteType: string, zoneId: string, options: SiteOptions?): string
	counter += 1
	local opts: SiteOptions = options or {}
	local id = opts.Id or ("%s_%s_%d"):format(zoneId, siteType, counter)
	part.Name = "Site"
	part:SetAttribute("SiteId", id)
	part:SetAttribute("SiteType", siteType)
	part:SetAttribute("ZoneId", zoneId)
	part:SetAttribute("MinTool", opts.MinTool or 1)
	if opts.DisplayName then
		part:SetAttribute("DisplayName", opts.DisplayName)
	end
	if opts.Fragile then
		part:SetAttribute("Fragile", true)
	end
	if opts.Heavy then
		part:SetAttribute("Heavy", true)
	end
	if opts.Special then
		part:SetAttribute("Special", opts.Special)
	end
	CollectionService:AddTag(part, if siteType == "DigSite" then "ExcavationSite" else "SearchSite")
	return id
end

-- Readable inscription (journal clue). PuzzleService wires up the prompt.
function SiteTags.Inscription(part: BasePart, clueId: string, title: string, text: string)
	part:SetAttribute("ClueId", clueId)
	part:SetAttribute("ClueTitle", title)
	part:SetAttribute("ClueText", text)
	CollectionService:AddTag(part, "Inscription")
end

return SiteTags
