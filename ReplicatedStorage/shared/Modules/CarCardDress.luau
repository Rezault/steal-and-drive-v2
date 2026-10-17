--[[
	CarCardDress  (client)
	----------------------
	The kit car card's identity, shared by the cars inventory (`PagesV2/Dealership`) and the select
	car screen (`PagesV2/StartCar`), which stamp the same `CarCard` template.

	=== ALEAFO'S CARD — 2026-10-14 ===============================================================

	WAS: every card the kit's gold face, the rarity word over the picture and the car's name under
	it, and a mutation written in front of the rarity ("SOAKED COMMON"). Aleafo, on the inventory:
	"it still looks kinda bad. I would do icon, and maybe swap it so that car name on top and rarity
	below; the rarity should = different background colour". IS:
	  * the FACE is the rarity's kit gradient (`ArcadeKit.rarityFace`: grey, green, cyan, purple,
	    gold), so rarity reads across the whole grid at a glance;
	  * the NAME is on top and the RARITY under the picture, in white (a rarity-coloured word on a
	    face of the same colour would vanish);
	  * a MUTATION is its weather's glyph in the card's corner (`WeatherConfig.iconOf` of the
	    mutation's `Event`, the badge the world screen and the road already wear), not a word. It is
	    also what marks Soaked and Charged, whose looks a viewport cannot draw.
	A card with no body (the inventory's LEAVE EMPTY) is left exactly as the kit drew it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local ArcadeKit = require(ReplicatedStorage.shared.Modules.ArcadeKit)
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)

local CarCardDress = {}

--- Set on a face once its two lines have been swapped, so a repaint never swaps them back.
local SWAPPED = "IdentitySwapped"
--- The mutation glyph, as fractions of the face: top left, under the name, clear of the star.
local GLYPH_NAME = "MutationGlyph"
local GLYPH_AT = UDim2.fromScale(0.05, 0.25)
local GLYPH_SIZE = 0.26

--[[ Dress one card (header). `title` and `rarity` are the face's two labels, already written by the
	page; this moves them, recolours the face and the rarity word, and shows or hides the glyph.
	Safe to call again on the same card. ]]
function CarCardDress.apply(face: Instance?, title: Instance?, rarity: Instance?, body: string?, mutation: string?)
	if not (face and face:IsA("GuiObject") and body) then
		return
	end
	local _, band = CarRarity.of(body)
	ArcadeKit.paint(face, ArcadeKit.rarityFace(band))

	if title and rarity and title:IsA("GuiObject") and rarity:IsA("GuiObject") and not face:GetAttribute(SWAPPED) then
		face:SetAttribute(SWAPPED, true)
		title.Position, rarity.Position = rarity.Position, title.Position
	end
	if rarity and rarity:IsA("TextLabel") then
		rarity.TextColor3 = Color3.new(1, 1, 1)
		local tint = rarity:FindFirstChild("Tint")
		if tint and tint:IsA("UIGradient") then
			tint.Enabled = false
		end
	end

	local mutated = mutation and WeatherConfig.mutationOf(mutation)
	local icon = mutated and WeatherConfig.iconOf(mutated.Event)
	local glyph = face:FindFirstChild(GLYPH_NAME)
	if not icon then
		if glyph then
			glyph:Destroy()
		end
		return
	end
	if not (glyph and glyph:IsA("ImageLabel")) then
		local made = Instance.new("ImageLabel")
		made.Name = GLYPH_NAME
		made.BackgroundTransparency = 1
		made.ScaleType = Enum.ScaleType.Fit
		made.Position = GLYPH_AT
		made.Size = UDim2.fromScale(GLYPH_SIZE, GLYPH_SIZE)
		made.ZIndex = (if title and title:IsA("GuiObject") then title.ZIndex else face.ZIndex) + 1
		local square = Instance.new("UIAspectRatioConstraint")
		square.DominantAxis = Enum.DominantAxis.Height
		square.Parent = made
		made.Parent = face
		glyph = made
	end
	(glyph :: ImageLabel).Image = UIAssets.url(icon)
end

return CarCardDress
