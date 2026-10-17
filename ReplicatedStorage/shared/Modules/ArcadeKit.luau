--[[
	ArcadeKit  (shared, client-side in practice)
	--------------------------------------------
	The kit's ARCADE CARD for the small screens built in code: the daily reward days, NEW CAR
	DISCOVERED, the rare-car banner, the sale tag, the upgrade banner and "While you were driving".

	IT BUILDS, IT DOES NOT ANIMATE OR DECIDE. Every function returns the instances it made and the
	caller places, shows and tweens them.

	=== THE KIT'S OWN PARTS, NOT AN IMITATION, 2026-10-12 =======================================

	WAS: a hand-made copy of the kit (a flat gradient, a 12-cell checker of white Frames across the
	top, pixel strokes), which read as a different game beside the kit pages (Dylan, after a playtest:
	"the UIs that are made in code are just... something off. Maybe it's the slice or the checkers").
	IS: `BuildArcadeKitV2` puts the kit's real parts on the `MainUIV2.Screens` shelf (its header lists
	them) and this clones them. The checker is the kit's texture under its dark tint with the sunray
	over it, and the rims are the kit's two ScaledSize strokes, white inside navy, which hold their
	weight at any size, BillboardGuis included.

	A place without the shelf (the old UI, or `BuildArcadeKitV2` not run) gets the old hand-made
	recipe from `card`, so every caller still draws something; the other builders fall back to plain
	instances in the same layout.

	=== THE CHECKER AND THE SUNRAY ARE FITTED, NOT SCALED ========================================

	Both are `ScaleType.Fit` squares sized in fractions of the card they sit in, so cloning them onto
	a card of another shape letterboxes them (see the kit-panel-dress memory). The kit's own numbers
	reduce to two rules, measured off its day card and its double-width day 7:

	    checker   a square `CHECKER` card-heights wide, or the card's width if that is more
	    sunray    a square of `SUNRAY_H` heights or `SUNRAY_W` widths, whichever is more

	so a caller passes the card's own aspect (pixels wide per pixel high) and `fit` does the rest, all
	in scale, which is what a BillboardGui needs.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local UIAssets = require(ReplicatedStorage.shared.Configs.UIAssets)
local NewUIConfig = require(ReplicatedStorage.shared.Configs.NewUIConfig)
local UIRoot = require(ReplicatedStorage.shared.Modules.UIRoot)

local ArcadeKit = {}

--- The kit's outline navy, on every rim and every outlined word.
ArcadeKit.Navy = Color3.fromRGB(2, 30, 56)
ArcadeKit.Ink = ArcadeKit.Navy
ArcadeKit.White = Color3.new(1, 1, 1)
ArcadeKit.CashGreen = Color3.fromRGB(20, 150, 40)
ArcadeKit.Gold = Color3.fromRGB(255, 205, 50)
ArcadeKit.FaceTop = Color3.fromRGB(33, 222, 255)
ArcadeKit.FaceBottom = Color3.fromRGB(12, 91, 235)

--- The kit's card faces, top to bottom, exactly as its day cards and buttons ship them.
ArcadeKit.Faces = {
	Cyan = { Color3.fromRGB(5, 255, 242), Color3.fromRGB(44, 93, 255) },
	Blue = { Color3.fromRGB(59, 235, 255), Color3.fromRGB(19, 93, 253) },
	Purple = { Color3.fromRGB(255, 97, 239), Color3.fromRGB(125, 18, 207) },
	Gold = { Color3.fromRGB(255, 234, 5), Color3.fromRGB(255, 100, 44) },
	Pink = { Color3.fromRGB(255, 97, 202), Color3.fromRGB(207, 18, 182) },
	Red = { Color3.fromRGB(251, 0, 255), Color3.fromRGB(217, 8, 12) },
	Green = { Color3.fromRGB(255, 217, 0), Color3.fromRGB(17, 211, 6) },
	Grey = { Color3.fromRGB(187, 192, 192), Color3.fromRGB(114, 114, 114) },
}

--[[ A rarity band's face: the kit gradient nearest the band's own colour (`CarRarity.Colours`:
	grey, green, blue, purple, gold), so a card says how rare the car is in the kit's own vivid
	palette rather than in the Index's pastel one. ]]
ArcadeKit.RarityFaces = { "Grey", "Green", "Cyan", "Purple", "Gold" }

function ArcadeKit.rarityFace(band: unknown): { Color3 }
	local index = if type(band) == "number" then math.clamp(math.floor(band), 1, #ArcadeKit.RarityFaces) else 1
	return ArcadeKit.Faces[ArcadeKit.RarityFaces[index]]
end

--- The kit's fitted squares (header). Card heights for the checker; heights or widths for the sunray.
local CHECKER = 5.445
local SUNRAY_H = 1.345
local SUNRAY_W = 1.18
--- The kit's outline on type, as a share of the type's size.
local TEXT_STROKE = 0.11
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

local shelfFolder: Instance? = nil
local shelfLooked = false

--[[ The shelf, looked up once. In a running client that is `PlayerGui.MainUIV2.Screens.ArcadeKit`;
	in edit mode (a probe, where Studio still has a LocalPlayer) it is StarterGui's copy. Nil when the
	place has none.

	IT WAITS FOR THE UI, HOWEVER LONG THAT TAKES (2026-10-12). The StarterGui copies only reach
	PlayerGui when the character first spawns, which the join screen holds back for as long as its
	preload runs, so a ten-second wait at a controller's `start` ran out and every card fell back to the
	old drawing. `UIRoot.wait` answers with whichever UI this client runs as soon as it lands, and the
	shelf is a child of it, so the old UI gets its answer (no shelf) at the same moment. Callers build
	in a spawned thread for exactly this reason. ]]
function ArcadeKit.shelf(): Instance?
	if shelfLooked then
		return shelfFolder
	end
	local root: Instance? = nil
	local player = Players.LocalPlayer
	if player and RunService:IsRunning() then
		root = UIRoot.wait(player:WaitForChild("PlayerGui") :: PlayerGui)
	else
		root = StarterGui:FindFirstChild(NewUIConfig.ScreenGuiName)
	end
	local screens = if root and root.Name == NewUIConfig.ScreenGuiName then root:FindFirstChild("Screens") else nil
	--- Marked looked only once answered, so callers that arrive while the UI is still on its way all
	--- wait for it rather than the second one taking an early "none".
	shelfFolder = if screens then screens:FindFirstChild("ArcadeKit") else nil
	if not shelfLooked and screens and not shelfFolder then
		warn("[ArcadeKit] No MainUIV2.Screens.ArcadeKit (run BuildArcadeKitV2); drawing the old cards.")
	end
	shelfLooked = true
	return shelfFolder
end

--- A fresh copy of one shelf part, or nil.
function ArcadeKit.clone(name: string): GuiObject?
	local shelf = ArcadeKit.shelf()
	local part = shelf and shelf:FindFirstChild(name)
	return if part then part:Clone() :: GuiObject else nil
end

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(radius, 0)
	item.Parent = parent
end
ArcadeKit.corner = corner

--- A navy stroke in pixels. Only the fallback cards use it; kit parts carry their own rims.
function ArcadeKit.stroke(parent: Instance, thickness: number, border: boolean?): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = ArcadeKit.Navy
	line.Thickness = thickness
	line.ApplyStrokeMode = if border then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual
	line.Parent = parent
	return line
end

--- The kit's type outline: navy, ScaledSize, so it keeps its weight at every size and distance.
function ArcadeKit.outline(label: TextLabel, share: number?): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = ArcadeKit.Navy
	line.Thickness = share or TEXT_STROKE
	line.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	line.LineJoinMode = Enum.LineJoinMode.Miter
	line.Parent = label
	return line
end

--- FredokaOne, scaled to its box, outlined the kit's way unless `outline` is false or 0.
function ArcadeKit.text(parent: Instance, x: number, y: number, w: number, h: number, colour: Color3, outline: (number | boolean)?): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromScale(x, y)
	label.Size = UDim2.fromScale(w, h)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextColor3 = colour
	label.TextScaled = true
	label.ZIndex = 4
	label.Parent = parent
	if outline and outline ~= 0 then
		ArcadeKit.outline(label)
	end
	return label
end

--- The kit's gold heading (its day card's "Day 1"): white type under the gold gradient, outlined.
function ArcadeKit.heading(parent: Instance, x: number, y: number, w: number, h: number): TextLabel
	local label = ArcadeKit.clone("Heading") :: TextLabel?
	if not label then
		label = ArcadeKit.text(parent, x, y, w, h, ArcadeKit.Gold, true)
		return label :: TextLabel
	end
	label.AnchorPoint = Vector2.zero
	label.Position = UDim2.fromScale(x, y)
	label.Size = UDim2.fromScale(w, h)
	label.TextScaled = true
	label.ZIndex = 4
	label.Parent = parent
	return label
end

--- An uploaded image, `h` tall, its width held to `aspect`.
function ArcadeKit.icon(parent: Instance, image: number, x: number, y: number, h: number, aspect: number): ImageLabel
	local item = Instance.new("ImageLabel")
	item.Position = UDim2.fromScale(x, y)
	item.Size = UDim2.fromScale(h, h)
	item.BackgroundTransparency = 1
	item.Image = UIAssets.url(image)
	item.ScaleType = Enum.ScaleType.Fit
	item.ZIndex = 4
	item.Parent = parent
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = aspect
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = item
	return item
end

--- Recolour a card or button: its own gradient, top to bottom.
function ArcadeKit.paint(face: Instance, colours: { Color3 })
	local gradient = face:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(colours[1], colours[2])
	end
end

--[[ Size a card's checker and sunray for its own shape (header). `aspect` is the card's pixels wide
	per pixel high; `sunrayX` moves the sunray's centre (a share of the card's width). ]]
function ArcadeKit.fit(face: Instance, aspect: number, sunrayX: number?)
	local bg = face:FindFirstChild("BG")
	if not bg then
		return
	end
	local checker = bg:FindFirstChild("CheckersBG") :: GuiObject?
	if checker then
		local side = math.max(CHECKER, aspect * 1.02)
		checker.Size = UDim2.fromScale(side / aspect, side)
	end
	local sunray = bg:FindFirstChild("Sunray") :: GuiObject?
	if sunray then
		local side = math.max(SUNRAY_H, SUNRAY_W * aspect)
		sunray.Position = UDim2.fromScale(sunrayX or 0.5, 0.5)
		sunray.Size = UDim2.fromScale(side / aspect, side)
	end
end

--- Call `apply(aspect)` with the holder's shape now and whenever it changes.
function ArcadeKit.track(holder: GuiObject, apply: (number) -> ())
	local last = 0
	local function update()
		local size = holder.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			local aspect = size.X / size.Y
			if math.abs(aspect - last) > 0.005 then
				last = aspect
				apply(aspect)
			end
		end
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

--[[ The old hand-made card, kept for a place with no shelf: shadow, gradient face with a navy
	outline, a faint Frame checker across the top. ]]
local function fallbackCard(holder: GuiObject, colours: { Color3 }): Frame
	local shadow = Instance.new("Frame")
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(3, 4)
	shadow.BackgroundColor3 = ArcadeKit.Navy
	shadow.BackgroundTransparency = 0.45
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	shadow.Parent = holder
	corner(shadow, 0.14)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = ArcadeKit.White
	face.BorderSizePixel = 0
	face.ZIndex = 2
	face.ClipsDescendants = true
	face.Parent = holder
	corner(face, 0.14)
	ArcadeKit.stroke(face, 3, true)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(colours[1], colours[2])
	gradient.Parent = face

	for row = 0, 1 do
		for col = 0, 11 do
			if (row + col) % 2 == 0 then
				local cell = Instance.new("Frame")
				cell.Position = UDim2.fromScale(col / 12, row * 0.16)
				cell.Size = UDim2.fromScale(1 / 12, 0.16)
				cell.BackgroundColor3 = ArcadeKit.White
				cell.BackgroundTransparency = 0.9
				cell.BorderSizePixel = 0
				cell.ZIndex = 3
				cell.Parent = face
			end
		end
	end
	return face
end

export type CardOptions = {
	--- The card's pixels wide per pixel high. Default: read off the holder, and again whenever it
	--- resizes (a card sized in offset or against the screen changes shape with the window).
	aspect: number?,
	--- Top and bottom of the face. Default: the kit's cyan day card.
	face: { Color3 }?,
	--- False hides the sunray. Default: shown.
	sunray: boolean?,
	--- False hides the checker pattern. Default: shown.
	checker: boolean?,
	--- Where the sunray centres, a share of the card's width. Default: the middle.
	sunrayX: number?,
	--- Corner radius as a share of the card's short side. Default: the kit's 0.06.
	corner: number?,
}

--[[ The kit's day card, filling `holder` (a transparent frame the caller sizes and places). Returns
	the face, which everything else goes on; put content at ZIndex 2 or above so it draws over the
	checker. ]]
function ArcadeKit.card(holder: GuiObject, options: CardOptions?): GuiObject
	local opts: CardOptions = options or {}
	local colours = opts.face or ArcadeKit.Faces.Cyan
	local face = ArcadeKit.clone("Card")
	if not face then
		return fallbackCard(holder, colours)
	end
	face.Name = "Face"
	face.AnchorPoint = Vector2.zero
	face.Position = UDim2.fromScale(0, 0)
	face.Size = UDim2.fromScale(1, 1)
	ArcadeKit.paint(face, colours)
	if opts.corner then
		local round = face:FindFirstChildOfClass("UICorner")
		if round then
			--- UICorner scale is a share of the SHORT side's half, close enough to read as one radius.
			round.CornerRadius = UDim.new(opts.corner, 0)
		end
	end
	if opts.aspect then
		ArcadeKit.fit(face, opts.aspect, opts.sunrayX)
	else
		ArcadeKit.track(holder, function(aspect)
			ArcadeKit.fit(face, aspect, opts.sunrayX)
		end)
	end
	if opts.sunray == false then
		local sunray = face:FindFirstChild("BG") and face.BG:FindFirstChild("Sunray")
		if sunray then
			sunray:Destroy()
		end
	end
	if opts.checker == false then
		local checker = face:FindFirstChild("BG") and face.BG:FindFirstChild("CheckersBG")
		if checker then
			checker:Destroy()
		end
	end
	face.Parent = holder
	return face
end

--[[ The kit's prompt panel filling `holder`: returns the panel, its header title and its white
	body. `headerShare` is how much of the height the header strip takes; the body takes the rest,
	inside the kit's margins. `aspect` (pixels wide per pixel high) is read off the holder, and again
	on every resize, when it is not given. ]]
function ArcadeKit.panel(holder: GuiObject, headerShare: number?, aspect: number?): (GuiObject, TextLabel, GuiObject)
	local panel = ArcadeKit.clone("Panel")
	local header = headerShare or 0.3
	if not panel then
		local face = fallbackCard(holder, ArcadeKit.Faces.Blue)
		local title = ArcadeKit.text(face, 0.04, 0.03, 0.92, header - 0.06, ArcadeKit.White, true)
		title.TextXAlignment = Enum.TextXAlignment.Left
		local body = Instance.new("Frame")
		body.Position = UDim2.fromScale(0.025, header)
		body.Size = UDim2.fromScale(0.95, 1 - header - 0.05)
		body.BackgroundColor3 = ArcadeKit.White
		body.ZIndex = 3
		body.Parent = face
		corner(body, 0.08)
		ArcadeKit.stroke(body, 2.5, true)
		return face, title, body
	end
	panel.AnchorPoint = Vector2.zero
	panel.Position = UDim2.fromScale(0, 0)
	panel.Size = UDim2.fromScale(1, 1)
	local bg = panel:FindFirstChild("BG")
	local sunray = bg and bg:FindFirstChild("Sunray")
	if sunray then
		sunray:Destroy()
	end
	local checker = bg and bg:FindFirstChild("CheckersBG") :: GuiObject?
	local strip = panel:FindFirstChild("Header") :: GuiObject?
	local title = strip and strip:FindFirstChild("Title") :: TextLabel?
	local body = panel:FindFirstChild("Main") :: GuiObject
	if title then
		title.TextScaled = true
		title.Size = UDim2.fromScale(1, 0.8)
	end

	--[[ The kit's frame round the body is the same thickness on the left, right and bottom: a share
		of the panel's HEIGHT (measured off PromptUI), turned into a width share by the aspect. The
		panel's checker is its own lighter weave, a square `PANEL_CHECKER` heights wide. ]]
	local MARGIN = 0.053
	local PANEL_CHECKER = 4.26
	local function layout(shape: number)
		local marginX = MARGIN / shape
		if strip then
			strip.AnchorPoint = Vector2.new(0.5, 0.5)
			strip.Position = UDim2.fromScale(0.5, (header + MARGIN * 0.4) / 2)
			strip.Size = UDim2.fromScale(1 - marginX * 2.6, header - MARGIN * 0.8)
		end
		body.AnchorPoint = Vector2.new(0.5, 1)
		body.Position = UDim2.fromScale(0.5, 1 - MARGIN)
		body.Size = UDim2.fromScale(1 - marginX * 2, 1 - header - MARGIN)
		if checker then
			local side = math.max(PANEL_CHECKER, shape * 1.02)
			checker.Size = UDim2.fromScale(side / shape, side)
		end
	end
	if aspect then
		layout(aspect)
	else
		ArcadeKit.track(holder, layout)
	end
	panel.Parent = holder
	return panel, title :: TextLabel, body
end

--[[ One of the kit's buttons ("Claim" green, "Decline" red, "Disabled" grey), placed in `parent`.
	Returns the button and its caption. It is NOT wired: the caller decides what a press does. ]]
function ArcadeKit.button(parent: Instance, kind: string, x: number, y: number, w: number, h: number): (GuiObject, TextLabel)
	local button = ArcadeKit.clone(kind)
	if not button then
		local fallback = Instance.new("TextButton")
		fallback.Text = ""
		fallback.AutoButtonColor = false
		fallback.BackgroundColor3 = ArcadeKit.White
		corner(fallback, 0.3)
		ArcadeKit.stroke(fallback, 2.5, true)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(table.unpack(ArcadeKit.Faces[kind == "Decline" and "Red" or kind == "Disabled" and "Grey" or "Green"]))
		gradient.Parent = fallback
		local caption = ArcadeKit.text(fallback, 0.05, 0.19, 0.9, 0.62, ArcadeKit.White, true)
		caption.Name = "Title"
		button = fallback
	end
	local b = button :: GuiObject
	b.AnchorPoint = Vector2.zero
	b.Position = UDim2.fromScale(x, y)
	b.Size = UDim2.fromScale(w, h)
	b.ZIndex = 5
	for _, item in b:GetDescendants() do
		if item:IsA("GuiObject") then
			item.ZIndex = math.max(item.ZIndex, 5)
		end
	end
	b.Parent = parent
	local caption = b:FindFirstChild("Title") :: TextLabel
	caption.TextScaled = true
	caption.ZIndex = 7
	return b, caption
end

--[[ The kit's progress bar (grey track, blue fill, both rims), placed in `parent`. Returns the bar
	and its fill; set the fill's X scale to the ratio. ]]
function ArcadeKit.bar(parent: Instance, x: number, y: number, w: number, h: number): (GuiObject, GuiObject)
	local bar = ArcadeKit.clone("ProgressBar")
	if not bar then
		local track = Instance.new("Frame")
		track.BackgroundColor3 = Color3.fromRGB(150, 155, 160)
		corner(track, 0.5)
		ArcadeKit.stroke(track, 2, true)
		local fill = Instance.new("Frame")
		fill.Name = "Progress"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.fromScale(0, 0.5)
		fill.Size = UDim2.fromScale(0.5, 1)
		fill.BackgroundColor3 = ArcadeKit.FaceBottom
		fill.Parent = track
		corner(fill, 0.5)
		bar = track
	end
	local b = bar :: GuiObject
	b.AnchorPoint = Vector2.zero
	b.Position = UDim2.fromScale(x, y)
	b.Size = UDim2.fromScale(w, h)
	b.ZIndex = 4
	b.Parent = parent
	local fill = b:FindFirstChild("Progress") :: GuiObject
	fill.ZIndex = 5
	return b, fill
end

--[[ Fade everything under `root` out (or back in with `to` = 0) over `seconds`, after `delay`: type,
	images, frames that draw, rims and the CanvasGroups the kit keeps its checker in. Things that were
	never drawn (a transparent holder) stay as they were. ]]
function ArcadeKit.fade(root: Instance, seconds: number, delay: number?, to: number?)
	local TweenService = game:GetService("TweenService")
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0)
	local target = to or 1
	for _, item in { root, table.unpack(root:GetDescendants()) } do
		local goal = {}
		if item:IsA("CanvasGroup") then
			goal.GroupTransparency = target
		elseif item:IsA("GuiObject") and item.BackgroundTransparency < 1 then
			goal.BackgroundTransparency = target
		end
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			goal.TextTransparency = target
		elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
			goal.ImageTransparency = target
		elseif item:IsA("UIStroke") then
			goal.Transparency = target
		end
		if next(goal) then
			TweenService:Create(item, info, goal):Play()
		end
	end
end

return ArcadeKit
