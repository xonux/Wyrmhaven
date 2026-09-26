-- Shared look for every Wyrmhaven UI screen (HabitatBar, DragonScreen, ...).
-- Change a value here and every screen follows. Icon/portrait `Image` fields
-- are empty placeholders: put a real "rbxassetid://..." in one and UIKit uses
-- it instead of the drawn fallback everywhere that icon appears.
local UITheme = {}

UITheme.Font = Enum.Font.BuilderSansBold

UITheme.CornerRadius = UDim.new(0, 24)
UITheme.CardCornerRadius = UDim.new(0, 16)
UITheme.ButtonCornerRadius = UDim.new(0, 18)
UITheme.StrokeThickness = 5

UITheme.TitleBarHeight = 58
UITheme.ButtonRowHeight = 70
UITheme.ContentGap = 14
UITheme.Padding = 18
UITheme.ScreenMargin = 20

UITheme.BackdropTransparency = 0.45

UITheme.Colors = {
	PopupTop = Color3.fromRGB(52, 55, 62),
	PopupBottom = Color3.fromRGB(38, 40, 46),
	Card = Color3.fromRGB(46, 48, 55),
	CardStroke = Color3.fromRGB(78, 82, 92),
	Text = Color3.fromRGB(236, 238, 242),
	TextMuted = Color3.fromRGB(150, 155, 166),
	TextLight = Color3.fromRGB(255, 255, 255),
	TextShadow = Color3.fromRGB(16, 17, 20),
	Backdrop = Color3.fromRGB(0, 0, 0),
	BarTrack = Color3.fromRGB(28, 30, 35),
	BarStroke = Color3.fromRGB(70, 74, 84),
	XpFill = Color3.fromRGB(96, 170, 240),
	CoinFill = Color3.fromRGB(226, 184, 88),
	CoinFaceTop = Color3.fromRGB(250, 214, 120),
	CoinFaceBottom = Color3.fromRGB(214, 160, 56),
	CoinEdge = Color3.fromRGB(150, 104, 30),
	FoodFace = Color3.fromRGB(220, 92, 78),
	FoodLeaf = Color3.fromRGB(110, 190, 110),
	Accent = Color3.fromRGB(230, 192, 110), -- levels, highlights
	Toast = Color3.fromRGB(30, 32, 37),

	-- Dark grey surfaces shared by every screen
	Surface = Color3.fromRGB(34, 36, 41),
	SurfaceRaised = Color3.fromRGB(50, 53, 60),
	SurfaceStroke = Color3.fromRGB(78, 82, 92),

	-- HabitatBar round buttons
	CircleTop = Color3.fromRGB(64, 67, 75),
	CircleBottom = Color3.fromRGB(40, 42, 48),
	CircleEdge = Color3.fromRGB(96, 100, 112),
	CircleInnerTop = Color3.fromRGB(46, 48, 55),
	CircleInnerBottom = Color3.fromRGB(30, 32, 37),

	-- DragonScreen
	BackgroundTop = Color3.fromRGB(58, 61, 68),
	BackgroundBottom = Color3.fromRGB(20, 21, 25),
	FloorTop = Color3.fromRGB(44, 46, 52),
	FloorBottom = Color3.fromRGB(26, 27, 31),
	LevelFill = Color3.fromRGB(86, 156, 232),
}

-- Face = main color, Lip = thin darker bottom edge, Outline = border stroke.
UITheme.Buttons = {
	Confirm = { Face = Color3.fromRGB(78, 168, 104), Lip = Color3.fromRGB(56, 128, 78), Outline = Color3.fromRGB(104, 196, 130) }, -- collect / feed / confirm
	Gem = { Face = Color3.fromRGB(138, 96, 196), Lip = Color3.fromRGB(100, 68, 150), Outline = Color3.fromRGB(170, 130, 224) }, -- Gem-costed actions
	Gold = { Face = Color3.fromRGB(196, 156, 76), Lip = Color3.fromRGB(150, 116, 52), Outline = Color3.fromRGB(226, 190, 110) }, -- Coin-costed upgrades
	Danger = { Face = Color3.fromRGB(190, 72, 66), Lip = Color3.fromRGB(140, 50, 46), Outline = Color3.fromRGB(222, 106, 98) }, -- sell / close
	Info = { Face = Color3.fromRGB(62, 65, 73), Lip = Color3.fromRGB(42, 44, 50), Outline = Color3.fromRGB(96, 100, 112) }, -- neutral (back)
	Pink = { Face = Color3.fromRGB(184, 92, 140), Lip = Color3.fromRGB(136, 64, 102), Outline = Color3.fromRGB(214, 124, 170) },
	Disabled = { Face = Color3.fromRGB(58, 60, 66), Lip = Color3.fromRGB(42, 44, 49), Outline = Color3.fromRGB(76, 79, 87) },
}

