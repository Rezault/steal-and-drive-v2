-- Traffic collection readability and contextual jump teaching.
local Config = {}
Config.Enabled = true
Config.UpdateInterval = 0.15
Config.CueDistance = 300
Config.FocusDistance = 210
Config.FocusCross = 24
Config.SwitchRatio = 0.72
Config.SpeedThreshold = 1.01
-- "Kit": rarity gradient card with sunburst, no checker. "Classic": the navy card with a rarity rim.
Config.Style = "Kit"
Config.JumpText = "JUMP TO STEAL"
-- Card bottom (screen share) on TOUCH, 2026-10-13 (punch list M5). At the desktop 0.87 it sat on the
-- phone speedo and NitroBadge (bottom 0.16 + 14px, `DrivingHudController._layoutReadouts`). 0.60 puts
-- the jump hint's lower edge (~0.05 below the card) at ~0.653, clear of the Nitro bar (0.673-0.73);
-- top-centre is taken by the near-miss / rare-car / STOLEN toasts (0.105 / 0.165 / 0.24).
Config.Y = 0.87
Config.TouchY = 0.60
Config.Reminder = {
 Enabled = true, StartDelay = 5, Duration = 4, Cooldown = 30,
 MinAhead = 35, MaxAhead = 180, MinArrival = 0.65, MaxArrival = 4.5,
}
return Config
