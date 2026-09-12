local FormatUtil = {}

function FormatUtil.Compact(n: number): string
	n = math.floor(n + 0.5)
	local absN = math.abs(n)
	if absN >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif absN >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif absN >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return FormatUtil.Comma(n)
end

function FormatUtil.Comma(n: number): string
	n = math.floor(n + 0.5)
	local s = tostring(math.abs(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (n < 0 and "-" or "") .. formatted
end

function FormatUtil.Cash(n: number): string
	return "$" .. FormatUtil.Compact(n)
end

function FormatUtil.CashExact(n: number): string
	return "$" .. FormatUtil.Comma(n)
end

function FormatUtil.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

function FormatUtil.Percent(fraction: number): string
	return string.format("%d%%", math.floor(fraction * 100 + 0.0001))
end

function FormatUtil.RoomNumber(id: number): string
	return string.format("#%03d", id)
end

return FormatUtil

