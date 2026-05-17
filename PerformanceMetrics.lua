-- PerformanceMetrics.lua - Server/Client shared lightweight telemetry helper
-- Disabled by default unless GameConfig.PerfMetricsEnabled == true

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PerformanceMetrics = {}

local ENABLED = GameConfig.PerfMetricsEnabled == true
local REPORT_INTERVAL = tonumber(GameConfig.PerfMetricsReportInterval) or 15
local MAX_SAMPLES_PER_SCOPE = tonumber(GameConfig.PerfMetricsSampleCap) or 64

local scopes = {} -- [scope] = { count, totalMs, maxMs, samples={}, counters={} }
local lastReportAt = tick()

local function getScope(scope)
	local s = scopes[scope]
	if s then return s end
	s = {
		count = 0,
		totalMs = 0,
		maxMs = 0,
		samples = {},
		counters = {},
	}
	scopes[scope] = s
	return s
end

local function percentile95(samples)
	if #samples == 0 then return 0 end
	local sorted = table.clone(samples)
	table.sort(sorted)
	local idx = math.clamp(math.ceil(#sorted * 0.95), 1, #sorted)
	return sorted[idx]
end

local function maybeReport()
	if not ENABLED then return end
	local now = tick()
	if now - lastReportAt < REPORT_INTERVAL then return end
	lastReportAt = now

	for scope, data in pairs(scopes) do
		if data.count > 0 then
			local avg = data.totalMs / data.count
			local p95 = percentile95(data.samples)
			local counterParts = {}
			for key, value in pairs(data.counters) do
				counterParts[#counterParts + 1] = key .. "=" .. tostring(value)
				data.counters[key] = 0
			end
			local counters = (#counterParts > 0) and (" | " .. table.concat(counterParts, ", ")) or ""
			warn(string.format(
				"[Perf] %s count=%d avg=%.2fms p95=%.2fms max=%.2fms%s",
				scope,
				data.count,
				avg,
				p95,
				data.maxMs,
				counters
			))
			data.count = 0
			data.totalMs = 0
			data.maxMs = 0
			table.clear(data.samples)
		end
	end
end

function PerformanceMetrics.IsEnabled()
	return ENABLED
end

function PerformanceMetrics.Begin()
	if not ENABLED then return nil end
	return os.clock()
end

function PerformanceMetrics.End(scope, token)
	if not ENABLED or not token then return 0 end
	local elapsedMs = (os.clock() - token) * 1000
	local data = getScope(scope)
	data.count += 1
	data.totalMs += elapsedMs
	if elapsedMs > data.maxMs then
		data.maxMs = elapsedMs
	end
	if #data.samples >= MAX_SAMPLES_PER_SCOPE then
		table.remove(data.samples, 1)
	end
	data.samples[#data.samples + 1] = elapsedMs
	maybeReport()
	return elapsedMs
end

function PerformanceMetrics.Count(scope, counterName, delta)
	if not ENABLED then return end
	local data = getScope(scope)
	data.counters[counterName] = (data.counters[counterName] or 0) + (delta or 1)
end

function PerformanceMetrics.Observe(scope, valueName, value)
	if not ENABLED then return end
	local data = getScope(scope)
	data.counters[valueName] = value
end

if RunService:IsClient() or RunService:IsServer() then
	RunService.Heartbeat:Connect(function()
		maybeReport()
	end)
end

return PerformanceMetrics
