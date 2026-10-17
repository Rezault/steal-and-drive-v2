--[[
	BrakeLightConfig
	----------------
	Stop lamps: a car's rear lamps lit red while it is slowing. Two cars wear them, off the same
	look and the same lamp choice (`Modules/CarBrakeLights`), and each has its own rule for WHEN:

	  • TRAFFIC lights up when its scripted speed is being eased down, which only ever happens
	    when it is falling in behind a slower car in its lane (`TrafficConfig.Headway`, read by
	    `TrafficController._headway`). A lane change, a swerve round an obstacle and a shove from
	    the player are none of them braking, and a wreck or the car being stolen has no driver.
	  • THE PLAYER'S CAR lights up on the pedal: brake held (`DriveController.getThrottleInput`
	    under the same -0.1 the drive shim brakes on, read by `CarLightsController`), while the
	    shim is actually driving. Not on deceleration, so a car slowing because it hit something
	    stays dark, and a car held on the brake floor (`DriveConfig.MinSpeedFraction`) stays lit,
	    which is what a pedal does.

	THE LOOK IS THE BLINKERS' LOOK (`TrafficConfig.Blinkers`), in red: the same twin of the same
	lamp, grown by `Grow` and pushed `Proud` studs out behind the car. `Proud` is set a shade UNDER
	the blinker's on purpose. On a body with no amber part the turn signal and the stop lamp share
	one mesh, and two twins in one place would z-fight; the one pushed further out is the one you
	see, so a flashing indicator shows through a lit brake light, the way a shared bulb does on a
	real car. Keep it under `TrafficConfig.Blinkers.Proud`. `CoverEnd` is the lamp rules' window
	band and must match the blinkers' too, or the two disagree about which glass is a tail lamp.

	`MinDrop` is how far, in studs/s, traffic's speed target has to be below its speed before the
	lamp lights. The headway easing chases a moving target, so without a deadband a car matching
	the one in front would flicker at every fraction-of-a-stud correction. `Hold` is how long, in
	seconds, a lamp stays lit after the last frame that asked for it: a stop lamp is a switch and
	must not strobe, and 0.4 is about the time a driver's foot rests on the pedal for a dab. The
	player's is shorter because their lamp is on a held key, which is already steady, and only a
	tap wants smoothing.
]]

local BrakeLightConfig = {}

BrakeLightConfig.Enabled = true

-- The look, shared by both cars. See the header for why `Proud` is under the blinkers'.
BrakeLightConfig.Color = Color3.fromRGB(255, 28, 18)
BrakeLightConfig.Grow = 0.03
BrakeLightConfig.Proud = 0.04
BrakeLightConfig.CoverEnd = 0.65

BrakeLightConfig.Traffic = {
	Enabled = true,
	MinDrop = 1,
	Hold = 0.4,
}

BrakeLightConfig.Player = {
	Enabled = true,
	Hold = 0.12,
}

return BrakeLightConfig
