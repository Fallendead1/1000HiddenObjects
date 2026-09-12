local TableUtil = {}

function TableUtil.DeepCopy<T>(t: T): T
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t :: any) do
		copy[k] = TableUtil.DeepCopy(v)
	end
	return copy :: any
end

-- Fill missing keys in `target` from `template` recursively (never overwrites existing values).
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in pairs(template) do
		if target[k] == nil then
			target[k] = TableUtil.DeepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" then
			TableUtil.Reconcile(target[k], v)
		end
	end
	return target
end

function TableUtil.Count(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function TableUtil.Keys<K, V>(t: { [K]: V }): { K }
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	return keys
end

function TableUtil.Shuffle<T>(t: { T }, rng: Random): { T }
	for i = #t, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

return TableUtil
