--[[
	Simple per-key token bucket. Used server-side to throttle remote calls per player.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: {
	_rate: number,
	_burst: number,
	_buckets: { [any]: { tokens: number, last: number } },
}, RateLimiter))

function RateLimiter.new(ratePerSecond: number, burst: number?): RateLimiter
	return setmetatable({
		_rate = ratePerSecond,
		_burst = burst or ratePerSecond,
		_buckets = {},
	}, RateLimiter)
end

function RateLimiter:Allow(key: any): boolean
	local now = os.clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._burst, last = now }
		self._buckets[key] = bucket
	end
	bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.last) * self._rate)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:Clear(key: any)
	self._buckets[key] = nil
end

return RateLimiter
