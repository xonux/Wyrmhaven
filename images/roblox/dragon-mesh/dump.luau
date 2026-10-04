-- Prints every triangle of a DragonBuilder spec: "t ax ay az bx by bz cx cy cz r g b"
local Builder = BUILDER()
local P = Builder.Palettes.Fire
for _, stage in ipairs({ "Baby", "Adult" }) do
	local spec = Builder.Specs[stage](P)
	print("stage " .. stage)
	for _, seg in ipairs(spec.segs) do
		print("seg " .. seg.name)
		for _, t in ipairs(seg.tris) do
			local a, b, c, col = t[1], t[2], t[3], t[4]
			print(string.format("t %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.3f %.3f %.3f %d",
				a.X, a.Y, a.Z, b.X, b.Y, b.Z, c.X, c.Y, c.Z, col.R, col.G, col.B, t[6] and 1 or 0))
		end
	end
end
