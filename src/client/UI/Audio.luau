--!strict
-- The client's sound cues (docs/UI-STYLE.md §2.7, docs/DESIGN.md D-053). Every
-- cue goes with something on screen: sound never carries meaning alone. The
-- server never plays audio. Volumes, cooldowns and pitches are presentation
-- numbers, so they live here and not in Sim/Config.
--
--   Audio.CUES                  name -> { id, volume, group, jitter, cooldown,
--                               pitch?, maxLength?, fallback? }
--   Audio.preload()             ContentProvider:PreloadAsync on every cue; never
--                               yields the caller (App.client calls it at start)
--   Audio.play(name, opts?)     opts.pitch, opts.volume: multipliers. Silent when
--                               muted, unknown, cooling down, or 4 cues already play
--   Audio.setMuted(on) · Audio.muted() -> boolean · Audio.changed (signal(muted))
--   Audio.setVolume(0..1)       scales the UI (0.8) and Stingers (0.9) groups
--   Audio.headless              true without a SoundService: play only logs
--   Audio.played                the names of the cues played, oldest first
--                               (the last Audio.LOG_MAX), for specs
--
-- SoundService holds SoundGroups "UI" and "Stingers" and a Folder "Cues" with one
-- Sound per cue (Name = the cue). `play` restarts that Sound with PlaybackSpeed
-- = pitch × opts.pitch × (1 ± jitter), stops it after `maxLength` seconds (long
-- clips would smear over the reveal's beats), and keeps each cue's cooldown and
-- a 4-voice cap. A cue whose asset failed to preload, or whose Sound has not
-- loaded, plays its fallback instead (another cue at a pitch, so the family
-- stays the same), or nothing; it warns once, never errors. A cue with id ""
-- is silent. Mute and volume are session-only (a saved setting needs the
-- profile, a server change).

local Signal = require(script.Parent.Signal)

local Audio = {}

local function service(name: string): any
	local ok, found = pcall(function()
		return game:GetService(name)
	end)
	return if ok then found else nil
end

local soundService: any = service("SoundService")
local contentProvider: any = service("ContentProvider")
local tweenService: any = service("TweenService")

export type Group = "UI" | "Stingers"

export type Fallback = {
	cue: string, -- the cue whose sound stands in
	pitch: number, -- times that cue's pitch
}

export type Cue = {
	id: string, -- "rbxassetid://…", or "" for silent
	volume: number, -- 0..1, Sound.Volume
	group: Group,
	jitter: number, -- ± share of random pitch change per play
	cooldown: number, -- s before the cue may play again
	pitch: number?, -- base PlaybackSpeed (default 1)
	maxLength: number?, -- s, fade and stop after this (long clips)
	fallback: Fallback?,
}

export type PlayOptions = {
	pitch: number?, -- multiplier
	volume: number?, -- multiplier
}

-- Candidate IDs (GAMEPLAN §4.2). All eleven verified to load (PreloadAsync
-- Success) in the published place on Oct 23, 2026, with the lengths noted;
-- auditioning by ear is still pending (docs/TESTING.md). Creator Roblox unless noted.
Audio.CUES = {
	-- Roblox_UI_Small_Click, 0.13 s
	tap = { id = "rbxassetid://15675032796", volume = 0.35, group = "UI", jitter = 0.05, cooldown = 0.06 },
	-- Roblox_UI_Bright_Click, 0.37 s
	select = {
		id = "rbxassetid://15675059323",
		volume = 0.3,
		group = "UI",
		jitter = 0.05,
		cooldown = 0.06,
		fallback = { cue = "tap", pitch = 1.15 },
	},
	-- Roblox_UI_Cute_Pop, 2.70 s: cut at 0.6 s so reveal beats don't smear
	planAdd = {
		id = "rbxassetid://15675055424",
		volume = 0.4,
		group = "UI",
		jitter = 0.05,
		cooldown = 0.08,
		maxLength = 0.6,
		fallback = { cue = "select", pitch = 0.9 },
	},
	-- Roblox_UI_Delete, 0.61 s
	planRemove = {
		id = "rbxassetid://15675075163",
		volume = 0.35,
		group = "UI",
		jitter = 0.05,
		cooldown = 0.08,
		fallback = { cue = "tap", pitch = 0.8 },
	},
	-- Roblox_UI_Indicator, 3.37 s: cut at 0.8 s
	lockIn = {
		id = "rbxassetid://15675085146",
		volume = 0.5,
		group = "UI",
		jitter = 0,
		cooldown = 0.3,
		maxLength = 0.8,
		fallback = { cue = "select", pitch = 0.8 },
	},
	-- Roblox_UI_Delete at 0.75 pitch, 0.61 s
	error = {
		id = "rbxassetid://15675075163",
		volume = 0.4,
		group = "UI",
		jitter = 0.03,
		cooldown = 0.3,
		pitch = 0.75,
		fallback = { cue = "tap", pitch = 0.6 },
	},
	-- Roblox_UI_Small_Click at 1.25 pitch, 0.13 s
	tick = {
		id = "rbxassetid://15675032796",
		volume = 0.3,
		group = "UI",
		jitter = 0,
		cooldown = 0.9,
		pitch = 1.25,
	},
	-- Roblox_UI_Whoosh_02, 0.49 s
	whoosh = { id = "rbxassetid://15675028888", volume = 0.4, group = "UI", jitter = 0.05, cooldown = 0.5 },
	-- Roblox_UI_Tonal_Stinger, 1.47 s
	flip = {
		id = "rbxassetid://15675043410",
		volume = 0.5,
		group = "Stingers",
		jitter = 0.03,
		cooldown = 0.3,
		fallback = { cue = "planAdd", pitch = 0.8 },
	},
	-- "Early Bird - Hit1" (APMOfficial), 2.64 s
	debateWin = {
		id = "rbxassetid://9040476898",
		volume = 0.55,
		group = "Stingers",
		jitter = 0,
		cooldown = 1,
		fallback = { cue = "flip", pitch = 1.2 },
	},
	-- Roblox_UI_Indicator, 3.37 s: cut at 0.8 s; pitch by the leader's total (opts.pitch)
	call = {
		id = "rbxassetid://15675085146",
		volume = 0.45,
		group = "UI",
		jitter = 0,
		cooldown = 0.3,
		maxLength = 0.8,
		fallback = { cue = "select", pitch = 1 },
	},
	-- "Waiting For This Moment" (APMOfficial), 4.94 s; alt 15675016548 Roblox
	-- Piano_Hello (4.04 s). Once per Results screen: the cooldown outlasts it.
	victory = {
		id = "rbxassetid://9039969824",
		volume = 0.6,
		group = "Stingers",
		jitter = 0,
		cooldown = 10,
		fallback = { cue = "flip", pitch = 1.3 },
	},
	-- Roblox_UI_Cute_Goodbye, 0.28 s. Once per Results screen.
	defeat = { id = "rbxassetid://15675081158", volume = 0.5, group = "Stingers", jitter = 0, cooldown = 10 },
} :: { [string]: Cue }

Audio.GROUP_VOLUME = { UI = 0.8, Stingers = 0.9 } :: { [string]: number }
Audio.VOICES = 4 -- cues sounding at once, at most
Audio.FADE = 0.08 -- s, the fade before a maxLength stop
Audio.LOG_MAX = 500 -- entries Audio.played keeps

Audio.headless = soundService == nil
Audio.changed = Signal.new() :: Signal.Signal<boolean>
Audio.played = {} :: { string }

local muted = false
local master = 1
local lastPlayed: { [string]: number } = {} -- cue -> os.clock() of its last play
local voices: { number } = {} -- os.clock() each sounding cue ends
local failed: { [string]: boolean } = {} -- cue names whose asset did not load
local warned: { [string]: boolean } = {}
local tokens: { [string]: number } = {} -- per cue, bumps on every play (for maxLength)
local random = Random.new()

local groups: { [string]: SoundGroup } = {}
local sounds: { [string]: Sound } = {}
local built = false

local function warnOnce(name: string, message: string)
	if not warned[name] then
		warned[name] = true
		warn(`[270] audio: {message}`)
	end
end

-- Makes the SoundGroups, the Cues folder and one Sound per cue (once).
local function build()
	if built or soundService == nil then
		return
	end
	built = true
	for _, name in { "UI", "Stingers" } do
		local group = soundService:FindFirstChild(name)
		if group == nil then
			group = Instance.new("SoundGroup")
			group.Name = name
			group.Parent = soundService
		end
		group.Volume = Audio.GROUP_VOLUME[name] * master
		groups[name] = group
	end
	local folder = soundService:FindFirstChild("Cues")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Cues"
		folder.Parent = soundService
	end
	for name, cue in Audio.CUES do
		if cue.id == "" then
			continue
		end
		local sound = folder:FindFirstChild(name)
		if sound == nil then
			sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = cue.id
			sound.Volume = cue.volume
			sound.SoundGroup = groups[cue.group]
			sound.Parent = folder
		end
		sounds[name] = sound
	end
end

function Audio.preload()
	build()
	if contentProvider == nil or next(sounds) == nil then
		return
	end
	local list: { Instance } = {}
	for _, sound in sounds do
		table.insert(list, sound)
	end
	task.spawn(function()
		pcall(function()
			contentProvider:PreloadAsync(list, function(contentId: string, status: any)
				if status ~= nil and status.Name == "Success" then
					return
				end
				for name, cue in Audio.CUES do
					if cue.id == contentId then
						failed[name] = true
						warnOnce(name, `cue {name} ({contentId}) did not load; using its fallback`)
					end
				end
			end)
		end)
	end)
end

function Audio.muted(): boolean
	return muted
end

function Audio.setMuted(on: boolean)
	if muted == on then
		return
	end
	muted = on
	if on then
		for _, sound in sounds do
			sound:Stop()
		end
		table.clear(voices)
	end
	Audio.changed:Fire(muted)
end

function Audio.setVolume(volume: number)
	master = math.clamp(volume, 0, 1)
	for name, group in groups do
		group.Volume = Audio.GROUP_VOLUME[name] * master
	end
end

-- The Sound to play for cue `name` and the pitch factor it needs: the cue's
-- own when it is ready, else its fallback's (recursively), else nil.
local function resolve(name: string, depth: number): (Sound?, number)
	local cue = Audio.CUES[name]
	if cue == nil or depth > 4 then
		return nil, 1
	end
	local sound: Sound? = sounds[name]
	local ready = sound ~= nil and not failed[name] and (sound :: Sound).IsLoaded
	if ready then
		return sound, cue.pitch or 1
	end
	if sound and not failed[name] then
		warnOnce(name, `cue {name} is not loaded yet; skipped`)
	end
	local fallback = cue.fallback
	if fallback == nil then
		return nil, 1
	end
	local other, pitch = resolve(fallback.cue, depth + 1)
	return other, pitch * fallback.pitch
end

local function log(name: string)
	table.insert(Audio.played, name)
	if #Audio.played > Audio.LOG_MAX then
		table.remove(Audio.played, 1)
	end
end

function Audio.play(name: string, opts: PlayOptions?)
	local cue = Audio.CUES[name]
	if muted or cue == nil or cue.id == "" then
		return
	end
	local now = os.clock()
	local last = lastPlayed[name]
	if last and now - last < cue.cooldown then
		return
	end
	for k = #voices, 1, -1 do
		if voices[k] <= now then
			table.remove(voices, k)
		end
	end
	if #voices >= Audio.VOICES then
		return
	end
	if Audio.headless then
		lastPlayed[name] = now
		log(name)
		return
	end
	build()
	local sound, pitch = resolve(name, 0)
	if sound == nil then
		return
	end
	local jitter = if cue.jitter > 0 then random:NextNumber(-cue.jitter, cue.jitter) else 0
	local speed = pitch * (if opts and opts.pitch then opts.pitch else 1) * (1 + jitter)
	sound.PlaybackSpeed = speed
	sound.Volume = cue.volume * (if opts and opts.volume then opts.volume else 1)
	sound.SoundGroup = groups[cue.group]
	sound.TimePosition = 0
	sound:Play()
	lastPlayed[name] = now
	log(name)
	local length = (sound.TimeLength or 0) / math.max(speed, 0.01)
	if length <= 0 then
		length = 0.5
	end
	if cue.maxLength then
		length = math.min(length, cue.maxLength)
		local key = sound.Name
		tokens[key] = (tokens[key] or 0) + 1
		local token = tokens[key]
		local stopping = sound
		task.delay(cue.maxLength, function()
			if tokens[key] ~= token then
				return -- played again since: that play owns the sound now
			end
			if tweenService then
				pcall(function()
					tweenService:Create(stopping, TweenInfo.new(Audio.FADE), { Volume = 0 }):Play()
				end)
			end
			task.delay(Audio.FADE, function()
				if tokens[key] == token then
					stopping:Stop()
				end
			end)
		end)
	end
	table.insert(voices, now + length)
end

return Audio
