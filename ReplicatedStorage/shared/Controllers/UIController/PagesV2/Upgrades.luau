--[[
	Upgrades page, V2 - THE DEALERSHIP UPGRADES SCREEN  (client)
	------------------------------------------------------------
	The billboard's kit face, lifted off the forecourt into a ScreenGui (2026-10-14) and opened from
	the `Upgrades` cabinet on your plot (`UpgradeConfig.Machine`). Same four tiles, same art, same
	names, so it is DRAWN BY THE SAME CODE as the billboard: `Modules/UpgradeBoardFace`, which this
	page and `UpgradeService` share. Two copies of "what a tile says at level N" would drift.

	WHAT IS DIFFERENT FROM THE BILLBOARD is only where the data comes from. The server draws a
	billboard from the profile; this draws from the levels the server already replicates on the
	player (`UpgradeConfig.Attribute`), and redraws when that attribute or the world unlocks change.
	A press fires `RequestUpgrade` through `UpgradeController.requestUpgrade` and NOTHING HERE
	PREDICTS: the tile changes when the attribute does, i.e. when the server has taken the money.
	An unaffordable press is still a press, and the server answers it with a cash pack offer.

	The page frame carries no `BoardStyle` attribute, so it is discovered as the kit face explicitly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shard = require(ReplicatedStorage.Packages.Shard)
local UpgradeConfig = require(ReplicatedStorage.shared.Configs.UpgradeConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)
local UpgradeBoardFace = require(ReplicatedStorage.shared.Modules.UpgradeBoardFace)
local KitPage = require(script.Parent.Parent.KitPage)

local Page = KitPage.extend(UpgradeConfig.Machine.PageName)

function Page.initialize(self)
	KitPage.scaleTextCaps(self.PageUI)
	self.Player = (self.UIController and self.UIController.Player) or Players.LocalPlayer

	--- A page whose grid is missing is a page that draws nothing; the warning names it.
	self._face = UpgradeBoardFace.discover(self.PageUI, true, function(message: string)
		warn("[Upgrades page] " .. message)
	end)
	if not self._face then
		return
	end

	for key, tile in self._face.tiles do
		local button = tile.button
		if button then
			--- The hover, sound and press every other screen button has (`Components/Button`).
			self:tagButton(button)
			button.Activated:Connect(function()
				local controller = Shard.get("UpgradeController")
				if controller then
					controller:requestUpgrade(key)
				end
			end)
		end
	end

	for _, attribute in { UpgradeConfig.Attribute, WorldConfig.UnlockAttribute } do
		self.Player:GetAttributeChangedSignal(attribute):Connect(function()
			self:_repaint()
		end)
	end
	self:_repaint()
end

--- Every tile, from the replicated levels. Cheap: a decode and a few text writes.
function Page:_repaint()
	if not self._face then
		return
	end
	local upgrades = UpgradeConfig.decode(self.Player:GetAttribute(UpgradeConfig.Attribute))
	UpgradeBoardFace.draw(self._face, self.Player, upgrades)
end

function Page:StartOpenThread()
	self:_repaint()
end

function Page:StartCloseThread() end

return Page
