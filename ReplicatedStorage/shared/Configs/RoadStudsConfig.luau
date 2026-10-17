--[[
	RoadStudsConfig
	---------------
	THE SWITCH for the stud texture on the RACE ROAD. Off, and the surface you drive on (the deck,
	its lane paint and the shoulders between the guardrails) renders flat, the way it looks for a
	moment when you spawn into a race before the textures have loaded. On, and it renders exactly as
	authored. Nothing else changes either way: the lobby, the plots, the sidewalks, verges and
	buildings beside the race road all keep their studs.

	=== WHERE THE LOOK COMES FROM ==============================================================

	Not from the parts' art. Every race tile wears the `2022 Universal` MaterialVariant, which is the
	stud and inlet texture, and a part picks its variant by NAME through `BasePart.MaterialVariant`.
	So `RoadService` re-points the road parts, and only those, at a flat twin named
	`<variant><FlatSuffix>` before it publishes the tiles. Every client clones the tiles it was
	published, so the whole race picks it up with nothing to do on the client.

	The twin is the textured variant with every texture map cleared, so its BaseMaterial and physics
	are identical. That matters: the road is Glacier, so clearing the variant name instead would
	render Glacier's ice art, and switching the part's Material would change how the cars grip.

	THE TWIN IS BUILT IN STUDIO, NOT AT RUNTIME. A variant's texture maps are PluginSecurity, so a
	game script cannot blank them. The `BuildFlatMaterials` Command Runner command builds one twin
	per name in `Variants` straight into MaterialService. Re-run it after adding a name, or after a
	map import replaces a variant. A road part whose twin is missing keeps its studs and the server
	warns once.

	IT IS READ ONCE, AT SERVER BOOT. Flipping it means changing the value and starting a new server.
	Studio's edit view always shows the authored studs.
]]

local RoadStudsConfig = {}

--[[ THE FLAG. False is the flat road. True brings the stud texture back on the race road. ]]
RoadStudsConfig.RoadStuds = false

--[[ The textured variants `BuildFlatMaterials` makes a flat twin of. The race tiles only wear
	`2022 Universal`; a road part wearing anything else is left alone if it has no twin. ]]
RoadStudsConfig.Variants = {
	"2022 Universal",
}

--- Appended to a variant's name to name its flat twin in MaterialService.
RoadStudsConfig.FlatSuffix = " Flat"

--[[ WHICH PARTS ARE "THE ROAD". Only parts in these buckets of a tile (see NormalizeRoadSegments'
	`Segment` module for what goes in each), and of those only the flat slabs lying at deck height
	that reach into the corridor between the guardrails. That keeps the deck, the lane paint and the
	shoulders, and leaves out the kerbs (5 studs tall), the verge terrain and the pavement past the
	rails, all of which share the `RoadSurface` bucket. ]]
RoadStudsConfig.Buckets = { "RoadSurface", "LaneLines" }

--- Tallest a part can be, in studs, and still count as road rather than a kerb or a bank.
RoadStudsConfig.MaxThickness = 2

--- How far a road part's top face may sit below and above the deck (the tile pivot's Y), in studs.
RoadStudsConfig.TopBelowDeck = 1
RoadStudsConfig.TopAboveDeck = 1.5

return RoadStudsConfig
