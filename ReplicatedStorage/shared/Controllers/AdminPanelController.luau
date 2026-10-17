--[[
	AdminPanelController
	--------------------
	In-game admin/debug panel built on Iris, toggled with F2. Functionality ported from
	Meteor's panel (tab registration via :addTab(), the Home tab, the first-open refresh),
	styled like slay-a-baddie's: sizeClear global config for bigger click targets and a
	button-row tab strip instead of Iris.TabBar.

	Non-admins never get the panel: :start() bails before Iris boots, so there's no render loop.
	This UI is a convenience front-end only — anything privileged a tab triggers must go through a
	server-validated remote; the Admins gate here is not a trust point. The Weather tab is the worked
	example: it asks WeatherService for an event and that service re-checks Admins.isAdmin itself,
	because the thing on the other end of that button multiplies a payout.

	The tabs:
	  Home     — who you are, FPS/ping/memory, your position, reset character.
	  Camera   — seven whole camera shots on buttons, every value behind them on a live slider, and a
	             report that turns a session of dragging back into lines to paste into CameraConfig.
	             The same presets are one row on the settings screen; this is that plus the rack.
	  Weather  — what weather is running in each world, force/stop/roll one, put a sky up outside a
	             race, switch between the library and the original weather particles, and the
	             mutation table with the chances and multipliers.
	  Police   — force a chase, hold its bar still so it can be looked at, and end it either way.
	  Pickups  — put a health or nitro pack in somebody's slot, and move the HP bar under the
	             health pack's auto-use line, which is the only way to watch that rule fire; and
	             switch the nitro flame between the library look and the original.
	  Cars     — grant a car, or a whole world's ladder, to yourself or anyone in the server, in a
	             chosen colour and mutation; and, under the collapsed section at the foot of the tab,
	             park a stock unpainted copy of one in front of yourself to hold a repaint against.
	  Maps     — unlock a world (or lock it back) and move somebody into it, so its obstacle
	             course can be driven without paying for the world or finishing the road before it.
	  Obstacles— drive ONE hazard, laid at a fixed distance and repeated, instead of the seeded
	             ramp: pick the world, pick the thing, press Drive.
	  Money    — put cash on a balance, take it off, or set it to a number; and post cash to a player
	             who is not in this server, by username or user id.
	  Products — the random-car card: show it, hide it, press it, and bank the pulls, lives and
	             offline boosts the three Robux products grant, without a receipt.
	  Showroom — send a buyer now (any rating), make offers run out, clear them; pretend a player was
	             away for N minutes and get the real welcome-back screen; set the condition of the
	             cars on the lot.
	  Tutorial   replay the onboarding from beat 1 on the save you have, or wipe your own save and
	             rejoin as a brand-new player. Both work on a live server.

	Two remotes, not one: WeatherConfig.AdminEvent for the weather schedule and Admins.Event for
	everything that is a grant. AdminService's header says where the line between them is.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Shard = require(ReplicatedStorage.Packages.Shard)
local Iris = require(ReplicatedStorage.shared.Libraries.iris)
local Admins = require(ReplicatedStorage.shared.Configs.Admins)
--- For the Showroom tab's rating list, read off the bands rather than typed, so a band added there
--- turns up here.
local BuyerConfig = require(ReplicatedStorage.shared.Configs.BuyerConfig)
--- For the Camera tab: the preset list and the field rack, plus the path walking both the sliders
--- and the report are written in. `CameraTuningController` owns every write.
local CameraTuningConfig = require(ReplicatedStorage.shared.Configs.CameraTuningConfig)
local CarMutation = require(ReplicatedStorage.shared.Modules.CarMutation)
--- For the Showroom tab's new-best preview: the roster grouped by rarity, as the garage colours it.
local CarRarity = require(ReplicatedStorage.shared.Modules.CarRarity)
local GarageConfig = require(ReplicatedStorage.shared.Configs.GarageConfig)
local NitroConfig = require(ReplicatedStorage.shared.Configs.NitroConfig)
local ObstacleConfig = require(ReplicatedStorage.shared.Configs.ObstacleConfig)
--- For the Obstacles tab's lists: which kinds and courses a map's ramp actually names, derived
--- from the ramp rather than declared, so a course added to a pool turns up here on its own.
local ObstacleLayout = require(ReplicatedStorage.shared.Modules.ObstacleLayout)
local PaintConfig = require(ReplicatedStorage.shared.Configs.PaintConfig)
local PassConfig = require(ReplicatedStorage.shared.Configs.PassConfig)
local PickupConfig = require(ReplicatedStorage.shared.Configs.PickupConfig)
local PoliceConfig = require(ReplicatedStorage.shared.Configs.PoliceConfig)
local RandomCarConfig = require(ReplicatedStorage.shared.Configs.RandomCarConfig)
local SellerConfig = require(ReplicatedStorage.shared.Configs.SellerConfig)
local TutorialConfig = require(ReplicatedStorage.shared.Configs.TutorialConfig)
local WeatherConfig = require(ReplicatedStorage.shared.Configs.WeatherConfig)
local WorldConfig = require(ReplicatedStorage.shared.Configs.WorldConfig)

local TOGGLE_KEY = Enum.KeyCode.F2
local FPS_SAMPLES = 90 -- rolling window for the Home tab's FPS graph
--- Pixels the tab strip slides per mouse-wheel notch. A bit over one tab, so a notch is a step
--- rather than a jump. See `_scrollTabStrip`.
local TAB_WHEEL_PIXELS = 90

--[[ Bounds on the Weather tab's duration slider, in seconds. `WeatherService.ADMIN_DURATION` holds
	the same pair and is the one that decides — this is the slider, not the rule. ]]
local WEATHER_SECONDS = { 10, 900 }

--[[ The most of anything the Products tab's slider will ask for. `AdminService`'s own MAX_COUNT holds the
	same number and is the one that decides — this is the slider, not the rule. ]]
local GRANT_MAX = 25

--[[ Bounds on the Money tab's amount box, and the one-press amounts under it. `AdminService.MAX_CASH`
	holds the same ceiling and is the one that decides — this is the box, not the rule. ]]
local CASH_MAX = 1e12
local CASH_QUICK = { 1e3, 1e4, 1e5, 1e6 }

--- The tag `CustomerService.placeBuyer` puts on every buyer rig; the Showroom tab lists them off it.
--- Spelled here for `BuyerController`'s reason: a client cannot require the server service.
local BUYER_TAG = "Buyer"

local OK_COLOR = Color3.fromRGB(126, 214, 142)
local BAD_COLOR = Color3.fromRGB(236, 122, 122)
local DIM_COLOR = Color3.fromRGB(168, 176, 190)

local AdminPanelController = Shard.new("AdminPanelController")
AdminPanelController.tabs = {}

--[[ The panel's two lines to the server, both directions — `WeatherConfig.AdminEvent` for the
	weather schedule, `Admins.Event` for every grant. Declared here rather than in the tabs because
	`withRemoteEvents` binds at require time and the tabs are registered in `start`.

	Bound for EVERY client, including the ones that will never open the panel: the module is required
	by the controller bootstrapper regardless of who is playing, and only `start` gates on admin. The
	cost is one remote handler that the server never fires at them. ]]
AdminPanelController:withRemoteEvents({
	{
		[WeatherConfig.AdminEvent] = function(ok: unknown, message: unknown)
			AdminPanelController._weatherReply = { ok = ok == true, message = tostring(message) }
		end,
		[Admins.Event] = function(ok: unknown, message: unknown)
			AdminPanelController._adminReply = { ok = ok == true, message = tostring(message) }
		end,
	},
})

-- Safe to call unconditionally: for a non-admin the tab is stored but never rendered, since
-- Iris never boots. `render` runs every frame inside the Iris connect loop — it must never
-- yield mid-cycle (task.spawn anything that does) or Iris desyncs its Begin/End stack.
function AdminPanelController.addTab(self, name: string, render: () -> ())
	table.insert(self.tabs, { name = name, render = render })
end

--[[ Tab strip as a SameLine row of buttons, active tab tinted with the ButtonActive colors, in a
	strip that scrolls sideways once there are more tabs than fit — see `_scrollTabStrip`.

	Push unconditionally with different values per tab: conditional Push/Pop shifts Iris's
	auto-generated widget IDs (immediate-mode quirk), which makes the Button widgets lose
	identity and stop tracking state changes. ]]
function AdminPanelController._renderTabBar(self)
	local row = Iris.SameLine()
	for index, tab in self.tabs do
		local isActive = self.selectedTab:get() == index
		Iris.PushConfig({
			ButtonColor = isActive and Iris._config.ButtonActiveColor or Iris._config.ButtonColor,
			ButtonTransparency = isActive and Iris._config.ButtonActiveTransparency
				or Iris._config.ButtonTransparency,
			ButtonHoveredColor = isActive and Iris._config.ButtonActiveColor or Iris._config.ButtonHoveredColor,
			ButtonHoveredTransparency = isActive and Iris._config.ButtonActiveTransparency
				or Iris._config.ButtonHoveredTransparency,
		})
		local button = Iris.Button({ tab.name })
		--[[ Ordered by hand, because otherwise clicking a tab sends it to the END of the strip. The
			config pushed above differs for the active tab, and a CHANGED PushConfig raises Iris's
			refresh counter, which discards that widget and rebuilds it (`Internal._Insert`). A rebuilt
			button is a new instance parented last, and the SameLine sorts on LayoutOrder, which Iris
			writes only when a widget's ZIndex actually moves. One property write per tab per frame
			pins the strip to the registration order instead. ]]
		if button.Instance then
			button.Instance.LayoutOrder = index
		end
		if button.clicked() then
			self.selectedTab:set(index)
		end
		Iris.PopConfig()
	end
	Iris.End()

	self:_scrollTabStrip(row)
end

--[[ Put the tab strip in a strip that SCROLLS sideways, so a panel with more tabs than fit is still
	a panel whose last tab can be pressed.

	IT HAS TO BE DONE BY HAND BECAUSE IRIS HAS NO SCROLLING REGION. There is a `Window` (which owns
	one, vertical, for its own content) and there is `SameLine` (a plain Frame, fixed to the window's
	width), and nothing in between — so the row's buttons simply run off the right edge and are
	clipped by the window's container. Adding a widget type to a vendored library to hold eight
	buttons is the larger change, not the smaller one.

	WHAT THIS DOES INSTEAD is take the Frame Iris built and reparent it into a `ScrollingFrame` of our
	own, once. That is safe in a specific way worth writing down: Iris sets a widget's `Parent` only
	in `Internal._GenerateWidget`, at creation, and `SameLine`'s per-frame `Update` touches nothing but
	its `UIListLayout` — so the move survives, and the two properties it does not set (`AutomaticSize`
	and `Size`, written at Generate) survive being changed too. The row is switched from "as wide as
	the window" to "as wide as its buttons", which is what gives the canvas something to scroll.

	It is re-checked every frame rather than done at startup because Iris can DISCARD AND REBUILD the
	row: a changed `PushConfig` raises the refresh counter, which is the same mechanism the comment
	above is about. A rebuilt row arrives parented back in the window, the test below sees it, and the
	wrapper is built again around the new instance.

	THE WHEEL IS OURS TOO. A `ScrollingFrame` restricted to the X axis does not scroll on the mouse
	wheel — the wheel drives `CanvasPosition.Y`, which this frame has none of — so it is bound here.
	The scrollbar itself and a touch drag work without help. ]]
function AdminPanelController._scrollTabStrip(self, row)
	local strip = row.Instance :: Frame?
	if not strip then
		return
	end

	local scroller = self._tabScroller
	if strip.Parent ~= scroller then
		-- Iris has just built (or rebuilt) the row straight into the window. Wrap the new one; the
		-- old wrapper, if there is one, is holding an instance Iris has already destroyed.
		if scroller then
			scroller:Destroy()
		end

		scroller = Instance.new("ScrollingFrame")
		scroller.Name = "AdminTabStrip"
		scroller.BackgroundTransparency = 1
		scroller.BorderSizePixel = 0
		scroller.ClipsDescendants = true
		scroller.ScrollingDirection = Enum.ScrollingDirection.X
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
		scroller.CanvasSize = UDim2.fromScale(0, 0)
		scroller.ScrollBarThickness = Iris._config.ScrollbarSize
		-- The bar takes its own strip of height rather than lying over the buttons, which is what the
		-- `+ ScrollbarSize` in the height below is paying for.
		scroller.HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		scroller.ScrollBarImageColor3 = Iris._config.ScrollbarGrabColor
		scroller.ScrollBarImageTransparency = Iris._config.ScrollbarGrabTransparency
		--[[ The same flat bar the Iris window draws, and the id is copied rather than reached for:
			`widgets.ICONS` is private to the library's widget module and is not on the public `Iris`
			table. Left as the stock rounded scrollbar it is the one part of this panel that does not
			look like the rest of it. ]]
		scroller.TopImage = "rbxassetid://83265623867126"
		scroller.MidImage = "rbxassetid://83265623867126"
		scroller.BottomImage = "rbxassetid://83265623867126"
		scroller.Parent = strip.Parent
		self._tabScroller = scroller

		-- The row must hug its buttons rather than fill the window, or the canvas is exactly as wide
		-- as the view and there is nothing to scroll.
		strip.AutomaticSize = Enum.AutomaticSize.XY
		strip.Size = UDim2.fromOffset(0, 0)
		strip.Parent = scroller

		local wheel = scroller
		scroller.InputChanged:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			-- Wheel up (+1) walks LEFT, which is the direction a vertical list moves for the same
			-- notch, so a strip and a list do not fight each other under one hand.
			wheel.CanvasPosition = Vector2.new(
				wheel.CanvasPosition.X - input.Position.Z * TAB_WHEEL_PIXELS,
				0
			)
		end)
	end

	--[[ Iris orders the window's children by `LayoutOrder`, and it is the row it writes that on — so
		the wrapper has to carry the number, or the strip sorts as a zero and lands above the title.
		Copied every frame rather than once: Iris rewrites it whenever the widget's ZIndex moves, and
		that is cheap enough to not be worth predicting. ]]
	scroller.LayoutOrder = strip.LayoutOrder
	scroller.ZIndex = strip.ZIndex

	--[[ Tall enough for the buttons plus the bar underneath them. Measured off the row rather than
		computed from the config, because the button height is text height plus padding and both move
		with the global config (`sizeClear`). AbsoluteSize is a frame behind on the first frame, which
		is what `_refreshOnFirstOpen` already exists to settle. ]]
	scroller.Size = UDim2.new(1, 0, 0, strip.AbsoluteSize.Y + Iris._config.ScrollbarSize)
end

function AdminPanelController._initHomeTab(self)
	self:addTab("Home", function()
		local localPlayer = Players.LocalPlayer
		Iris.Text({ string.format("Logged in as %s (%d)", localPlayer.Name, localPlayer.UserId) })

		Iris.SeparatorText({ "Performance" })

		local fpsValues = Iris.State(self._fpsHistory)
		fpsValues:set(self._fpsHistory, true) -- force: same table mutated in place, so push it each frame
		local peak = 60
		for _, v in self._fpsHistory do
			if v > peak then
				peak = v
			end
		end
		local maxFps = math.ceil(peak / 30) * 30
		Iris.PlotLines({ "", 64, 0, maxFps, string.format("%d FPS", self._fps or 0) }, { values = fpsValues })

		Iris.Text({ string.format("Ping: %d ms", math.floor(localPlayer:GetNetworkPing() * 1000 + 0.5)) })
		Iris.Text({ string.format("Memory: %.0f MB", Stats:GetTotalMemoryUsageMb()) })
		Iris.Text({ string.format("Instances: %d", Stats.InstanceCount) })

		Iris.SeparatorText({ "Character" })

		local character = localPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p = hrp.Position
			Iris.Text({ string.format("Position: %.1f, %.1f, %.1f", p.X, p.Y, p.Z) })
		else
			Iris.Text({ "Position: (no character)" })
		end

		Iris.SameLine()
		if Iris.Button({ "Reset character" }).clicked() then
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
		end
		if Iris.Button({ "Copy position" }).clicked() then
			if hrp then
				local p = hrp.Position
				print(string.format("[AdminPanel] Vector3.new(%g, %g, %g)", p.X, p.Y, p.Z))
			end
		end
		Iris.End()
	end)
end

--- How many preset buttons go on one row before the next one starts. Four keeps the strip inside the
--- panel at its default width without the names having to be abbreviated.
local PRESETS_PER_ROW = 4

--[[ ONE FIELD, DRAWN. A slider for a number and a checkbox for a flag, either one wired straight
	through to `CameraTuningController.setValue`, plus the field's own line of explanation under it.

	`Iris.VariableState` IS THE WHOLE WIRING, and it is worth saying why it is the right widget state
	here rather than the `Iris.State` every other tab uses. An `Iris.State` ignores its seed after the
	first frame, which is correct for a box somebody types a number into and wrong for a control that
	has to follow a value something ELSE can move: press a preset and thirteen of these sliders change
	underneath the panel. `VariableState` compares the live value against what the control is showing
	every frame and takes the live one, so a preset repaints the whole rack for free, and it calls
	back only when the control itself was moved.

	THE ID IS PUSHED RATHER THAN LEFT TO THE LINE NUMBER. Iris keys a widget on the line it was
	created from plus a per-frame counter, so a loop drawing forty-four sliders from one line gets
	them apart by their ORDER. That is stable until somebody reorders the rack or switches a field
	off, at which point every control below the change quietly inherits the state of a different one.
	Pushing the field's own key makes the identity the field rather than its position.

	The controller is fetched inside the callback and not captured, because the callback is attached
	on the first frame the control exists and would otherwise hold whatever `Shard.get` answered
	then, including nil. The same reason `Modules/SettingsRows` fetches per call. ]]
function AdminPanelController._cameraField(self, field)
	Iris.PushId(field.Key)

	if field.Kind == "boolean" then
		local state = Iris.VariableState(CameraTuningConfig.read(field) == true, function(value)
			local bench = Shard.get("CameraTuningController")
			if bench then
				bench:setValue(field.Key, value)
			end
		end)
		Iris.Checkbox({ field.Label }, { isChecked = state })
	else
		local state = Iris.VariableState(CameraTuningConfig.read(field), function(value)
			local bench = Shard.get("CameraTuningController")
			if bench then
				bench:setValue(field.Key, value)
			end
		end)
		--- Control-clicking any of these turns it into a box you can type an exact number into, which
		--- is how a value outside the slider's grain gets entered. It is still clamped to the ends.
		Iris.SliderNum({ field.Label, field.Step, field.Min, field.Max, field.Format }, { number = state })
	end

	if field.Hint then
		Iris.Text({ field.Hint, true, DIM_COLOR })
	end

	Iris.PopId()
end

--[[ THE CAMERA BENCH. Seven whole shots on buttons, every value behind them on a slider, and a
	report that turns twenty minutes of dragging back into lines that can be pasted into
	`CameraConfig`.

	WHAT IT IS FOR, in one sentence: the game has had exactly two cameras and an argument about which
	is better, and neither of us can win that argument by typing numbers into a file and waiting for
	a build. So the numbers are on screen, they are live, and the answer comes back as source.

	THE PRESETS ARE ALSO ON THE SETTINGS SCREEN, as one row, for everybody. This tab is the same seven
	presets plus the rack, and it is admin-gated because forty-four sliders is not a thing to hand a
	player. A tester gets told to try Bumper; whoever is tuning opens this.

	NOTHING HERE TOUCHES THE SERVER. Every control writes a field in the client's own `CameraConfig`
	and `RaceCameraController` reads it on the next frame, so there is no remote to validate, nothing
	lands on anybody else, and rejoining puts it all back. That is also the limit: two people in one
	playtest are looking at two different cameras, and the report is per client.

	OUT OF A RACE THERE IS NOTHING TO SEE. The race camera only owns the shot between RaceStart and
	the ride home, so the panel says which of those you are in rather than leaving a tester dragging
	sliders at a lobby the stock camera is framing. ]]
function AdminPanelController._initCameraTab(self)
	self:addTab(CameraTuningConfig.Copy.Tab, function()
		local bench = Shard.get("CameraTuningController")
		if not bench then
			Iris.Text({
				"CameraTuningController is not running, so nothing here could be written. Check the client console for a boot warning.",
				true,
				BAD_COLOR,
			})
			return
		end

		--[[ `CameraType` is the honest test and not a guess: `RaceCameraController` re-asserts
			Scriptable on every frame it owns the shot, precisely so nothing can take it back, and
			hands it over the moment a race ends. ]]
		local camera = workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			Iris.Text({
				string.format("The race camera has the shot. The lens is at %.1f degrees right now.", camera.FieldOfView),
				true,
				OK_COLOR,
			})
		else
			Iris.Text({
				"You are not in a run, so the stock Roblox camera owns the shot and none of this shows. Everything you set here stays set and lands the moment a race starts.",
				true,
				DIM_COLOR,
			})
		end

		Iris.SeparatorText({ "Shots" })

		Iris.Text({
			"A preset puts every value back to what this build ships and then writes its own over the top, so it means the same shot whatever was pressed before it. Pressing the one you are already on is how you throw away a session of dragging.",
			true,
			DIM_COLOR,
		})

		--[[ Ordered rows of buttons, the active one tinted, exactly as `_renderTabBar` does it and
			with both of the same immediate-mode rules.

			ONE: push unconditionally with different values, never conditionally, or the auto-generated
			ids shift and the buttons stop tracking their own state.

			TWO: WRITE `LayoutOrder` BY HAND, every button, every frame. Without it the row reorders
			itself the moment anything is pressed, and it is the pushed config above that does it: a
			CHANGED `PushConfig` raises Iris's refresh counter, which discards that widget and rebuilds
			it, and a rebuilt button arrives parented LAST while the SameLine sorts on `LayoutOrder`,
			which Iris only writes when a ZIndex actually moves. Seen here before the fix: pressing
			nothing at all left the row reading "Chase, Fixed, Cinematic, Default", because Default is
			the active one and so the one being rebuilt. `_renderTabBar` carries the same three lines
			for the same reason. ]]
		local presets = CameraTuningConfig.Presets
		for first = 1, #presets, PRESETS_PER_ROW do
			Iris.SameLine()
			for index = first, math.min(first + PRESETS_PER_ROW - 1, #presets) do
				local preset = presets[index]
				local isActive = bench:preset() == preset.Key
				Iris.PushConfig({
					ButtonColor = isActive and Iris._config.ButtonActiveColor or Iris._config.ButtonColor,
					ButtonTransparency = isActive and Iris._config.ButtonActiveTransparency
						or Iris._config.ButtonTransparency,
				})
				local button = Iris.Button({ preset.Name })
				if button.Instance then
					button.Instance.LayoutOrder = index
				end
				if button.clicked() then
					bench:applyPreset(preset.Key)
				end
				Iris.PopConfig()
			end
			Iris.End()
		end

		local current = CameraTuningConfig.presetFor(bench:preset())
		if current then
			Iris.Text({ current.Blurb, true, DIM_COLOR })
		end
		if bench:isEdited() then
			Iris.Text({
				string.format("Edited by hand since %s was pressed.", if current then current.Name else "the preset"),
				true,
				OK_COLOR,
			})
		end

		Iris.SeparatorText({ "Every value" })

		Iris.Text({
			"Live, every one of them. A drag lands on the next frame, so tune these with the car moving. Nothing is saved and rejoining is the reset.",
			true,
			DIM_COLOR,
		})

		--[[ One collapsed section per group. The children of a closed tree are still DECLARED every
			frame (Iris hides them rather than skipping them), so this is not the conditional-widget
			trap the tab bar warns about, and a field's state survives its section being shut. The
			shot is open on arrival because it is the one anybody opens this tab for. ]]
		for _, group in CameraTuningConfig.Groups do
			local fields = CameraTuningConfig.fieldsIn(group)
			if #fields > 0 then
				Iris.Tree({ group, false, false, group == "Shot" or group == "First person" })
				for _, field in fields do
					self:_cameraField(field)
				end
				Iris.End()
			end
		end

		Iris.SeparatorText({ "Bring it back" })

		--[[ THE POINT OF THE WHOLE TAB. Nothing on this bench is saved, so a shot found at eleven at
			night exists until the tester leaves and then does not. The report is the assignments that
			differ from what this build ships, written as the lines they would be pasted into
			`CameraConfig` as, with a header naming the preset they came out of.

			TWO WAYS OUT, because there are two people who want it. The box below can be selected and
			copied, which is what somebody sitting at the game does. The print goes to the output as
			ONE entry (a multi-line string is one row, not thirty), which is what survives a log dump
			and reaches whoever is editing the file. ]]
		local reportState = Iris.State("Press one of these and the lines land here.")

		Iris.SameLine()
		if Iris.Button({ "Show the changes" }).clicked() then
			reportState:set(bench:report(false))
		end
		if Iris.Button({ "Show everything" }).clicked() then
			reportState:set(bench:report(true))
		end
		if Iris.Button({ "Print to output" }).clicked() then
			reportState:set(bench:printReport(false))
		end
		Iris.End()

		local moved = 0
		for _, record in bench:fields() do
			if bench:isMoved(record.field.Key) then
				moved += 1
			end
		end
		Iris.Text({
			string.format("%d of %d values differ from the shipped build.", moved, #bench:fields()),
			true,
			if moved > 0 then OK_COLOR else DIM_COLOR,
		})

		--- Read-only so a stray keystroke cannot turn the report into something that was never true,
		--- and multi-line so it is one selectable block rather than a row per assignment.
		Iris.InputText({ "", "", true, true }, { text = reportState })

		if Iris.Button({ "Back to the shipped camera" }).clicked() then
			bench:reset()
			reportState:set("Everything is back to what this build ships.")
		end
	end)
end

--[[ Ask the server to change the weather. Non-yielding — `Fire` is a `FireServer` and returns at
	once — so this is safe to call straight out of the Iris render loop, which must not yield.

	The optimistic line it writes is overwritten by the server's own answer a round trip later. It is
	left in on purpose: a press that produces no reply at all (a non-admin, whose refusal is silent
	by design) then reads as "asked, never answered", which is exactly what happened. ]]
function AdminPanelController._weatherAsk(self, action: string, world: number, key: string?, seconds: number?)
	local remote = self:getRemoteEvent(WeatherConfig.AdminEvent)
	if not remote then
		self._weatherReply = { ok = false, message = "The weather remote is not bound on this client." }
		return
	end
	self._weatherReply = { ok = true, message = string.format("Asked the server to %s...", action) }
	remote:Fire(action, world, key, seconds)
end

--[[ Weather. Three things, in the order you need them to test an event:

	  1. WHAT IS RUNNING, per world, off the same Workspace attribute every other client reads.
	  2. FORCE ONE. Goes to the server and comes back as a real event — the notice, everyone
	     else's sky, and the history window a mutation claim is bounded against. There is
	     deliberately no client-side "pretend" mode: a preview that skipped the server would be
	     testing a lookalike.
	  3. SHOW IT HERE. Weather is only drawn during a race (`WeatherController._onRaceStart`), so an
	     event forced from the lobby is invisible until you start one. Staging puts the sky up where
	     you are standing, using the race's own code path.

	The mutation table at the bottom is a reference, plus one button that dresses the live traffic so
	the badge and the highlight can be looked at without waiting on a 5-20% roll. ]]
function AdminPanelController._initWeatherTab(self)
	-- Built once at registration: both configs are fixed at require time, and a combo needs arrays.
	local eventLabels, eventOfLabel = {}, {}
	for _, event in WeatherConfig.Events do
		table.insert(eventLabels, event.Name)
		eventOfLabel[event.Name] = event.Key
	end

	--[[ The combo's state holds the LABEL and not the world index, because the preview field prints
		its state with `tostring` — a state of 2 would put "2" in the box where "2 · Desert" belongs. ]]
	local worldLabels, worldOfLabel = {}, {}
	for index in WorldConfig.Worlds do
		local label = string.format("%d - %s", index, WorldConfig.displayName(index))
		table.insert(worldLabels, label)
		worldOfLabel[label] = index
	end

	self:addTab("Weather", function()
		local now = workspace:GetServerTimeNow()
		local schedule = WeatherConfig.decode(workspace:GetAttribute(WeatherConfig.Attribute))
		local myWorld = WorldConfig.resolve(Players.LocalPlayer:GetAttribute(WorldConfig.WorldAttribute))

		--[[ Constant for the session, so this is not the conditional-widget trap `_renderTabBar`
			warns about: it cannot flip between frames and shift every ID below it. ]]
		if not WeatherConfig.Enabled then
			Iris.Text({
				"WeatherConfig.Enabled is false. The server runs no schedule and refuses every button here.",
				true,
				BAD_COLOR,
			})
		end

		Iris.SeparatorText({ "Running now" })

		for _, label in worldLabels do
			local index = worldOfLabel[label]
			local entry = schedule[index]
			local left = if entry then entry.endsAt - now else 0
			local event = if entry and left > 0 then WeatherConfig.eventOf(entry.event) else nil

			Iris.SameLine()
			if Iris.SmallButton({ "Roll" }).clicked() then
				self:_weatherAsk("roll", index)
			end
			if Iris.SmallButton({ "Stop" }).clicked() then
				self:_weatherAsk("stop", index)
			end
			--[[ WHAT IS COMING, which only became printable when the schedule became arithmetic: the
				queue and the offsets are pure functions of the clock (`WeatherConfig.scheduledAt`),
				so the client can work out the next event for itself with nothing sent for it.

				Walked forward a slot at a time rather than solved, because "the next start" is the
				start of THIS slot if the world is still in its clear run-up and the start of the
				next one otherwise, and eight seconds of arithmetic is not worth a closed form. ]]
			local nextUp, nextIn = nil, nil
			for step = 0, 1 do
				local slot = WeatherConfig.slotAt(index, now) + step
				local startsAt = slot * WeatherConfig.Schedule.Period + WeatherConfig.offsetFor(index)
				if startsAt > now then
					nextUp, nextIn = WeatherConfig.queuedEvent(index, slot), startsAt - now
					break
				end
			end

			local line = if event
				then string.format(
					"%s - %s, %d:%02d left",
					label,
					event.Name,
					math.floor(left / 60),
					math.floor(left % 60)
				)
				else string.format(
					"%s - clear%s",
					label,
					if nextUp
						then string.format(
							", %s in %d:%02d",
							nextUp,
							math.floor(nextIn / 60),
							math.floor(nextIn % 60)
						)
						else ""
				)
			Iris.Text({
				if index == myWorld then line .. "   <- you" else line,
				false,
				if event then event.Color else DIM_COLOR,
			})
			Iris.End()
		end

		Iris.SeparatorText({ "Force one" })
		Iris.Text({
			"Started for real: everyone in that world gets the notice and the sky, and the window a mutation claim is checked against opens. It outranks the schedule until it expires.",
			true,
			DIM_COLOR,
		})

		local worldState = Iris.State(worldLabels[math.clamp(myWorld, 1, #worldLabels)])
		Iris.Combo({ "World" }, { index = worldState })
		for _, label in worldLabels do
			Iris.Selectable({ label, label }, { index = worldState })
		end
		Iris.End()

		local eventState = Iris.State(eventLabels[1])
		Iris.Combo({ "Event" }, { index = eventState })
		for _, label in eventLabels do
			Iris.Selectable({ label, label }, { index = eventState })
		end
		Iris.End()

		local secondsState = Iris.State(120)
		Iris.SliderNum({ "Seconds", 10, WEATHER_SECONDS[1], WEATHER_SECONDS[2] }, { number = secondsState })

		local chosenWorld = worldOfLabel[worldState:get()] or myWorld
		local chosenEvent = eventOfLabel[eventState:get()]

		Iris.SameLine()
		if Iris.Button({ "Start" }).clicked() then
			self:_weatherAsk("start", chosenWorld, chosenEvent, secondsState:get())
		end
		if Iris.Button({ "Roll random" }).clicked() then
			self:_weatherAsk("roll", chosenWorld)
		end
		if Iris.Button({ "Stop" }).clicked() then
			self:_weatherAsk("stop", chosenWorld)
		end
		Iris.End()

		-- Always drawn, never conditionally, so everything below it keeps its widget IDs.
		local reply = self._weatherReply
		Iris.Text({
			if reply then reply.message else "Nothing asked for yet.",
			true,
			if reply then (if reply.ok then OK_COLOR else BAD_COLOR) else DIM_COLOR,
		})

		Iris.SeparatorText({ "Show it here" })
		Iris.Text({
			"Weather only draws during a race. Staging puts the chosen world's sky up where you are standing, using the race's own code — a race that starts takes it back.",
			true,
			DIM_COLOR,
		})

		self._weather = self._weather or Shard.get("WeatherController")
		local weather = self._weather
		local state = if weather then weather:debugState() else nil
		local status
		if not state then
			status = "WeatherController is not running."
		elseif state.staged then
			status = string.format("Staged: %s, %s.", WorldConfig.displayName(state.world), state.event or "clear")
		elseif state.racing then
			status = string.format("Racing in %s - the sky is the race's.", WorldConfig.displayName(state.world))
		else
			status = "Nothing staged."
		end
		Iris.Text({ status, true, DIM_COLOR })

		Iris.SameLine()
		if Iris.Button({ "Stage here" }).clicked() then
			if weather and not weather:debugStage(chosenWorld) then
				self._weatherReply = { ok = false, message = "Cannot stage: a race owns the sky, or weather is switched off." }
			end
		end
		if Iris.Button({ "Unstage" }).clicked() then
			if weather then
				weather:debugUnstage()
			end
		end
		Iris.End()

		--[[ THE EVENT VFX FLAG, live. `WeatherConfig.EventVfx` written into THIS client's copy and the
			particles of whatever sky is up rebuilt, so the library look and the original can be compared
			on the same storm. The Lighting does not move. What ships is the file's value. ]]
		Iris.SeparatorText({ "Event VFX" })
		Iris.Text({
			string.format(
				"Weather particles are the %s set. This client only: the file's flag is what ships.",
				if WeatherConfig.EventVfx then "library" else "original"
			),
			true,
			DIM_COLOR,
		})
		Iris.SameLine()
		for _, choice in { "Library", "Original" } do
			if Iris.Button({ choice }).clicked() then
				WeatherConfig.EventVfx = choice == "Library"
				local rebuilt = weather ~= nil and weather:debugRefresh()
				self._weatherReply = {
					ok = true,
					message = string.format(
						"Event VFX set to %s. %s",
						string.lower(choice),
						if rebuilt
							then "Rebuilt the sky that is up."
							else "Nothing is up: stage a sky or start a race to see it."
					),
				}
			end
		end
		Iris.End()

		Iris.SeparatorText({ "Mutations" })

		for _, mutation in WeatherConfig.Mutations do
			Iris.Text({
				string.format(
					"%s - %s - %g%% under it, %g%% clear - run %s, garage %s",
					mutation.Name,
					mutation.Event,
					(mutation.EventChance or 0) * 100,
					(mutation.NaturalChance or 0) * 100,
					WeatherConfig.formatMultiplier(WeatherConfig.multiplierOf(mutation.Key)),
					WeatherConfig.formatMultiplier(WeatherConfig.valueMultiplierOf(mutation.Key))
				),
				false,
				mutation.Color,
			})
		end

		--[[ Dressing writes `rec.mutation`, which is the field a real roll writes, so a car dressed
			here and then stolen and banked makes a REAL claim — and `WeatherService.couldHaveSpawned`
			refuses it unless that event actually ran in this world. Which makes this button the way
			to test that bound as well as the way to look at the art. ]]
		Iris.Text({
			"Dressing sets the same field a real roll sets, so a car banked afterwards is a real claim - and the server still refuses it unless that event actually ran in your world.",
			true,
			DIM_COLOR,
		})

		if Iris.Button({ "Dress the traffic ahead" }).clicked() then
			self._traffic = self._traffic or Shard.get("TrafficController")
			local key = WeatherConfig.MutationOfEvent[chosenEvent]
			local cars = if self._traffic then self._traffic:getCars() else nil
			local dressed = 0
			for _, rec in cars or {} do
				if rec.model and rec.model.Parent then
					rec.mutation = key
					CarMutation.apply(rec.model, key, true)
					dressed += 1
				end
			end
			self._weatherReply = {
				ok = dressed > 0,
				message = string.format(
					"Dressed %d traffic cars as %s. (None means no race is running.)",
					dressed,
					key or "nothing"
				),
			}
		end

		--[[ THE OUTLINE TEST, live. The two flags in `WeatherConfig.Outline`, written into THIS
			client's copy of the config and then every mutated car on the road re-dressed, so the three
			states can be compared on the same cars without restarting the playtest. The server keeps
			the file's setting, so a podium or a street car only changes when the file does. ]]
		Iris.SeparatorText({ "Outline test" })
		local flags = WeatherConfig.Outline
		local mode = if flags.Hidden then "Hidden" elseif flags.Soft then "Soft" else "Full"
		Iris.Text({
			string.format(
				"Outline is %s (transparency %g). This client only: the file's flags are what ships and what the server uses.",
				mode,
				WeatherConfig.outlineTransparency()
			),
			true,
			DIM_COLOR,
		})
		Iris.SameLine()
		for _, choice in { "Full", "Soft", "Hidden" } do
			if Iris.Button({ choice }).clicked() then
				flags.Hidden = choice == "Hidden"
				flags.Soft = choice == "Soft"
				self._traffic = self._traffic or Shard.get("TrafficController")
				local redressed = 0
				for _, rec in (if self._traffic then self._traffic:getCars() else nil) or {} do
					if rec.mutation and rec.model and rec.model.Parent then
						CarMutation.apply(rec.model, rec.mutation, true)
						redressed += 1
					end
				end
				self._weatherReply = {
					ok = true,
					message = string.format("Outline set to %s. Re-dressed %d mutated traffic cars.", choice, redressed),
				}
			end
		end
		Iris.End()
	end)
end

--[[ Police. Force a chase, then hold it still and look at it.

	IT DOES NOT SIMULATE ONE. Every button here goes through `PoliceController`'s own entry points,
	so a forced chase is a chase: it rolls a duration, counts toward the repeat, peels off when it is
	survived and ends the run through `PoliceService` when it is not. Same argument as the Weather
	tab's, and the bust is the sharp end of it: "Bust me" really does end the run, with the real
	banner, the real results headline and the real revive offer behind it.

	THE ONE EXCEPTION IS "SHOW THE BUSTED SCREEN", and it is the exception on purpose. Reaching a
	real arrest costs a race, a chase and the driving in between; the SCREEN it ends on is a
	four-second beat that wants looking at over and over while it is tuned. That button draws that
	screen and nothing else — no arrest, no payout, no chase — through `RaceUIController`. Its note
	on the tab says so, because a button next to "Bust me" that quietly did less would be worse than
	no button.

	THIS IS THE ONLY WAY TO SEE ONE IN THREE OF THE FOUR WORLDS. The road arms a chase off police
	art, and only the City has any; `PoliceConfig.FallbackTile` is nil, so everywhere else waits for
	a section that does not exist. Even in the City it is one tile, two thirds of the way through a
	four minute run, and then a repeat every six tiles behind a 55 second cooldown.

	HOLDING THE BAR IS THE OTHER HALF. Under the floor the bar is empty in three and a half seconds
	and full again in under two, which is the beat working and is far too fast to inspect how the
	cruisers close, what the helicopter does, or what the HUD looks like at 20%. The checkbox stops
	the drain where it is and the slider puts it anywhere.

	The hold is pushed to the controller every frame rather than on the tick, so the checkbox and the
	freeze can never drift apart, and it costs one boolean write. ]]
function AdminPanelController._initPoliceTab(self)
	self:addTab("Police", function()
		self._police = self._police or Shard.get("PoliceController")
		local police = self._police
		local state = if police then police:debugState() else nil

		--[[ Constant for the session, like the Weather tab's switch: with the feature off the server
			publishes nothing, so this is not a state the panel can flip between frames. ]]
		if not PoliceConfig.Enabled then
			Iris.Text({
				"PoliceConfig.Enabled is false. Nothing was published and no chase can arm, forced or otherwise.",
				true,
				BAD_COLOR,
			})
		end

		Iris.SeparatorText({ "Right now" })

		--[[ Three lines that are always three lines. The reason is chosen before the widget rather
			than by branching around it: a status that appeared and vanished as chases start and end
			would shift every widget ID under it, which is the immediate-mode trap `_renderTabBar`
			warns about, and this tab has state-holding widgets below. ]]
		local status, statusColor = "PoliceController is not running.", BAD_COLOR
		if state and not state.published then
			status = "No police vehicles were published, so races run without a chase. The server log says why."
		elseif state and not state.active then
			status, statusColor = "No race is running. Start a run and a chase can be forced from here.", DIM_COLOR
		elseif state and state.state == "live" then
			local grace = if state.grace > 0 then string.format(", %.1fs of grace", state.grace) else ""
			if state.stealGrace > 0 then
				grace ..= string.format(", %.1fs of steal grace", state.stealGrace)
			end
			if state.nitroCut > 0 then
				grace ..= string.format(", %.1fs cut by nitro", state.nitroCut)
			end
			status = string.format(
				"CHASE LIVE. %.0fs left, %d vehicle%s on you%s.",
				state.left,
				state.pursuers,
				if state.pursuers == 1 then "" else "s",
				grace
			)
			statusColor = OK_COLOR
		elseif state and state.state == "pit" then
			status, statusColor = "CAUGHT. A cruiser is putting you into the barrier.", BAD_COLOR
		elseif state and state.state == "leaving" then
			status, statusColor = "Survived. They are peeling off.", OK_COLOR
		elseif state then
			local when
			if state.cooldown == math.huge then
				when = "the run is ending, so nothing may arm"
			elseif state.stealCall then
				--- Above the cooldown line on purpose, because a call ignores the cooldown
				--- (`PoliceConfig.StealHeat.IgnoreCooldown`) and a panel printing the number it is
				--- about to ignore would be the wrong answer.
				when = string.format("a stolen car has been called in, %.1fs", state.stealCallIn)
			elseif state.cooldown > 0 then
				when = string.format("%.0fs of cooldown left", state.cooldown)
			else
				when = "ready to arm"
			end
			status, statusColor = string.format("Racing, no chase: %s.", when), DIM_COLOR
		end
		Iris.Text({ status, true, statusColor })

		local roadLine = "Road: no race."
		if state and state.active then
			roadLine = string.format(
				"Tile %s, %s. Chases this run: %d.",
				if state.tile then tostring(state.tile) else "?",
				if state.sectionAhead then "a police section IS in range" else "no section in range",
				state.chases
			)
		end
		Iris.Text({ roadLine, true, DIM_COLOR })

		--[[ The floor is the whole rule of the beat, so it is drawn as the comparison the chase makes
			rather than as two loose numbers: it is what the player is being marked on. A floor of
			zero is the first frames of a race, before the chassis has declared a `MaxSpeed`, and the
			chase deliberately does not drain through it. ]]
		local speedLine, speedColor = "Speed: no race.", DIM_COLOR
		if state and state.active then
			if state.floorSpeed <= 0 then
				speedLine = string.format(
					"%.0f studs/s, no floor yet: the car has not declared a top speed, so nothing drains.",
					state.speed
				)
			elseif state.speed < state.floorSpeed then
				speedLine =
					string.format("%.0f studs/s against a floor of %.0f. UNDER IT.", state.speed, state.floorSpeed)
				speedColor = BAD_COLOR
			else
				speedLine =
					string.format("%.0f studs/s against a floor of %.0f. Clear.", state.speed, state.floorSpeed)
				speedColor = OK_COLOR
			end
		end
		Iris.Text({ speedLine, true, speedColor })

		--[[ Display only, pushed from the chase every frame: the bar out of the window, the bar on the
			HUD and this one are the same number drawn three times.

			FULL WHENEVER NOTHING IS LIVE, which is a correction and not a white lie. `_bar` keeps the
			value the last chase ended on until the next arm resets it, so a survived chase leaves 93%
			sitting here with no cruisers anywhere, which reads as a chase in progress. What a bar with
			nothing draining it is worth is 1. ]]
		local live = state ~= nil and state.state ~= "off"
		local bar = if live then state.bar else 1
		local barState = Iris.State(1)
		barState:set(bar)
		Iris.ProgressBar({
			"Bar",
			if live then string.format("%d%%", math.floor(bar * 100 + 0.5)) else "no chase",
		}, { progress = barState })

		--[[ WHERE THE CARS ACTUALLY ARE, which is not the bar and has not been since the lead and the
			swoop went in. `station` is the 0..2 `PoliceController._stationValue` composes, and it is
			the only number any pursuer is placed against: this line and the window are the pair that
			have to agree. The bar above is the RULE, and it is allowed to disagree with both.

			IT IS THE LINE TO WATCH WHEN THE CHASE LOOKS WRONG. A station that is not where the eye
			says the cars are is a placement bug; a station that is exactly where they are and still
			looks wrong is a tuning question, and the two want completely different files opening. ]]
		local stationLine, stationColor = "Stations: no chase.", DIM_COLOR
		if live then
			local station = state.station or state.bar
			local read = if station >= 1.5
				then "dropping out of the corners of the frame"
				elseif station > 1.02 then "falling back"
				elseif station >= 0.98 then "the ordinary chase station"
				elseif station < state.bar - 0.02 then "in past what the bar asks: a crash swoop, or the arrival"
				else "closing"
			stationLine = string.format("Stations: %.2f of 2, %s.", station, read)
			stationColor = if station >= 0.98 then OK_COLOR else BAD_COLOR
			if state.lead > 0 then
				stationLine ..= string.format(" Lead %d%%.", math.floor(state.lead * 100 + 0.5))
			end
			if state.lineup > 0 then
				stationLine ..= string.format(
					" LINING UP %d%%: the outside cruiser has left its station to set the PIT up.",
					math.floor(state.lineup * 100 + 0.5)
				)
				stationColor = BAD_COLOR
			end
		end
		Iris.Text({ stationLine, true, stationColor })

		--[[ The other half of the rule, and the half the speed line above cannot show: a chase is
			lost far more often to two crashes in three seconds than to a slow car. The chain is what
			prices the second one, so it is printed as a countdown rather than as a count. ]]
		local strikeLine, strikeColor = "Strikes: no race.", DIM_COLOR
		if state and state.active then
			if state.chain > 0 then
				strikeLine = string.format(
					"CHAIN x%d. The next crash inside %.1fs costs %.0f%% of the bar.",
					state.chain,
					state.chainLeft,
					PoliceConfig.strikeBite(1, state.chain) * 100
				)
				strikeColor = BAD_COLOR
			else
				strikeLine = string.format(
					"No chain: the next crash costs %.0f%% at worst. A second inside %.1fs costs %.0f%%.",
					PoliceConfig.strikeBite(1, 0) * 100,
					PoliceConfig.Strikes.Chain.Window,
					PoliceConfig.strikeBite(1, 1) * 100
				)
			end
			if state.settle > 0 then
				strikeLine ..= string.format(" Refill held for %.1fs.", state.settle)
			end
		end
		Iris.Text({ strikeLine, true, strikeColor })

		Iris.SeparatorText({ "Drive it" })

		Iris.SameLine()
		if Iris.Button({ "Start a chase" }).clicked() then
			local armed = police ~= nil and police:debugArm()
			self._policeNote = {
				ok = armed,
				message = if armed
					then "Armed. They come out of the fog behind you."
					else "Nothing to arm: you are not on the road, or no vehicles were published.",
			}
		end
		if Iris.Button({ "Let them go" }).clicked() then
			local ended = police ~= nil and police:debugLose()
			self._policeNote = {
				ok = ended,
				message = if ended
					then "Peeling off, with the usual cooldown behind it."
					else "No live chase to end.",
			}
		end
		if Iris.Button({ "Bust me" }).clicked() then
			local busted = police ~= nil and police:debugBust()
			self._policeNote = {
				ok = busted,
				message = if busted
					then "Caught. A cruiser is spinning you, and the report lands when it has."
					else "No live chase, and the server refuses a bust from a client that is not in one.",
			}
		end
		Iris.End()

		--[[ ...and the one button on this tab that is not a chase at all.

			"Bust me" above is the real arrest and needs everything a real arrest needs: a live race,
			a live chase, and the road driven far enough to reach police art. This draws the SCREEN
			that arrest ends on, from anywhere, in about four seconds — which is the difference
			between looking at that beat once and looking at it twenty times while tuning it.

			IT IS NOT A MOCK-UP OF THE SCREEN, it is the screen: `debugBustScreen` sets the two facts
			a real bust arrives with and then calls the same show and hide the remotes call. Its own
			note says what it can and cannot show from the lobby. ]]
		self._raceUI = self._raceUI or Shard.get("RaceUIController")
		local raceUI = self._raceUI
		if Iris.Button({ "Show the busted screen" }).clicked() then
			self._policeNote = {
				ok = raceUI ~= nil,
				message = if raceUI and raceUI:debugBustScreen()
					then "Drawn, with stand-in numbers. The lights and the cruiser are the real ones."
					else "RaceUIController is not running, so there is no screen to draw.",
			}
		end

		--[[ ...and its twin, which is on the POLICE tab because it is the same screen.

			A bust and a wreck are one results screen in two keys: the same slot, the same bar, the
			same numbers, and three differences that were every one of them settled by flipping
			between the two (`RaceUIController`'s `THE CRUISER` and `THE WRECK` are where each is
			argued). Two buttons on two tabs would mean walking the panel between every comparison,
			which is the thing that stops anyone making it.

			It folds up a published traffic shell rather than the player's own car, because in the
			lobby there is no car and `Workspace.CarSystem` never reaches a client at all.
			`debugWreckScreen` says which parts of the shot are the real ones. ]]
		if Iris.Button({ "Show the wrecked screen" }).clicked() then
			local drawn = raceUI ~= nil and raceUI:debugWreckScreen()
			self._policeNote = {
				ok = drawn,
				message = if drawn
					then "Drawn. The fold, the light and the smoke are real; only the car is a stand-in."
					elseif raceUI == nil then "RaceUIController is not running, so there is no screen to draw."
					else "No traffic shells are published yet, so there is no car to wreck.",
			}
		end

		Iris.Text({
			"That one is the results screen on its own, not an arrest: nothing ends and nothing is paid. Out of a race there is no road under it, so the ladder bar draws as the plain divider it falls back to.",
			true,
			DIM_COLOR,
		})

		local holdState = Iris.State(false)
		Iris.Checkbox({ "Hold the bar where it is" }, { isChecked = holdState })
		if police then
			police:debugHold(holdState:get())
		end

		local percentState = Iris.State(100)
		Iris.SliderNum({ "Bar %", 5, 0, 100 }, { number = percentState })
		if Iris.Button({ "Set the bar" }).clicked() then
			if police then
				police:debugSetBar(percentState:get() / 100)
			end
			self._policeNote = {
				ok = police ~= nil,
				message = if police
					then string.format("Bar set to %d%%. The cruisers close on the next frame.", percentState:get())
					else "PoliceController is not running.",
			}
		end

		Iris.Text({
			"Hold it and the drain stops where it is, but the chase still ends on time. Set it to 0 with the hold off and the next frame arrests you, through the same test the road uses.",
			true,
			DIM_COLOR,
		})

		Iris.SeparatorText({ "Crash into things" })

		--[[ THE POINT OF THESE TWO IS PRESSING ONE OF THEM TWICE. A single strike is a wobble by
			design; what the beat is made of is the second one landing inside the window, and that is
			a thing you have to be able to do on demand rather than by finding two barriers three
			seconds apart on a live road.

			Both go through `reportStrike`, so they chain off each other and off real crashes
			indifferently: hit a cone for real and then press "a barrier" and the chain counts it. ]]
		Iris.SameLine()
		if Iris.Button({ "A graze (cone)" }).clicked() then
			local struck = police ~= nil and police:debugStrike(0.35)
			self._policeNote = {
				ok = struck,
				message = if struck
					then "Clipped. Press it again inside the window and watch the second one cost more."
					else "No live chase to be struck in.",
			}
		end
		if Iris.Button({ "A barrier" }).clicked() then
			local struck = police ~= nil and police:debugStrike(1.2)
			self._policeNote = {
				ok = struck,
				message = if struck
					then "The worst hit on the road. Two of these close together is an arrest."
					else "No live chase to be struck in.",
			}
		end
		Iris.End()

		Iris.Text({
			string.format(
				"A crash takes %.0f%% to %.0f%% of the bar, multiplied by %.1f for each one inside %.1fs of the last (up to %d deep). The bar then holds for %.1fs before it starts refilling, and a full refill takes %.1fs.",
				PoliceConfig.Strikes.Bite.Min * 100,
				PoliceConfig.Strikes.Bite.Max * 100,
				PoliceConfig.Strikes.Chain.Scale,
				PoliceConfig.Strikes.Chain.Window,
				PoliceConfig.Strikes.Chain.MaxLinks,
				PoliceConfig.Strikes.Settle,
				PoliceConfig.RefillTime
			),
			true,
			DIM_COLOR,
		})

		-- Always drawn, never conditionally, for the same reason the Weather tab's reply line is.
		local note = self._policeNote
		Iris.Text({
			if note then note.message else "Nothing pressed yet.",
			true,
			if note then (if note.ok then OK_COLOR else BAD_COLOR) else DIM_COLOR,
		})

		Iris.SeparatorText({ "How it arms by itself" })

		for map, tiles in PoliceConfig.Sections do
			Iris.Text({
				string.format("%s: tile %s carries the police art.", map, table.concat(tiles, ", ")),
				false,
				DIM_COLOR,
			})
		end
		Iris.Text({
			string.format(
				"Sirens %d studs before that tile. Then a repeat every %s tiles, %ds of cooldown after each one, and a fallback tile of %s.",
				PoliceConfig.ArmLead,
				tostring(PoliceConfig.RepeatTiles),
				PoliceConfig.Cooldown,
				if PoliceConfig.FallbackTile
					then tostring(PoliceConfig.FallbackTile)
					else "none, so a world with no marked section never arms one on its own"
			),
			true,
			DIM_COLOR,
		})

		Iris.SeparatorText({ "Tuning" })

		Iris.Text({
			string.format(
				"Floor: %d%% of what your own car cruises at. %.1fs from full to empty stopped, %.1fs back to full above the floor, %.1fs of grace at the arm and %.1fs after a landed steal.",
				PoliceConfig.Floor * 100,
				PoliceConfig.DrainTime,
				PoliceConfig.RefillTime,
				PoliceConfig.Grace,
				PoliceConfig.StealGrace
			),
			true,
			DIM_COLOR,
		})
		Iris.Text({
			string.format(
				"A chase runs %d to %ds, with %d cruiser%s and %s helicopter.",
				PoliceConfig.Duration[1],
				PoliceConfig.Duration[2],
				PoliceConfig.Cruisers.Count,
				if PoliceConfig.Cruisers.Count == 1 then "" else "s",
				if PoliceConfig.Helicopter.Enabled then "a" else "no"
			),
			true,
			DIM_COLOR,
		})
		Iris.Text({
			if PoliceConfig.Pit.Enabled
				then string.format(
					"An empty bar is a PIT: a cruiser comes off its station over %.2fs, spins you, and the bust is reported %.1fs later.",
					PoliceConfig.Pit.Approach,
					PoliceConfig.Pit.Spin
				)
				else "PoliceConfig.Pit.Enabled is false: an empty bar reports the bust on the frame it empties.",
			true,
			DIM_COLOR,
		})
	end)
end

--[[ Pickups. Put a pack in a slot, and move the HP bar so it has something to do.

	THE TWO CONTROLS ARE ONE TEST, which is why they share a tab rather than sitting next to each
	other in two. A health pack collected at full health banks and then pays nothing when it is spent,
	and the rule that makes the pack interesting — `AutoUseBelow`, banked unless you needed it — only
	fires under half a bar. So "give me a pack" is not a test of the packs on its own; "put me on 40%
	and then give me a pack" is, and the second half of that sentence is the slider.

	THE NITRO PACK'S HALF OF THAT RULE HAS NO SLIDER HERE, and cannot: it fires under a depleted tank,
	the tank is a client-owned number (`PickupConfig`'s header) and this panel talks to the server.
	Reaching it is a burn — hold nitro until the bar bottoms out, then grant a pack — which is a few
	seconds of driving rather than the wait the HP bar would have been.

	EVERYTHING IS DRIVEN OFF `PickupConfig` RATHER THAN NAMED HERE. The buttons come from
	`PickupConfig.Names` and what each one says it pays is read off the pack, so the third pack that
	file promises costs an entry there and nothing here — which is the claim its header makes, and
	this is the place that would quietly break it.

	The slot read-out is the PLAYER ATTRIBUTE (`PickupConfig.SlotAttribute`), not a reply, so it is
	live for anyone in the server rather than only after a press: the server mirrors the slot onto the
	player for the HUD, and that mirror replicates to every client. Watching somebody else collect a
	pack off the road shows up here with no remote of our own. ]]
function AdminPanelController._initPickupsTab(self)
	--[[ One line per pack saying what it is worth, built from the fields rather than written out.
		Built once: `Packs` is fixed at require time. ]]
	local payouts = {}
	--- The highest auto-use line any HEALING pack has, which is the health the slider wants to get
	--- under for the branch below it to be worth pressing. Read across the packs rather than off
	--- `Health`, so a third healing pack with a rule of its own moves this without touching it.
	local autoUse = 0
	for _, name in PickupConfig.Names do
		local pack = PickupConfig.Packs[name]
		local parts = {}
		if pack.Heal then
			table.insert(parts, string.format("heals %d%% of the car's ceiling", math.floor(pack.Heal * 100 + 0.5)))
		end
		if pack.Tank then
			table.insert(parts, string.format("fills %d%% of the nitro tank", math.floor(pack.Tank * 100 + 0.5)))
		end
		if pack.Star then
			table.insert(parts, string.format(
				"%gs invincible at %gx speed, ploughs traffic",
				pack.Star.Duration,
				pack.Star.SpeedScale
			))
		end
		if pack.AutoUseBelow > 0 then
			--- The threshold is a fraction of the pack's OWN resource, so the sentence has to name
			--- which one -- read off the payout field, the same pairing `PickupController
			--- ._wouldAutoUse` dispatches on, rather than off a list of pack names.
			table.insert(parts, string.format(
				"spends itself on contact under %d%% %s",
				math.floor(pack.AutoUseBelow * 100 + 0.5),
				if pack.Tank then "tank" else "health"
			))
		end
		--- HEALTH thresholds only: this is the number the HP slider below is aimed at, and a nitro
		--- pack's line has nothing to say about where the bar should start.
		if pack.Heal then
			autoUse = math.max(autoUse, pack.AutoUseBelow)
		end
		payouts[name] = string.format("%s: %s.", name, table.concat(parts, ", "))
	end

	--- Where the slider starts. A notch under the auto-use line, because that is the state this tab
	--- exists to reach in one press; well down the bar if nothing auto-uses, so a heal is still visible.
	local startPercent = if autoUse > 0 then math.clamp(math.floor(autoUse * 100) - 10, 5, 100) else 40

	self:addTab("Pickups", function()
		Iris.SeparatorText({ "The slot" })

		--[[ ONE SWITCH NOW. Packs used to ride the obstacle course's switch too, and this tab warned
			about both; since 2026-09-28 the pickup pass runs with the course off (`PickupConfig`'s
			dated note), so `PickupConfig.Enabled` alone decides. ]]
		if not PickupConfig.Enabled then
			Iris.Text({
				"PickupConfig.Enabled is false, so the layout places none and the HUD slot never appears.",
				true,
				BAD_COLOR,
			})
		end

		local target = self:_targetPicker()

		--[[ Who the read-out below is about. A single named player is the one being watched; "Me" and
			"Everyone" both fall back to the local player, because there is no useful one-line answer for
			a whole server and the person pressing the button is the one who wants it. ]]
		local watching = if type(target) == "number" then Players:GetPlayerByUserId(target) else nil
		watching = watching or Players.LocalPlayer

		local slot = watching:GetAttribute(PickupConfig.SlotAttribute)
		Iris.Text({
			string.format(
				"%s is carrying: %s",
				watching.Name,
				if type(slot) == "string" then slot else "nothing"
			),
			true,
			if type(slot) == "string" then OK_COLOR else DIM_COLOR,
		})

		local spendState = Iris.State(false)
		Iris.Checkbox({ "Spend it straight away instead of banking it" }, { isChecked = spendState })

		Iris.SameLine()
		for _, name in PickupConfig.Names do
			if Iris.Button({ string.format("Give %s", name) }).clicked() then
				self:_adminAsk("pickup", target, name, spendState:get())
			end
		end
		Iris.End()

		for _, name in PickupConfig.Names do
			Iris.Text({ payouts[name], true, DIM_COLOR })
		end

		Iris.Text({
			string.format(
				"A banked pack is spent with %s, or the right bumper, or by tapping the slot on a phone. It only exists during a run, so all of this refuses in the lobby.",
				PickupConfig.Hud.CapText or "Q"
			),
			true,
			DIM_COLOR,
		})

		Iris.SeparatorText({ "Car health" })

		local healthState = Iris.State(startPercent)
		Iris.SliderNum({ "Leave them on %", 5, 5, 100 }, { number = healthState })

		Iris.SameLine()
		if Iris.Button({ "Set health" }).clicked() then
			self:_adminAsk("health", target, healthState:get() / 100)
		end
		if Iris.Button({ "Repair to full" }).clicked() then
			self:_adminAsk("health", target, 1)
		end
		Iris.End()

		Iris.Text({
			if autoUse > 0
				then string.format(
					"Under %d%% a health pack spends itself on contact instead of banking, which is the half of the feature worth watching. Put it back to 100 and the same press banks.",
					math.floor(autoUse * 100 + 0.5)
				)
				else "No pack auto-uses today, so every one of them banks. Damage is still worth setting: a heal collected at full health pays nothing.",
			true,
			DIM_COLOR,
		})
		Iris.Text({
			"The drop goes through the same call a hazard uses, so a run inside its spawn shield, or one with ObstacleConfig.Invulnerable on, will refuse it. The reply says so with the HP either side.",
			true,
			DIM_COLOR,
		})

		--[[ THE NITRO FLAME FLAG, live. `NitroConfig.FlameVfx` written into THIS client's copy and the
			jets on the car you are in rebuilt, so the library flame and the original can be compared on
			the same car. What ships is the file's value. ]]
		Iris.SeparatorText({ "Nitro flame" })
		Iris.Text({
			string.format(
				"Nitro burns the %s flame. This client only: the file's flag is what ships.",
				if NitroConfig.FlameVfx then "library" else "original"
			),
			true,
			DIM_COLOR,
		})
		Iris.SameLine()
		for _, choice in { "Library", "Original" } do
			if Iris.Button({ choice }).clicked() then
				NitroConfig.FlameVfx = choice == "Library"
				local nitro = Shard.get("NitroController")
				local rebuilt = nitro ~= nil and nitro:debugRefresh()
				self._adminReply = {
					ok = true,
					message = string.format(
						"Nitro flame set to %s. %s",
						string.lower(choice),
						if rebuilt then "Rebuilt the jets on your car." else "Start a race to see it."
					),
				}
			end
		end
		Iris.End()

		self:_renderAdminReply()
	end)
end

--[[ Ask AdminService for something. Non-yielding, so it is safe out of the Iris render loop; the
	answer lands in `_adminReply` a round trip later and the tab that asked prints it.

	Nothing is ever sent as nil. "Roll me a colour" goes as the string `"random"` and "no mutation"
	as `"none"`, because a nil in the middle of a remote's arguments is a thing that works until the
	argument after it is also nil — and both of these have an argument after them. The server reads
	both by type (`type(paint) == "number"`, `WeatherConfig.sanitize`), so a string it does not
	recognise already means "you choose", with no branch of its own. ]]
function AdminPanelController._adminAsk(self, action: string, target: any, ...: any)
	local remote = self:getRemoteEvent(Admins.Event)
	if not remote then
		self._adminReply = { ok = false, message = "The admin remote is not bound on this client." }
		return
	end
	self._adminReply = { ok = true, message = string.format("Asked the server to %s...", action) }
	remote:Fire(action, target, ...)
end

--[[ The "who does this land on" combo, drawn by every tab that grants something. Returns the value
	to put on the wire — a UserId, or the string "all".

	The list is rebuilt every frame because the answer changes every time somebody joins or leaves.
	That is safe in a way that is worth knowing before writing another one of these: Iris derives a
	widget's identity from the SOURCE LINES on the call stack plus how many times that line has run
	this frame (`Internal._getID`), so a loop whose length changes reassigns identity inside the
	loop and shifts nothing after it. A player leaving mid-frame therefore costs a selection, never
	the state of the widgets below.

	A selection that names somebody who has since left resolves to `Me` rather than to nothing, so
	the button under it always has a target and never silently does nothing.

	`label` is what the combo calls itself, for a tab where "Give to" is the wrong verb. It changes
	the caption and nothing else: Iris derives the widget's identity from the call site, not from
	its text, so the selection is per tab either way. ]]
function AdminPanelController._targetPicker(self, label: string?): any
	local me = Players.LocalPlayer
	local labels = { "Me", "Everyone" }
	local valueOf = { Me = me.UserId, Everyone = "all" }
	for _, player in Players:GetPlayers() do
		if player ~= me then
			local label = string.format("%s (%d)", player.Name, player.UserId)
			table.insert(labels, label)
			valueOf[label] = player.UserId
		end
	end

	local state = Iris.State("Me")
	Iris.Combo({ label or "Give to" }, { index = state })
	for _, label in labels do
		Iris.Selectable({ label, label }, { index = state })
	end
	Iris.End()

	return valueOf[state:get()] or me.UserId
end

--- The last thing AdminService said, drawn unconditionally so it is one widget rather than a hole.
function AdminPanelController._renderAdminReply(self)
	local reply = self._adminReply
	Iris.Text({
		if reply then reply.message else "Nothing asked for yet.",
		true,
		if reply then (if reply.ok then OK_COLOR else BAD_COLOR) else DIM_COLOR,
	})
end

--[[ Cars. Put one on somebody's lot, or a whole world's ladder at once.

	IT GRANTS THROUGH `GarageService.awardCar`, which is the same call the getaway truck makes at
	the end of a run, so everything that hangs off owning a car happens here too: the free bay, the
	swap when the lot is full, the duplicate that sells itself, the catalogue tick. That is the
	reason this is worth having as a tab rather than as a DataStore edit — the outcome the server
	reports back IS the thing under test.

	The tier is not sent. `AdminService` derives it from the body, so the pair cannot disagree. ]]
function AdminPanelController._initCarsTab(self)
	--[[ Built once: the roster, the palette and the mutation list are all fixed at require time.
		The car list is per world, so it is a table of tables rather than one flat list — a single
		combo of every car in the game would be forty-odd rows to scroll for one of eight. ]]
	local worldLabels, worldOfLabel = {}, {}
	local carsOfWorld = {}
	for index in WorldConfig.Worlds do
		local label = string.format("%d - %s", index, WorldConfig.displayName(index))
		table.insert(worldLabels, label)
		worldOfLabel[label] = index

		local cars = {}
		for _, body in WorldConfig.carsFor(index) do
			table.insert(cars, { body = body, label = string.format("%s  (tier %d)", body, GarageConfig.TierOfBody[body] or 0) })
		end
		carsOfWorld[index] = cars
	end

	local paintLabels, paintOfLabel = { "Random" }, { Random = "random" }
	for index, entry in PaintConfig.Palette do
		table.insert(paintLabels, entry.Name)
		paintOfLabel[entry.Name] = index
	end

	local mutationLabels, mutationOfLabel = { "None" }, { None = "none" }
	for _, mutation in WeatherConfig.Mutations do
		table.insert(mutationLabels, mutation.Name)
		mutationOfLabel[mutation.Name] = mutation.Key
	end

	self:addTab("Cars", function()
		Iris.Text({
			"Granted through GarageService.awardCar — the same call the truck makes when a run banks. A free bay parks it, a full lot swaps its worst, and one you already own sells itself.",
			true,
			DIM_COLOR,
		})

		local target = self:_targetPicker()

		local worldState = Iris.State(worldLabels[1])
		Iris.Combo({ "World" }, { index = worldState })
		for _, label in worldLabels do
			Iris.Selectable({ label, label }, { index = worldState })
		end
		Iris.End()

		local world = worldOfLabel[worldState:get()] or 1
		local cars = carsOfWorld[world]

		--[[ Seeded from the world's first car, and re-seeded whenever the chosen world no longer has
			the selected body: an `Iris.State` ignores its seed after the first frame, so without this
			a switch from world 1 to world 2 would leave "Civic" selected and the button would grant a
			world 1 car from the world 2 page. ]]
		local carState = Iris.State(cars[1].label)
		local chosen = nil
		for _, car in cars do
			if car.label == carState:get() then
				chosen = car
			end
		end
		if not chosen then
			chosen = cars[1]
			carState:set(chosen.label)
		end

		Iris.Combo({ "Car" }, { index = carState })
		for _, car in cars do
			Iris.Selectable({ car.label, car.label }, { index = carState })
		end
		Iris.End()

		local paintState = Iris.State(paintLabels[1])
		Iris.Combo({ "Paint" }, { index = paintState })
		for _, label in paintLabels do
			Iris.Selectable({ label, label }, { index = paintState })
		end
		Iris.End()

		local mutationState = Iris.State(mutationLabels[1])
		Iris.Combo({ "Mutation" }, { index = mutationState })
		for _, label in mutationLabels do
			Iris.Selectable({ label, label }, { index = mutationState })
		end
		Iris.End()

		local paint = paintOfLabel[paintState:get()] or "random"
		local mutation = mutationOfLabel[mutationState:get()] or "none"

		Iris.SameLine()
		if Iris.Button({ "Give car" }).clicked() then
			self:_adminAsk("car", target, chosen.body, paint, mutation)
		end
		if Iris.Button({ "Give the whole ladder" }).clicked() then
			self:_adminAsk("world", target, world, paint, mutation)
		end
		Iris.End()

		--[[ The stock car, folded away. Everything above this line GRANTS; this parks something to
			look at and writes nothing, which is why it is behind an arrow rather than sitting in the
			same column as the two buttons that write to a save file.

			IT ALWAYS LANDS ON YOU, whatever the picker at the top of the tab says, and the note under
			the buttons says so — the server refuses to read a target for these two (`Untargeted`).
			Parking a car to look at is a thing you do where you are standing, and "everyone" would be
			a car in a lobby nobody asked to see.

			The tree's children are declared on every frame whether it is open or not — Iris hides
			them rather than skipping them — so this is not the conditional-widget trap
			`_renderTabBar` warns about. ]]
		Iris.Tree({ "Compare against the stock car" })
		Iris.Text({
			"Parks an UNPAINTED copy of the car picked above in front of you, and the painted one beside it, so a repaint can be held against the livery the artist drew. It is a display clone: anchored, no collision, no physics. Nothing is granted and nothing is saved.",
			true,
			DIM_COLOR,
		})

		Iris.SameLine()
		if Iris.Button({ "Stock only" }).clicked() then
			self:_adminAsk("reference", "none", chosen.body)
		end
		--- The Paint combo above feeds this one, "Random" included: the reply names whatever colour
		--- the roll landed on, so pressing it repeatedly walks the palette a car at a time.
		if Iris.Button({ "Stock + the paint above" }).clicked() then
			self:_adminAsk("reference", "none", chosen.body, paint)
		end
		if Iris.Button({ "Clear" }).clicked() then
			self:_adminAsk("clearReference", "none")
		end
		Iris.End()

		Iris.Text({
			"These three land on you and not on the pick at the top of the tab. Stock is the left-hand car and its number plate reads STOCK; the painted one keeps the plate its colour really hashes to.",
			true,
			DIM_COLOR,
		})
		Iris.End()

		self:_renderAdminReply()
	end)
end

--[[ Maps. Own a world, stand in it, and drive its obstacle course — without paying for it or
	finishing the road before it.

	THIS TAB EXISTS FOR THE OBSTACLES. A world's course set is keyed by its MAP name
	(`ObstacleConfig.TiersByMap`), and the only way onto a map is to own the world it is under and be
	standing in that world when the run starts. Owning world 4 the way a player does costs cash and
	100% of world 3's road, which is an evening's driving before a single course has been looked at.

	TWO PRESSES AND NOT ONE, because they are two different things. "Unlock" writes what the target
	OWNS (worlds 1..N, the same single number a purchase writes, saved to their profile); "Go" writes
	where they ARE, which is what decides the road the next run builds. Unlocking alone leaves the
	teleport screen offering a world nobody has walked into yet, which is exactly what wants testing
	half the time.

	UNLOCK GOES DOWN AS WELL AS UP — the row for world 1 locks everything else — so a gate can be put
	back and walked through again. Locking somebody out of the world they are standing in moves them
	down to what they still own, and `WorldService.setUnlocked` refuses to do that mid-race.

	The map column is the thing to read before pressing anything: two worlds pointed at ONE map have
	ONE obstacle set between them, so a course that needs testing is reached by any world above it. ]]
function AdminPanelController._initMapsTab(self)
	--[[ Built once — the ladder, the maps and the ramps are all fixed at require time.

		A ROW SAYS AS LITTLE AS IT CAN, because the useful reading is the exception. A world whose
		card name already IS its map name (all five today) says nothing about the map; one that shares
		a map with another world says which, because then two rows are the same obstacle set and
		either will do. And `ObstacleLayout.tiersFor` falls back to `ObstacleConfig.Tiers` for a map
		with no entry in `TiersByMap` — which is the one thing to know before driving a course
		looking for art that is not there, so that is what gets flagged rather than the normal
		case. World 1 names its own ramp now, so the fallback is nobody's authored set. ]]
	local sharers = {}
	for index = 1, #WorldConfig.Worlds do
		local map = WorldConfig.mapFor(index)
		if map then
			sharers[map] = (sharers[map] or 0) + 1
		end
	end

	local rows = {}
	for index = 1, #WorldConfig.Worlds do
		local map = WorldConfig.mapFor(index)
		local name = WorldConfig.displayName(index)
		local notes = {}
		if not map then
			table.insert(notes, "no map")
		elseif map ~= name or sharers[map] > 1 then
			table.insert(notes, map .. " map")
		end
		if not (map and ObstacleConfig.TiersByMap[map]) then
			table.insert(notes, "fallback obstacles")
		end

		table.insert(rows, {
			index = index,
			label = string.format("%d - %s", index, name),
			notes = if #notes > 0 then "  ·  " .. table.concat(notes, ", ") else "",
		})
	end

	self:addTab("Maps", function()
		Iris.Text({
			"Unlock writes what they OWN (through WorldService.setUnlocked — no price, no road finished first, saved to the profile). Go writes where they ARE, which is the map the next run builds.",
			true,
			DIM_COLOR,
		})

		--[[ Both constant for the session, so neither is the conditional-widget trap `_renderTabBar`
			warns about — and both are worth saying on the one tab whose whole job is driving into a
			course. A tab that unlocked a world whose obstacles are switched off, and said nothing,
			would read as the unlock having failed. ]]
		if not ObstacleConfig.Enabled then
			Iris.Text({
				"ObstacleConfig.Enabled is false. Every road streams empty — no world here has a course on it.",
				true,
				BAD_COLOR,
			})
		end
		if ObstacleConfig.Invulnerable then
			Iris.Text({
				"ObstacleConfig.Invulnerable is true. Hits still shove, yaw and shake; they take no HP, so no run can end in a wreck.",
				true,
				BAD_COLOR,
			})
		end

		local target = self:_targetPicker("Unlock for")

		--[[ WHOSE STATE THE ROWS DESCRIBE. Unlocks, world and cash are all replicated attributes on
			the Player, so another player in this server can be read as honestly as yourself — but
			"Everyone" is not one player and has no state to print, so it falls back to you and says
			so. The buttons still land on whoever is picked; only the reading is yours. ]]
		local watched = if type(target) == "number" then Players:GetPlayerByUserId(target) else nil
		local shown = watched or Players.LocalPlayer
		if shown ~= watched then
			Iris.Text({
				string.format("Showing %s's own state; the buttons still land on the pick above.", shown.Name),
				true,
				DIM_COLOR,
			})
		end

		Iris.SeparatorText({ "Worlds" })

		local cash = tonumber(shown:GetAttribute(GarageConfig.CashAttribute)) or 0
		local standing = WorldConfig.resolve(shown:GetAttribute(WorldConfig.WorldAttribute))

		for _, row in rows do
			Iris.SameLine()
			--- Unlock EVERYTHING UP TO HERE, which is what the stored number means (see
			--- `WorldConfig`, "Earning a world": one number, so owning 4 is owning 1-4, and world 1's
			--- row is therefore the lock).
			if Iris.SmallButton({ "Unlock" }).clicked() then
				self:_adminAsk("unlock", target, row.index)
			end
			if Iris.SmallButton({ "Go" }).clicked() then
				self:_adminAsk("visit", target, row.index)
			end

			--[[ The same call the teleport card paints itself from (`WorldConfig.unlockStateFor`), so
				a row saying "locked" here and a card offering a price there can never disagree. Read
				for the WATCHED player, whose cash is an attribute this client can already see. ]]
			local state, detail = WorldConfig.unlockStateFor(row.index, shown, cash)
			local status, color
			if state == "open" then
				status, color = "owned", OK_COLOR
			elseif state == "needs" then
				status, color = string.format(
					"needs %d%% of %s (%d%%)",
					math.floor(detail.required * 100 + 0.5),
					detail.previousShort,
					math.floor(detail.progress * 100 + 0.5)
				), DIM_COLOR
			else
				status, color = string.format(
					"locked, %s%s",
					GarageConfig.formatCash(detail.cost),
					if detail.affordable then " and can afford it" else ""
				), DIM_COLOR
			end

			Iris.Text({
				string.format(
					"%s%s  ·  %s%s",
					row.label,
					row.notes,
					status,
					if row.index == standing then "   <- here" else ""
				),
				false,
				if row.index == standing then OK_COLOR else color,
			})
			Iris.End()
		end

		Iris.Text({
			"Unlock is the whole prefix: pressing world 4 gives 1-4, pressing world 1 takes the rest back. Locking somebody out of the world they are standing in moves them down to what they still own, and is refused while they are racing.",
			true,
			DIM_COLOR,
		})

		self:_renderAdminReply()
	end)
end

--[[ One line saying what a kind DOES, built out of the fields that make it interesting rather than
	out of a written description, so a kind retuned in `ObstacleConfig` cannot end up described here
	by its old numbers.

	The order is the order a driver meets them in: what it gives you first, then what it takes, then
	what happens to the thing itself. Anything a kind does not have simply does not appear. ]]
local function describeKind(name: string): string
	local kind = ObstacleConfig.Kinds[name]
	if not kind then
		return "This build has no kind by that name."
	end

	local bits = {}
	if kind.Pickup then
		table.insert(bits, string.format("a %s pack, collected rather than hit", kind.Pickup))
	end
	if kind.Boost then
		local boost = kind.Boost
		if (boost.Speed or 0) > 0 then
			table.insert(bits, string.format("+%d studs/s along the road", boost.Speed))
		end
		if (boost.Lift or 0) > 0 then
			table.insert(bits, string.format("%d studs/s straight up", boost.Lift))
		end
		if (boost.Nitro or 0) > 0 then
			table.insert(bits, string.format("%d%% of a nitro tank", math.floor(boost.Nitro * 100 + 0.5)))
		end
	end
	if kind.Slick then
		table.insert(bits, string.format("grip down to %.2f for %.1fs", kind.Slick.Grip, kind.Slick.Duration))
	end
	if (kind.Damage or 0) > 0 then
		table.insert(bits, string.format("%d HP", kind.Damage))
	end
	if (kind.SpeedKeep or 1) < 1 then
		table.insert(bits, string.format("keeps %d%% of your speed", math.floor(kind.SpeedKeep * 100 + 0.5)))
	end
	if (kind.Yaw or 0) > 0 then
		table.insert(bits, string.format("%.2f rad/s of yaw", kind.Yaw))
	end
	if kind.Roll then
		table.insert(bits, "sweeps across the road instead of standing still")
	end
	if kind.Smash then
		table.insert(bits, if kind.Smash.Break then "breaks apart" else "tumbles away")
	end
	if kind.Pass and not (kind.Boost or kind.Pickup) then
		table.insert(bits, "you drive straight through it")
	end

	local art = if kind.Art then string.format("art %s", kind.Art.Model) else "primitives, no art"
	if #bits == 0 then
		return string.format("Does nothing at all on contact.  (%s)", art)
	end
	return string.format("%s.  (%s)", table.concat(bits, ", "), art)
end

--- ...and the same for a course, which is a shape rather than a behaviour: what is in it, how wide
--- a stretch of road it takes, and which lanes it uses.
local function describeCourse(name: string): string
	local course = ObstacleConfig.Courses[name]
	if not course then
		return "This build has no course by that name."
	end

	local counts, order = {}, {}
	local lanes = {}
	for _, item in course.Items do
		if not counts[item.Kind] then
			counts[item.Kind] = 0
			table.insert(order, item.Kind)
		end
		counts[item.Kind] += 1
		lanes[item.Lane] = true
	end

	local parts = {}
	for _, kind in order do
		table.insert(parts, if counts[kind] > 1 then string.format("%s x%d", kind, counts[kind]) else kind)
	end

	local used = {}
	for lane = 1, #ObstacleConfig.Lanes do
		if lanes[lane] then
			table.insert(used, tostring(lane))
		end
	end

	return string.format(
		"%s, over %d studs, in lane%s %s.",
		table.concat(parts, ", "),
		course.Length,
		if #used == 1 then "" else "s",
		table.concat(used, "/")
	)
end

--[[ Obstacles. Drive ONE hazard, on purpose, as many times as it takes.

	THE TAB EXISTS BECAUSE THE RAMP IS A RANDOM DRAW. A tile picks its courses out of a pool
	(`ObstacleConfig.Tiers`), so meeting a particular kind means driving until it happens to come up,
	meeting it twice in a row means driving a great deal further than that, and meeting it twice on
	the SAME line is not something the road will ever agree to. None of which matters when the
	question is "does the boom gate read from far enough out" and every one of which matters when
	the answer is no and it needs looking at again.

	WHAT IT ARMS is `ObstacleConfig.Bench`: one kind (or one authored course) laid a fixed distance
	past the spawn and repeated for the length of the road, with nothing else on the tile. It is
	otherwise an ordinary race. The same client builds it, the same server prices the hits, the same
	lane check accepts them, so what happens when the car arrives is what happens in a real run.

	IT STAYS ARMED UNTIL IT IS TURNED OFF, deliberately: a hazard is looked at over several runs, and
	re-arming after every wreck would be the panel getting in the way of the thing it is for. The
	read-out under the picker is what stops that being a trap, and it is read from the target's own
	attribute rather than remembered here, so a bench armed in a session that has since been reloaded
	still shows.

	"DRIVE IT" ENDS THE RUN YOU ARE ALREADY ON, which is what makes the tab usable one hazard at a
	time: drive into the boom gate, decide it reads too late, pick the next thing, press again. The
	run is ended the ordinary way and a fresh one is entered on the new bench, because the road under
	a live car cannot be swapped without the server and the client disagreeing about what was hit —
	so it is a new road rather than an edited one. "Arm it" is the button that leaves a live run
	alone, and is still what you want when the next run is going to be started some other way.

	THE WORLD IS PART OF THE ANSWER AND NOT A CONVENIENCE. An obstacle set belongs to a MAP, art and
	all (`ObstacleConfig.TiersByMap`), so a desert hazard benched on the city road has no model to
	build from and quietly does not appear. Picking the world is therefore picking the hazards, which
	is why the two combos are in that order, and "Drive it" unlocks that world and stands the target
	in it before entering the race. ]]
function AdminPanelController._initObstaclesTab(self)
	--[[ Built once: the ramps, the kinds and the courses are all fixed at require time.

		A group per world rather than one flat list of every kind in the game, because a kind is only
		drivable in the worlds whose ramp names it, and a combo that offered all thirty would mostly
		be offering roads that build nothing. `ObstacleLayout.kindsFor` derives the list from the ramp
		itself, so a course added to a pool puts its kinds in here with no second list to update. ]]
	local groups = {}
	local onSomeRamp = {}

	--- Two worlds pointed at one map share one obstacle set, so either of them reaches it. That is
	--- the only case where naming the map tells the reader something their own eyes do not, which
	--- is the rule the Maps tab's rows follow too.
	local sharers = {}
	for index = 1, #WorldConfig.Worlds do
		local map = WorldConfig.mapFor(index)
		if map then
			sharers[map] = (sharers[map] or 0) + 1
		end
	end

	for index = 1, #WorldConfig.Worlds do
		local map = WorldConfig.mapFor(index)

		local kinds = {}
		for name in ObstacleLayout.kindsFor(map) do
			table.insert(kinds, name)
			onSomeRamp[name] = true
		end
		table.sort(kinds)

		--- In ramp order rather than alphabetical, because that is difficulty order: the first
		--- courses in the list are the ones tile 0 can deal.
		local courses, seen = {}, {}
		for _, tier in ObstacleLayout.tiersFor(map) do
			for _, name in tier.Pool do
				if ObstacleConfig.Courses[name] and not seen[name] then
					seen[name] = true
					table.insert(courses, name)
				end
			end
		end

		local entries = {}
		for _, name in kinds do
			table.insert(entries, { label = name, kind = name })
		end
		for _, name in courses do
			table.insert(entries, { label = "course:  " .. name, course = name })
		end

		local name = WorldConfig.displayName(index)
		local note = ""
		if not map then
			note = "  (no map)"
		elseif map ~= name or sharers[map] > 1 then
			note = string.format("  (%s map)", map)
		end

		table.insert(groups, {
			label = string.format("%d - %s%s", index, name, note),
			world = index,
			entries = entries,
		})
	end

	--[[ ...and everything no ramp names, which today is the two road packs and would tomorrow be a
		kind that has been authored but not put in a course yet. Both are worth being able to drive
		into: a pack is placed by its own pass and is the one thing on the road you steer TOWARDS,
		and an unreferenced kind is exactly the thing somebody is in the middle of building.

		They run in whatever world the target is already standing in, because there is no map that
		owns them. A pack is drawn identically everywhere so that is the right answer for it; a kind
		with art in one world's folder and not another's is the case where it is a guess, and the
		note under the picker says so. ]]
	local spare = {}
	for name in ObstacleConfig.Kinds do
		if not onSomeRamp[name] then
			table.insert(spare, name)
		end
	end
	table.sort(spare)
	if #spare > 0 then
		local entries = {}
		for _, name in spare do
			table.insert(entries, { label = name, kind = name })
		end
		table.insert(groups, { label = "On no ramp  (drives where you already are)", entries = entries, loose = true })
	end

	local groupLabels = {}
	for _, group in groups do
		table.insert(groupLabels, group.label)
	end

	local defaults = ObstacleConfig.Bench

	self:addTab("Obstacles", function()
		Iris.Text({
			"One hazard, laid a fixed distance down the road and repeated, instead of the seeded ramp. Everything else about the run is a real run: the client builds it, the server prices the hits, the lane check accepts them.",
			true,
			DIM_COLOR,
		})

		--[[ Constant for the session, so neither is the conditional-widget trap `_renderTabBar`
			warns about, and both would otherwise be read as this tab having failed. ]]
		if not ObstacleConfig.Enabled then
			Iris.Text({
				"ObstacleConfig.Enabled is false. The bench is built by the same function the ramp is, so with that switch off it lays nothing either.",
				true,
				BAD_COLOR,
			})
		end
		if ObstacleConfig.Invulnerable then
			Iris.Text({
				"ObstacleConfig.Invulnerable is true, for everybody, benched or not. Hits still shove, yaw and shake; no run can end in a wreck.",
				true,
				BAD_COLOR,
			})
		end

		local target = self:_targetPicker("Bench for")

		--[[ What that target has armed RIGHT NOW, off their own attribute
			(`ObstacleConfig.Bench.Attribute`) rather than off anything this panel remembers, so it
			is honest about a bench armed before this session and about one somebody else armed.
			"Everyone" has no single answer, so it falls back to the local player and the line below
			the picker says whose state is being shown. ]]
		local watched = if type(target) == "number" then Players:GetPlayerByUserId(target) else nil
		local shown = watched or Players.LocalPlayer
		local armed = shown:GetAttribute(defaults.Attribute)
		Iris.Text({
			string.format(
				"%s: %s",
				shown.Name,
				if type(armed) == "string"
					then string.format("%s armed, and it stays armed until Off is pressed", armed)
					else "no bench, driving the real ramp"
			),
			true,
			if type(armed) == "string" then OK_COLOR else DIM_COLOR,
		})

		Iris.SeparatorText({ "What to drive into" })

		local groupState = Iris.State(groupLabels[1])
		Iris.Combo({ "World" }, { index = groupState })
		for _, label in groupLabels do
			Iris.Selectable({ label, label }, { index = groupState })
		end
		Iris.End()

		local group = groups[1]
		for _, candidate in groups do
			if candidate.label == groupState:get() then
				group = candidate
			end
		end

		--[[ Re-seeded whenever the chosen world no longer has the selected entry: an `Iris.State`
			ignores its seed after the first frame, so without this a switch from the city to the
			desert would leave "Cone" selected on a road that has no cone art to build it from. Same
			correction the Cars tab makes, for the same reason. ]]
		local entryState = Iris.State(group.entries[1] and group.entries[1].label)
		local chosen = nil
		for _, entry in group.entries do
			if entry.label == entryState:get() then
				chosen = entry
			end
		end
		if not chosen then
			chosen = group.entries[1]
			entryState:set(chosen and chosen.label)
		end

		Iris.Combo({ "Obstacle" }, { index = entryState })
		for _, entry in group.entries do
			Iris.Selectable({ entry.label, entry.label }, { index = entryState })
		end
		Iris.End()

		if not chosen then
			Iris.Text({ "This world's ramp names no obstacles at all.", true, BAD_COLOR })
			self:_renderAdminReply()
			return
		end

		Iris.Text({
			if chosen.course then describeCourse(chosen.course) else describeKind(chosen.kind),
			true,
			DIM_COLOR,
		})
		if group.loose then
			Iris.Text({
				"Nothing on this list is on a ramp, so it drives in the world the target is already in. The two packs are drawn the same everywhere and are safe anywhere; anything else here needs art in that world's folder or it will not appear.",
				true,
				DIM_COLOR,
			})
		end

		Iris.SeparatorText({ "Where to put it" })

		local leadState = Iris.State(defaults.Lead)
		Iris.SliderNum(
			{ "First one at (studs)", 20, defaults.LeadRange[1], defaults.LeadRange[2] },
			{ number = leadState }
		)
		local spacingState = Iris.State(defaults.Spacing)
		Iris.SliderNum(
			{ "Then every (studs)", 20, defaults.SpacingRange[1], defaults.SpacingRange[2] },
			{ number = spacingState }
		)

		local rowState = Iris.State(defaults.Row)
		Iris.Checkbox({ "One in every lane" }, { isChecked = rowState })
		local laneState = Iris.State(defaults.Lane)
		Iris.SliderNum({ "...or just this lane", 1, 1, #ObstacleConfig.Lanes }, { number = laneState })

		local invulnState = Iris.State(defaults.Invulnerable)
		Iris.Checkbox({ "Take no HP from it" }, { isChecked = invulnState })
		local trafficState = Iris.State(defaults.Traffic)
		Iris.Checkbox({ "Leave the traffic on" }, { isChecked = trafficState })

		--[[ One Text whose STRING changes rather than a line that appears and disappears: a widget
			that comes and goes shifts the identity of everything declared after it, which is the
			trap `_renderTabBar`'s note is about. ]]
		local note = if chosen.course
			then
				"A course brings its own lanes and its own spacing, so the two lane controls above do nothing for one. The distances still apply: they place the course, not the obstacles in it."
			else string.format(
				"Lane 3 is the middle of the road, which is where the car spawns. Cruise is about 85 studs/s, so %d studs is roughly %.1fs of driving from a standing start.",
				leadState:get(),
				leadState:get() / 85
			)
		--[[ ...and the one distance that is a trap. The spawn shield (`RaceConfig.SpawnShield`)
			drops as soon as the car is demonstrably moving plus a settle, which is timed to be over
			before the first obstacle a real run meets at `SpawnGraceStuds`. Put the bench closer
			than that and the first one can land inside the shield, cost nothing, and read as the
			hazard not working. ]]
		if leadState:get() < ObstacleConfig.SpawnGraceStuds then
			note ..= string.format(
				"  Under %d studs is inside the spawn shield's usual reach, so the first one may cost no HP.",
				ObstacleConfig.SpawnGraceStuds
			)
		end
		Iris.Text({ note, true, DIM_COLOR })

		local spec = {
			kind = chosen.kind,
			course = chosen.course,
			lane = laneState:get(),
			row = rowState:get(),
			lead = leadState:get(),
			spacing = spacingState:get(),
			invuln = invulnState:get(),
			traffic = trafficState:get(),
		}
		--- Not nil, for the reason `_adminAsk`'s note gives: it has an argument after it. The server
		--- takes anything that is not a world index as "leave them where they are".
		local world = group.world or "here"

		Iris.SameLine()
		if Iris.Button({ "Drive it" }).clicked() then
			self:_adminAsk("bench", target, spec, world, true)
		end
		if Iris.Button({ "Arm it for their next run" }).clicked() then
			self:_adminAsk("bench", target, spec, world, false)
		end
		if Iris.Button({ "Off" }).clicked() then
			self:_adminAsk("bench", target, "off", "here", false)
		end
		Iris.End()

		Iris.Text({
			"Drive it unlocks that world, stands them in it and enters a race, which is the same call the entry pad makes. Pressed mid-run it ends that run first and starts a fresh one on the new pick, so hazards can be walked through one at a time; expect a couple of seconds of black screen while it goes home and back. Arm it is the one that leaves a live run alone.",
			true,
			DIM_COLOR,
		})

		self:_renderAdminReply()
	end)
end

--[[ Money. Cash onto a balance, off it, or set to a number — and the only tab that can reach a
	player who is not in this server.

	THE LIVE HALF IS THE POINT OF DOING IT THROUGH A REMOTE at all. `GarageService.addCash` is the
	one thing in the game that writes `Cash`, and three screens repaint off that one call: the HUD
	number, the forecourt billboard, and the upgrade kiosks lighting up as a level becomes affordable.
	Pressing "Give" here drives the same path a customer's tip drives, so what happens on screen is
	the shipping behaviour rather than a debug shortcut.

	THE OFFLINE HALF posts a message against their save file and answers with what it did. It lands
	the moment they next join; if they are playing on another server right now it lands there within
	a minute, because posting nudges that server to save early.

	IN A STUDIO PLAYTEST THE OFFLINE HALF GOES NOWHERE VISIBLE. `Settings.DEBUG_MOCK` swaps the whole
	profile store for the mock, and the mock is wiped between playtests — so a post to somebody who is
	not in the playtest is a message nothing will ever read. Posting to a name that IS in the playtest
	still works, because the server hands that over directly instead. The tab says so on screen; the
	reason lives in `AdminService.Actions.cashOffline`. ]]
function AdminPanelController._initMoneyTab(self)
	self:addTab("Money", function()
		Iris.Text({
			"Granted through GarageService.addCash — the one writer. The HUD, the forecourt sign and the kiosk prices all follow it, so a press here repaints everything a real payout would.",
			true,
			DIM_COLOR,
		})

		Iris.SeparatorText({ "In this server" })

		local target = self:_targetPicker()

		--[[ Everybody's balance, straight off `GarageConfig.CashAttribute` — the same attribute the
			HUD reads, so this list is what those players are looking at rather than a second opinion.
			An absent attribute is a profile that has not arrived yet, which is worth saying out loud:
			a grant in that window is a no-op and would otherwise look like a broken button.

			The loop's length changes as people join and leave. That is safe for the same reason
			`_targetPicker`'s is — Iris identity comes from the call-stack line plus how many times it
			has run this frame, so a changed length shifts identity inside the loop and nothing after
			it. ]]
		for _, player in Players:GetPlayers() do
			local balance = player:GetAttribute(GarageConfig.CashAttribute)
			local known = type(balance) == "number"
			Iris.Text({
				string.format(
					"%s (%d) — %s",
					player.Name,
					player.UserId,
					if known then GarageConfig.formatCash(balance) else "profile has not loaded yet"
				),
				false,
				if known then DIM_COLOR else BAD_COLOR,
			})
		end

		--[[ One amount for the whole tab, used by the buttons below AND by the post button at the
			bottom. Both places name the number in their own label, so there is never a press whose
			amount is off screen. ]]
		local amountState = Iris.State(10000)
		--[[ Increment 1, and the +/- buttons off with it. Iris ROUNDS the box to its increment when it
			loses focus, so a coarser step would quietly turn a typed 12,345 into 12,300 — which is the
			wrong trade for a box whose whole job is "set them to exactly this". The one-press amounts
			below are the fast path; this one is the exact path. ]]
		Iris.InputNum({ "Amount", 1, -CASH_MAX, CASH_MAX, "$%d", true }, { number = amountState })
		local amount = math.abs(math.floor(amountState:get() or 0))

		Iris.SameLine()
		if Iris.Button({ "Give" }).clicked() then
			self:_adminAsk("cash", target, amount, "add")
		end
		if Iris.Button({ "Take" }).clicked() then
			self:_adminAsk("cash", target, -amount, "add")
		end
		--[[ Set is not Give with a subtraction done on this side: the panel does not know the target's
			balance for anybody but the players it can see, and racing a payout that lands between the
			read and the write is exactly the bug that makes a debug tool untrustworthy. The server does
			the arithmetic against the profile it is holding. ]]
		if Iris.Button({ "Set to" }).clicked() then
			self:_adminAsk("cash", target, amount, "set")
		end
		Iris.End()

		Iris.Text({ "Take stops at zero — a balance never goes negative.", true, DIM_COLOR })

		Iris.SameLine()
		for _, step in CASH_QUICK do
			if Iris.Button({ "+" .. GarageConfig.formatCash(step) }).clicked() then
				self:_adminAsk("cash", target, step, "add")
			end
		end
		Iris.End()

		Iris.SeparatorText({ "Not in this server" })

		Iris.Text({
			"A username or a user id. It is posted to their save file and lands the moment they next join — or within a minute, if they are playing on another server right now. Somebody already in this server is handed it directly instead.",
			true,
			DIM_COLOR,
		})
		Iris.Text({
			"In a Studio playtest this writes to the mock store, which is wiped between playtests — so a post to anyone who is not in the playtest with you cannot be seen.",
			true,
			DIM_COLOR,
		})

		local whoState = Iris.State("")
		Iris.InputText({ "Player", "username or user id" }, { text = whoState })

		Iris.SameLine()
		if Iris.Button({ string.format("Post %s", GarageConfig.formatCash(amount)) }).clicked() then
			self:_adminAsk("cashOffline", "none", whoState:get(), amount)
		end
		if Iris.Button({ string.format("Post -%s", GarageConfig.formatCash(amount)) }).clicked() then
			self:_adminAsk("cashOffline", "none", whoState:get(), -amount)
		end
		Iris.End()

		self:_renderAdminReply()
	end)
end

--[[ Products. The three things this game sells for Robux, granted without a receipt, plus the
	controls for the one of them that has a screen of its own.

	THE RANDOM CAR CARD IS THE POINT OF THIS TAB. It is tuned to be missable — twenty-five seconds
	before it first slides in, then twelve on and forty-five off — which is right for a player and
	unworkable for anybody trying to look at it. "Show card now" drives the card's own slide, and
	"Press card" presses its own button, so what is on screen is the shipping card.

	Grant a pull first, then press: with a pull banked the press spends it and the reveal opens,
	which is the whole product. With none, the press opens the real Robux prompt — deliberately, and
	the tab says so, because a debug button that skipped the prompt would be testing the half that
	was never in doubt. ]]
function AdminPanelController._initProductsTab(self)
	self:addTab("Products", function()
		self._randomCar = self._randomCar or Shard.get("RandomCarController")
		local card = self._randomCar
		local state = if card then card:debugState() else nil

		Iris.SeparatorText({ "Random car card" })

		if not RandomCarConfig.Enabled then
			Iris.Text({ "RandomCarConfig.Enabled is false — there is no card and no product.", true, BAD_COLOR })
		end

		if not state then
			Iris.Text({ "RandomCarController is not running.", true, BAD_COLOR })
		else
			--[[ `sellable` is the server's word on whether rbxsync ever created the product. False
				means the id is 0, which reads downstream as "this cannot be sold" and takes the card
				off the screen for the session — worth saying out loud, because it looks identical to
				a bug from the outside. ]]
			Iris.Text({
				string.format(
					"Product %d at R$%d · %s",
					RandomCarConfig.ProductId,
					RandomCarConfig.Price,
					if state.sellable then "sellable" else "NOT sellable (product id is 0 — run rbxsync)"
				),
				true,
				if state.sellable then DIM_COLOR else BAD_COLOR,
			})
			Iris.Text({
				string.format("Pulls banked: %d", state.pulls),
				false,
				if state.pulls > 0 then OK_COLOR else DIM_COLOR,
			})

			local phase = if state.revealOpen
				then "reveal is open"
				elseif state.suppressed then "hidden (racing)"
				elseif state.shown then "on screen"
				else "off screen"
			Iris.Text({ string.format("Card: %s, %.1fs to the next flip", phase, math.max(state.timeLeft, 0)) })
		end

		Iris.SameLine()
		if Iris.Button({ "Show card now" }).clicked() then
			if card and not card:debugShowCard() then
				self._adminReply = { ok = false, message = "The card cannot show: the product is not sellable in this place." }
			end
		end
		if Iris.Button({ "Hide card" }).clicked() then
			if card then
				card:debugHideCard()
			end
		end
		if Iris.Button({ "Press card" }).clicked() then
			if card then
				card:debugPress()
			end
		end
		Iris.End()

		Iris.Text({
			"Press with a pull banked and it rolls one in front of you. Press with none and Roblox's real purchase prompt opens — that is what the button does.",
			true,
			DIM_COLOR,
		})

		Iris.SeparatorText({ "Grant" })

		local target = self:_targetPicker()

		local countState = Iris.State(1)
		Iris.SliderNum({ "How many", 1, 1, GRANT_MAX }, { number = countState })
		local many = countState:get()

		Iris.SameLine()
		if Iris.Button({ "Random car pulls" }).clicked() then
			self:_adminAsk("pull", target, many)
		end
		if Iris.Button({ "Extra lives" }).clicked() then
			self:_adminAsk("life", target, many)
		end
		if Iris.Button({ "Offline boosts" }).clicked() then
			self:_adminAsk("boost", target, many)
		end
		Iris.End()

		Iris.Text({
			"All three go through the same grant the Robux receipt calls, so a pull banked here rolls exactly as a bought one does.",
			true,
			DIM_COLOR,
		})

		--[[ GAME PASSES, and this is the only way to test one before it is synced. Roblox draws no
			purchase prompt in a Studio playtest at all, and a pass whose id is still 0 cannot be
			bought anywhere — so without this a pass seam can only be exercised in a live server by
			spending real Robux. See `AdminService.Actions.pass`.

			LIVE ONES ONLY. A pass with `Live = false` in `PassConfig` has no seam behind it, so
			granting it would hand somebody an entitlement that does nothing and leave a tester
			reading a result off code that was never written. The server refuses those too. ]]
		Iris.SeparatorText({ "Game passes" })

		Iris.SameLine()
		for _, pass in PassConfig.Passes do
			if pass.Live and Iris.Button({ pass.Title }).clicked() then
				self:_adminAsk("pass", target, pass.Key)
			end
		end
		Iris.End()

		Iris.Text({
			"Writes the same profile entry a GIFT receipt writes, so PassService answers true through the same union every seam reads. It is NOT revocable, and it cannot make Roblox's own ownership say true.",
			true,
			DIM_COLOR,
		})

		self:_renderAdminReply()
	end)
end

--[[ Tutorial. Play the onboarding again, on the save you have or on a brand-new one.

	REPLAY is the everyday button and it is safe on a live server: nothing is deleted, the target is
	put back on beat 1 (`TutorialService.restart`), and a run they are in is ended first so that beat,
	which is pressed in the lobby, has a lobby to be pressed in. It can be aimed at anybody here,
	which is what a group playtest wants.

	IN STUDIO THE PLACE CARRIES `Workspace.SkipTutorial`, so no tutorial is running at all until
	something lifts it. Replay does, for that playtest only, and because the flag is server-wide
	everybody in the playtest comes up on their own beat. The tab says so while the flag is on.

	WIPE is the other end: your own save emptied, and you sent back in as somebody who has never
	joined, which is the only way to see the tutorial exactly as a first join gets it. It never lands
	on anybody else, it cannot be undone, and the box above it has to be ticked first. The server
	refuses it on Studio's mock store, where every playtest already starts empty. ]]
function AdminPanelController._initTutorialTab(self)
	self:addTab("Tutorial", function()
		--- Where you are, off the same attribute the card, the truck and the staged road all read.
		local step = Players.LocalPlayer:GetAttribute(TutorialConfig.StepAttribute)
		local index = if type(step) == "string" then TutorialConfig.indexOf(step) else nil
		local status, colour
		if not TutorialConfig.Enabled then
			status, colour = "No tutorial in this build: TutorialConfig.Enabled is false.", BAD_COLOR
		elseif TutorialConfig.isBypassed() then
			status, colour = string.format(
				"No tutorial is running: Workspace.%s is on in this place.",
				TutorialConfig.BypassAttribute
			), DIM_COLOR
		elseif index then
			status, colour = string.format("You are on beat %d of %d: %s.", index, #TutorialConfig.Steps, step), OK_COLOR
		elseif step == "" then
			status, colour = "You have finished or skipped the tutorial.", DIM_COLOR
		else
			status, colour = "Waiting for the server to say where your tutorial is.", DIM_COLOR
		end
		Iris.Text({ status, true, colour })

		Iris.SeparatorText({ "Replay" })

		Iris.Text({
			"Puts you back on beat 1 on the save you already have. Nothing is deleted, so it is safe on a live server. A run in progress is ended first, because beat 1 is pressed in the lobby.",
			true,
			DIM_COLOR,
		})
		if TutorialConfig.isBypassed() then
			Iris.Text({
				string.format(
					"Workspace.%s is on, so Replay lifts it for this playtest first. That never reaches the place file, and the flag is server-wide, so everyone in this playtest gets their tutorial too.",
					TutorialConfig.BypassAttribute
				),
				true,
				BAD_COLOR,
			})
		end

		local target = self:_targetPicker("Replay for")
		if Iris.Button({ "Replay tutorial" }).clicked() then
			self:_adminAsk("tutorial", target)
		end

		Iris.SeparatorText({ "Wipe my data" })

		Iris.Text({
			"Deletes YOUR save for good and sends you back in as a brand-new player, so the tutorial runs exactly as a first join gets it. Cars, cash, worlds, likes, banked lives and pulls, and gifted passes all go. Passes bought on Roblox stay. This only ever lands on you.",
			true,
			BAD_COLOR,
		})
		if RunService:IsStudio() then
			Iris.Text({
				"On Studio's mock store the server refuses this, since every playtest already starts on an empty save. Use Replay here.",
				true,
				DIM_COLOR,
			})
		end

		local armed = Iris.State(false)
		Iris.Checkbox({ "Yes, delete my save" }, { isChecked = armed })
		if Iris.Button({ "Wipe my data and rejoin" }).clicked() then
			if armed:get() then
				armed:set(false)
				self:_adminAsk("wipe", "none")
			else
				self._adminReply = { ok = false, message = "Tick \"Yes, delete my save\" first." }
			end
		end

		self:_renderAdminReply()
	end)
end

--[[ Showroom (2026-09-28). The dealership rework's three waits, on buttons: a buyer (seventy-five
	seconds, and a Great one is one roll in ten), a buyer giving up (five minutes), and the
	welcome-back screen (five real minutes logged out). Plus car condition, which otherwise only moves
	when a run banks a damaged car. Every button goes through `AdminService`, which calls the public
	function of the service that owns the thing — so a buyer sent from here walks in, prices and sells
	exactly as one that arrived on its own.

	THE LIST AT THE TOP IS READ OFF THE RIGS, not asked of the server: a buyer carries their offer as
	attributes (`CustomerService.BuyerAttributes`) for the sign, and this reads the same ones. So a
	row here that disagrees with the sign above the buyer's head is a thing that cannot happen, and a
	buyer missing from the list is a rig that was never built — which is its own finding. ]]
function AdminPanelController._initShowroomTab(self)
	local bandLabels = { "Random" }
	for _, band in BuyerConfig.Bands do
		table.insert(bandLabels, band.Key)
	end
	local sellerBandLabels = { "Random" }
	for _, band in SellerConfig.Bands do
		table.insert(sellerBandLabels, band.Key)
	end

	--[[ The new-best preview's lists (2026-10-03, for recording the garage in every rarity): every car
		on any world's ladder grouped by `CarRarity`, rarities in ladder order, plus paint and weather
		with a "Random" each. Built once; the roster is fixed at require time. ]]
	local rarityLabels, carsOfRarity, bandOf = { "Any" }, { Any = {} }, { Any = 0 }
	local seenBody = {}
	for index in WorldConfig.Worlds do
		for _, body in WorldConfig.carsFor(index) do
			if seenBody[body] then
				continue
			end
			seenBody[body] = true
			local word, band = CarRarity.of(body)
			local rarity = if word ~= "" then word else "Unranked"
			if not carsOfRarity[rarity] then
				carsOfRarity[rarity] = {}
				bandOf[rarity] = band
				table.insert(rarityLabels, rarity)
			end
			local car = { body = body, label = string.format("%s  (%s)", GarageConfig.displayName(body), body) }
			table.insert(carsOfRarity[rarity], car)
			table.insert(carsOfRarity.Any, car)
		end
	end
	table.sort(rarityLabels, function(a, b)
		return bandOf[a] < bandOf[b]
	end)
	for _, cars in carsOfRarity do
		table.sort(cars, function(a, b)
			return a.label < b.label
		end)
	end
	local previewPaints, paintOfPreview = { "Stock", "Random" }, { Stock = PaintConfig.StockIndex, Random = "random" }
	for index, entry in PaintConfig.Palette do
		if index ~= PaintConfig.StockIndex then
			table.insert(previewPaints, entry.Name)
			paintOfPreview[entry.Name] = index
		end
	end
	local previewWeathers, weatherOfPreview, weatherKeys = { "None", "Random" }, { None = "none" }, {}
	for _, mutation in WeatherConfig.Mutations do
		table.insert(previewWeathers, mutation.Name)
		weatherOfPreview[mutation.Name] = mutation.Key
		table.insert(weatherKeys, mutation.Key)
	end
	local previewRng = Random.new()

	self:addTab("Showroom", function()
		Iris.SeparatorText({ "Buyers on your lot" })

		local me = Players.LocalPlayer.UserId
		local now = workspace:GetServerTimeNow()
		local rows = 0
		for _, model in CollectionService:GetTagged(BUYER_TAG) do
			if model:GetAttribute("BuyerOwner") ~= me then
				continue
			end
			rows += 1
			local expires = model:GetAttribute("BuyerExpiresAt")
			local left = if type(expires) == "number" then math.max(0, expires - now) else 0
			local arrived = model:GetAttribute("BuyerArrived") == true
			Iris.Text({
				string.format(
					"%s - %s for %s - %s",
					tostring(model:GetAttribute("BuyerName") or "Anonymous"),
					GarageConfig.formatCash(tonumber(model:GetAttribute("BuyerOffer")) or 0),
					tostring(model:GetAttribute("BuyerCarId")),
					if arrived
						then string.format("%d:%02d left", math.floor(left / 60), math.floor(left % 60))
						else "walking in, clock not started"
				),
				true,
				if arrived then OK_COLOR else DIM_COLOR,
			})
		end
		--- Always one line when there is nothing, so the widgets below keep their ids whatever the count.
		Iris.Text({
			if rows == 0 then "Nobody is waiting. A buyer needs a car on a bay with For Sale on." else "",
			true,
			DIM_COLOR,
		})

		Iris.SeparatorText({ "Buyers" })
		local target = self:_targetPicker("For")

		local bandState = Iris.State("Random")
		Iris.Combo({ "Rating" }, { index = bandState })
		for _, label in bandLabels do
			Iris.Selectable({ label, label }, { index = bandState })
		end
		Iris.End()

		if Iris.Button({ "Send a buyer now" }).clicked() then
			self:_adminAsk("buyer", target, bandState:get())
		end
		Iris.Text({
			"Picks a random for-sale car on a bay with no buyer yet, and they walk in from the forecourt. Ignores the waiting cap; still one buyer per car.",
			true,
			DIM_COLOR,
		})

		local hurryState = Iris.State(10)
		Iris.SliderNum({ "Seconds", 1, 1, 120 }, { number = hurryState })
		Iris.SameLine()
		if Iris.Button({ "Make every offer end in that" }).clicked() then
			self:_adminAsk("hurryBuyers", target, hurryState:get())
		end
		if Iris.Button({ "Send them all away" }).clicked() then
			self:_adminAsk("clearBuyers", target)
		end
		Iris.End()

		--- Sellers at the kerb (2026-10-15): the four-minute wait skipped. A real seller; buying costs real cash.
		Iris.SeparatorText({ "Sellers" })
		local sellerBandState = Iris.State("Random")
		Iris.Combo({ "Seller rating" }, { index = sellerBandState })
		for _, label in sellerBandLabels do
			Iris.Selectable({ label, label }, { index = sellerBandState })
		end
		Iris.End()
		Iris.SameLine()
		if Iris.Button({ "Send a seller now" }).clicked() then
			self:_adminAsk("seller", target, sellerBandState:get())
		end
		if Iris.Button({ "Send the seller away" }).clicked() then
			self:_adminAsk("clearSeller", target)
		end
		Iris.End()
		Iris.Text({
			"Pulls a car up at their SellerSpot now, replacing any seller already there. Skips the clock, the tutorial and the mid-run check.",
			true,
			DIM_COLOR,
		})

		Iris.SeparatorText({ "Welcome back" })
		Iris.Text({
			"Runs the real rejoin check as if they had been gone this long: offline tips are simulated and BANKED, buyers who would have come are made, and the screen opens. Tips stop growing past the 2h cap.",
			true,
			DIM_COLOR,
		})
		local awayState = Iris.State(60)
		Iris.SliderNum({ "Minutes away", 5, 5, 240 }, { number = awayState })
		if Iris.Button({ "Pretend they were away" }).clicked() then
			self:_adminAsk("away", target, awayState:get())
		end

		Iris.SeparatorText({ "Condition" })
		Iris.Text({
			"Sets the condition of every car on their bays (workshop included), as if each had been banked at that much HP. Moves market value, tips, and what buyers offer, and gives the workshop's REPAIR something to fix.",
			true,
			DIM_COLOR,
		})
		local conditionState = Iris.State(50)
		Iris.SliderNum({ "Condition %", 5, 0, 100 }, { number = conditionState })
		if Iris.Button({ "Set condition" }).clicked() then
			self:_adminAsk("condition", target, conditionState:get() / 100)
		end

		Iris.SeparatorText({ "New best cutscene" })
		Iris.Text({
			"Play it now shows their most valuable car and leaves the record alone. Forget the record makes the next car they get (of any worth) a real new best.",
			true,
			DIM_COLOR,
		})
		Iris.SameLine()
		if Iris.Button({ "Play it now" }).clicked() then
			self:_adminAsk("showcase", target, "play")
		end
		if Iris.Button({ "Forget the record" }).clicked() then
			self:_adminAsk("showcase", target, "forget")
		end
		Iris.End()

		--[[ Any car at all, in the garage its rarity colours. Nothing is given and the record is not
			touched (`ShowcaseService.playCar`). "Random" in a list is resolved here, per press, so the
			rarity buttons give a different car each time. ]]
		Iris.SeparatorText({ "New best: try any car" })
		Iris.Text({
			"Plays the cutscene for the car picked here, owned or not. Nothing is given and the record is untouched. The garage neon is the car's rarity colour. The rarity buttons play a random car of that rarity with the paint and weather below.",
			true,
			DIM_COLOR,
		})
		local rarityState = Iris.State("Any")
		Iris.Combo({ "Rarity" }, { index = rarityState })
		for _, label in rarityLabels do
			Iris.Selectable({ label, label }, { index = rarityState })
		end
		Iris.End()
		local pool = carsOfRarity[rarityState:get()] or carsOfRarity.Any

		--- "Random" unless it names a car in the chosen rarity, so switching rarity never strands a pick.
		local pickState = Iris.State("Random")
		local picked = nil
		for _, car in pool do
			if car.label == pickState:get() then
				picked = car
			end
		end
		if not picked and pickState:get() ~= "Random" then
			pickState:set("Random")
		end
		Iris.Combo({ "Car" }, { index = pickState })
		Iris.Selectable({ "Random", "Random" }, { index = pickState })
		for _, car in pool do
			Iris.Selectable({ car.label, car.label }, { index = pickState })
		end
		Iris.End()

		local previewPaintState = Iris.State("Stock")
		Iris.Combo({ "Paint" }, { index = previewPaintState })
		for _, label in previewPaints do
			Iris.Selectable({ label, label }, { index = previewPaintState })
		end
		Iris.End()

		local previewWeatherState = Iris.State("None")
		Iris.Combo({ "Weather" }, { index = previewWeatherState })
		for _, label in previewWeathers do
			Iris.Selectable({ label, label }, { index = previewWeatherState })
		end
		Iris.End()

		local function preview(cars, car)
			local chosen = car or cars[previewRng:NextInteger(1, #cars)]
			local weather = weatherOfPreview[previewWeatherState:get()]
			if not weather then
				weather = if #weatherKeys > 0 then weatherKeys[previewRng:NextInteger(1, #weatherKeys)] else "none"
			end
			self:_adminAsk("showcase", target, "preview", chosen.body, paintOfPreview[previewPaintState:get()] or "random", weather)
		end
		if Iris.Button({ "Play this car" }).clicked() then
			preview(pool, picked)
		end
		Iris.SameLine()
		for _, rarity in rarityLabels do
			if rarity ~= "Any" and Iris.Button({ rarity }).clicked() then
				preview(carsOfRarity[rarity], nil)
			end
		end
		Iris.End()

		--[[ The line from a carried car to its bay (`GuideTrailConfig`, 2026-10-16): which look, live,
			for this client only, and a way to see it without banking a car. Last in the tab so a
			missing controller cannot shift the ids of anything under it. ]]
		Iris.SeparatorText({ "Guide trail" })
		local guide = Shard.get("GuideTrailController")
		if guide then
			local guideStyleState = Iris.State(guide:getStyle())
			--[[ Gamebeast can change the look after this state was made (the A/B group lands a few
				seconds into a session), so a change from outside is followed here rather than read
				as a pick below, which would pin the old look over the player's real group. ]]
			if self._guideStyleSeen ~= guide:getStyle() then
				self._guideStyleSeen = guide:getStyle()
				guideStyleState:set(guide:getStyle())
			end
			Iris.Combo({ "Look" }, { index = guideStyleState })
			for _, style in guide.Styles do
				Iris.Selectable({ style, style }, { index = guideStyleState })
			end
			Iris.End()
			if guideStyleState:get() ~= guide:getStyle() then
				guide:setStyle(guideStyleState:get())
				self._guideStyleSeen = guide:getStyle()
			end
			Iris.Text({
				"Gamebeast A/B gave you: " .. (guide:getRemoteStyle() or "nothing yet (Studio never does)"),
				true,
				DIM_COLOR,
			})

			local guidePreviewState = Iris.State(guide:getPreview())
			Iris.Checkbox({ "Draw it with empty hands" }, { isChecked = guidePreviewState })
			if guidePreviewState:get() ~= guide:getPreview() then
				guide:setPreview(guidePreviewState:get())
			end
			Iris.Text({
				"Points at the nearest empty bay on your lot, the same one the glow and the tutorial chip use. Picking a look changes only this screen and overrides the A/B for the session; each player's look comes from Gamebeast (GuideTrailConfig.Remote).",
				true,
				DIM_COLOR,
			})
		else
			Iris.Text({ "GuideTrailController is not running.", true, BAD_COLOR })
		end

		self:_renderAdminReply()
	end)
end

-- Iris can build widgets before Roblox has measured their text, leaving AutomaticSize widgets
-- clipped. A one-shot ForceRefresh a couple frames after the first open re-measures everything.
function AdminPanelController._refreshOnFirstOpen(self)
	if self._didFirstRefresh then
		return
	end
	self._didFirstRefresh = true
	task.spawn(function()
		for _ = 1, 2 do
			RunService.RenderStepped:Wait()
		end
		Iris.ForceRefresh()
	end)
end

AdminPanelController:withLifecycle({
	init = function(_self) end,

	start = function(self)
		-- UI-only gate; the server must re-validate any privileged action a tab triggers.
		if not Admins.isAdmin(Players.LocalPlayer) then
			return
		end

		Iris.Init()
		-- Default Iris sizing makes list items ~19px tall and tightly packed, which is fiddly
		-- to click. sizeClear bumps text+padding so widgets become proper click targets.
		Iris.UpdateGlobalConfig(Iris.TemplateConfig.sizeClear)

		self.isOpened = Iris.State(false)
		self.selectedTab = Iris.State(1)

		self._fps = 0
		self._fpsHistory = table.create(FPS_SAMPLES, 60)
		RunService.Heartbeat:Connect(function(dt)
			local fps = math.floor(1 / math.max(dt, 1e-4) + 0.5)
			self._fps = fps
			local history = self._fpsHistory
			table.remove(history, 1)
			table.insert(history, fps)
		end)

		self:_initHomeTab()
		--- Second in the strip, because it is the one tab somebody is told to go and open, and the
		--- only one whose whole job is answering a question about how the game feels.
		if CameraTuningConfig.Enabled then
			self:_initCameraTab()
		end
		self:_initWeatherTab()
		self:_initPoliceTab()
		self:_initPickupsTab()
		self:_initCarsTab()
		self:_initMapsTab()
		self:_initObstaclesTab()
		self:_initMoneyTab()
		self:_initProductsTab()
		self:_initShowroomTab()
		self:_initTutorialTab()

		Iris:Connect(function()
			-- Skip the whole frame while closed — no window, no per-frame cost.
			if not self.isOpened:get() then
				return
			end

			Iris.Window({ "ADMIN PANEL  (F2)" }, { isOpened = self.isOpened })
			self:_renderTabBar()
			Iris.Separator()

			local tab = self.tabs[math.clamp(self.selectedTab:get(), 1, math.max(#self.tabs, 1))]
			if tab then
				tab.render()
			end
			Iris.End()
		end)

		local function toggle()
			local opening = not self.isOpened:get()
			self.isOpened:set(opening)
			if opening then
				self:_refreshOnFirstOpen()
			end
		end

		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == TOGGLE_KEY then
				toggle()
			end
		end)

		--[[ A PHONE HAS NO F2 (2026-10-16: the owner could not reach Give Star to test the star timer
			on a phone). An admin on a touch screen gets a small ADMIN tab in the topbar row's far right,
			which this game leaves empty; the left edge mid-height, where it first went, is the HUD rail
			(it sat on the rail's buttons). Only past the admin gate above, so nobody else ever sees it. ]]
		if UserInputService.TouchEnabled then
			local gui = Instance.new("ScreenGui")
			gui.Name = "AdminToggle"
			gui.ResetOnSpawn = false
			gui.DisplayOrder = 2000
			--- In the topbar's own row, so it sits beside Roblox's buttons rather than under the bar.
			gui.IgnoreGuiInset = true
			local button = Instance.new("TextButton")
			button.AnchorPoint = Vector2.new(1, 0)
			button.Position = UDim2.new(1, -16, 0, 14)
			button.Size = UDim2.fromOffset(56, 28)
			button.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
			button.BackgroundTransparency = 0.3
			button.TextColor3 = Color3.new(1, 1, 1)
			button.Font = Enum.Font.GothamBold
			button.TextSize = 12
			button.Text = "ADMIN"
			button.Parent = gui
			button.Activated:Connect(toggle)
			gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		end
	end,
})

return AdminPanelController
