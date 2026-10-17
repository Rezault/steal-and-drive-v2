--[[
	CarInfoTag  (shared, built on the server)
	-----------------------------------------
	The little sign over a car you are HOLDING or have PARKED (2026-10-14, the owner: "it's a bit
	unintuitive how we're comparing car values; when you hold a car show a billboard with cash/s and its
	rarity, and the same over a car on a bay"): its name, its rarity word in the rarity's colour, and what
	it is WORTH.

	VALUE, NOT CASH/S (same day, the owner: "the $X/s is misleading"). The first cut printed one
	customer's tip income a second, which was true and read as wrong: the lot's real income depends on
	how many customers are in, so the tags never added up to the HUD's +$/hr. The car's market value
	(`GarageService.marketValueOf`: condition and parts included) is the number buyers' offers and the
	sell lot are measured against, so it is the one a player can act on, and tips scale with it anyway.

	Plain instances only (no kit shelf), so it can be built on the server, where every visitor sees it.
	`GarageConfig.InfoTag.Enabled = false`: no tags anywhere.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)

local CarInfoTag = {}

CarInfoTag.NAME = "CarInfoTag"
local INK = Color3.fromRGB(5, 25, 43)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")

local function line(parent: Instance, y: number, h: number, text: string, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, h)
	label.FontFace = FONT
	label.TextScaled = true
	label.Text = (string.gsub(text, " ", "\u{00A0}"))
	label.TextColor3 = colour
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Parent = parent
	return label
end

--[[ A tag for `body` (painted `paint`) worth `value`, hung `lift` studs over `parent` at `size` studs.
	Parent it to a part of the car so it goes when the car does. Nil when switched off. ]]
function CarInfoTag.build(parent: BasePart, body: string, paint: number?, value: number, lift: number, size: Vector2): BillboardGui?
	local cfg = GarageConfig.InfoTag
	if not (cfg and cfg.Enabled) then
		return nil
	end
	local word, colour = CarRarity.labelOf(body)
	local gui = Instance.new("BillboardGui")
	gui.Name = CarInfoTag.NAME
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	gui.MaxDistance = cfg.MaxDistance
	gui.LightInfluence = 0
	line(gui, 0, 0.4, string.upper(GarageConfig.carName(body, paint)), Color3.new(1, 1, 1))
	line(gui, 0.4, 0.28, string.upper(word), colour)
	line(gui, 0.68, 0.32, string.format(cfg.ValueFormat, GarageConfig.formatCash(math.floor(value + 0.5))), Color3.fromRGB(110, 235, 120))
	gui.Parent = parent
	return gui
end

return CarInfoTag