-- Accent per element (popup stroke + title ribbon, DragonScreen element badge
-- and backdrop). Fire follows style-guide.md's Fire palette. Icon: the round
-- element badge image (see UIKit.elementBadge).
UITheme.Elements = {
	Fire = { Main = Color3.fromRGB(242, 130, 59), Dark = Color3.fromRGB(196, 58, 32), Light = Color3.fromRGB(255, 201, 77), Icon = "rbxassetid://76019394805473" },
	Water = { Main = Color3.fromRGB(46, 134, 217), Dark = Color3.fromRGB(22, 78, 150), Light = Color3.fromRGB(124, 196, 255), Icon = "rbxassetid://71877368377312" },
	Nature = { Main = Color3.fromRGB(88, 178, 72), Dark = Color3.fromRGB(42, 112, 38), Light = Color3.fromRGB(170, 226, 120), Icon = "rbxassetid://112411202329997" },
	Electric = { Main = Color3.fromRGB(240, 196, 40), Dark = Color3.fromRGB(176, 136, 16), Light = Color3.fromRGB(255, 228, 120), Icon = "rbxassetid://139500864127580" },
	Earth = { Main = Color3.fromRGB(166, 120, 76), Dark = Color3.fromRGB(100, 68, 40), Light = Color3.fromRGB(222, 184, 132), Icon = "rbxassetid://139368799293229" },
	Light = { Main = Color3.fromRGB(236, 226, 190), Dark = Color3.fromRGB(170, 160, 120), Light = Color3.fromRGB(255, 250, 232), Icon = "rbxassetid://131261090252398" },
	Dark = { Main = Color3.fromRGB(110, 72, 160), Dark = Color3.fromRGB(60, 36, 96), Light = Color3.fromRGB(170, 136, 214), Icon = "rbxassetid://111790945722453" },
	Metal = { Main = Color3.fromRGB(150, 160, 172), Dark = Color3.fromRGB(92, 100, 112), Light = Color3.fromRGB(204, 212, 222), Icon = "rbxassetid://119786214915275" },
	Default = { Main = Color3.fromRGB(150, 155, 166), Dark = Color3.fromRGB(90, 94, 104), Light = Color3.fromRGB(200, 204, 212) },
}

function UITheme.GetElement(element)
	return UITheme.Elements[element] or UITheme.Elements.Default
end

-- Same slot structure as Elements, derived from an arbitrary color (e.g. a
-- dragon's actual part color, so the UI matches the 3D model exactly).
function UITheme.AccentFromColor(color)
	return {
		Main = color,
		Dark = color:Lerp(Color3.new(0, 0, 0), 0.35),
		Light = color:Lerp(Color3.new(1, 1, 1), 0.4),
	}
end

-- No emoji anywhere (they read childish). Model: a 3D model in
-- ReplicatedStorage.Wyrmhaven.Assets.Icons shown in a ViewportFrame (Yaw/Rise
-- angle it); otherwise the icon is drawn from rounded frames (see UIKit
-- fillIcon), which is also the fallback if the model is missing. "Dot" is a
-- plain colored disc for icons that don't have a drawing yet.
UITheme.Icons = {
	Coin = { Image = "", Model = "GoldCoin", Yaw = 20, Rise = 0.1, Drawn = "Coin" },
	CoinBag = { Image = "", Model = "GoldCoin", Yaw = 20, Rise = 0.1, Drawn = "Coin" },
	Food = { Image = "", Model = "AppleIcon", Yaw = 15, Rise = 0.15, Drawn = "Food" },
	Dot = { Image = "", Drawn = "Dot" }, -- plain disc, tinted by the caller
	Gem = { Image = "", Model = "GemIcon", Rise = 0.3, Drawn = "Dot", Color = Color3.fromRGB(150, 110, 220) },
	Attack = { Image = "", Drawn = "Dot", Color = Color3.fromRGB(210, 90, 80) },
	Defense = { Image = "", Drawn = "Dot", Color = Color3.fromRGB(96, 150, 220) },
	Health = { Image = "", Drawn = "Dot", Color = Color3.fromRGB(110, 190, 110) },
	Speed = { Image = "", Drawn = "Dot", Color = Color3.fromRGB(240, 196, 40) },
	Upgrade = { Image = "", Drawn = "Dot", Color = Color3.fromRGB(110, 190, 110) },
	Lock = { Image = "", Drawn = "Lock", Color = Color3.fromRGB(150, 155, 166) }, -- the Shop's locked cards
	Edit = { Image = "", Drawn = "Dot", Color = Color3.fromRGB(150, 155, 166) },
	Nursery = { Image = "", Drawn = "Dot", Color = Color3.fromRGB(214, 124, 170) },
	ArrowUp = { Image = "", Drawn = "ArrowUp" },
	Back = { Image = "", Drawn = "Back" },
	Close = { Image = "", Drawn = "Close" },
	Check = { Image = "", Drawn = "Check" },
	Move = { Image = "", Drawn = "Move" },
	Heart = { Image = "", Drawn = "Heart" },
	Egg = { Image = "", Drawn = "Egg" },
	Nest = { Image = "", Model = "NestIcon", Rise = 0.9, Drawn = "Egg" }, -- a nest of the Incubator with its egg
	Swatch = { Image = "", Drawn = "Swatch" },
	Axe = { Image = "", Drawn = "Axe" },
	Plus = { Image = "", Drawn = "Plus" },
}

-- Fallback when a dragon's 3D model can't be found: an empty image (no glyph).
UITheme.Portraits = {
	Egg = { Image = "" },
	Baby = { Image = "" },
	Adult = { Image = "" },
}

UITheme.Tweens = {
	PopOpen = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PopClose = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.In),
	Fade = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	BarFill = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Bump = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

return UITheme
