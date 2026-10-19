--[[
	Format
	Number/text helpers shared by server and client.
]]

local Format = {}

-- 1234567 -> "1,234,567"
function Format.Commas(n: number): string
	local s = tostring(math.floor(n))
	local negative = string.sub(s, 1, 1) == "-"
	if negative then
		s = string.sub(s, 2)
	end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if negative then "-" else "") .. out
end

-- 1234 -> "$1,234" ; 2500000 -> "$2.5M"
function Format.Cash(n: number): string
	n = math.floor(n)
	if math.abs(n) >= 1e9 then
		return string.format("$%.2fB", n / 1e9)
	elseif math.abs(n) >= 1e6 then
		return string.format("$%.2fM", n / 1e6)
	end
	return "$" .. Format.Commas(n)
end

function Format.Percent(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

function Format.Seconds(s: number): string
	s = math.max(0, math.ceil(s))
	if s >= 60 then
		return string.format("%dm %02ds", s // 60, s % 60)
	end
	return tostring(s) .. "s"
end

return Format
