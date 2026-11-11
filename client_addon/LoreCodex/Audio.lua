-- Voiceover for the codex entries. A clip is audio/<entry>.mp3 for the opening and
-- audio/<entry>_<part>.mp3 for each part, so only what the character has earned is read.
--
-- The clips play as sound effects (PlaySoundFile), so the zone music, ambience and the world around
-- go on underneath. Stopping a clip partway needs WowClient64MC.exe: there PlaySoundFile also returns
-- a handle and StopSound(handle) stops it (a stock 3.3.5 client can't stop a PlaySoundFile sound).
-- The voice follows the master and sound effects volume. It goes on when the codex is closed or
-- another entry is opened; it stops when it ends, on Stop, when another entry is played, or on logout.
--
-- Without the codex open: an entry can be read straight from a discovery (the "read new lore aloud" option) or a
-- click on its banner (the "banners read aloud" option). A new entry is read whole; an entry that grew, only what
-- this character hasn't read of it yet. Discoveries that come while something is being read wait their turn (a few at
-- most) instead of cutting it off.

local LC = LoreCodex

local DIR = "Interface\\AddOns\\LoreCodex\\audio\\"

local audio = {}
LC.Audio = audio

local manifest = LoreCodexAudio or {}

-- What is playing: the clip names still to play, the one playing, its sound handle and when it
-- ends, the entry.
local queue, entry, current, handle, endsAt = nil, nil, nil, nil, nil

-- The clip for an entry's opening (no part) or one of its parts.
function audio.Clip(id, part)
	return part and (id .. "_" .. part) or tostring(id)
end

function audio.Has(clip)
	return manifest[clip] ~= nil
end

-- The entry being read aloud, and the clip of it that is playing now.
function audio.Entry()
	return entry
end

function audio.Current()
	return current
end

local frame = CreateFrame("Frame")

local function stopClip()
	if handle and StopSound then StopSound(handle) end
	handle = nil
end

local announceNext

local function finish()
	local was = entry
	stopClip()
	queue, entry, current, endsAt = nil, nil, nil, nil
	frame:SetScript("OnUpdate", nil)
	if was then LC.Fire("AUDIO", was) end
	-- the next discovery waiting to be read (after a clip set that ended by itself; Stop clears them first)
	if announceNext then announceNext() end
end

local function playNext()
	local name = table.remove(queue, 1)
	if not name then finish() return end
	local _, h = PlaySoundFile(DIR .. name .. ".mp3")
	handle = h
	current = name
	-- The next clip starts after the length in the manifest; a sound effect plays once, so the timer
	-- only chains the clips.
	endsAt = GetTime() + manifest[name]
	LC.Fire("AUDIO", entry)
end

local function tick()
	if endsAt and GetTime() >= endsAt then
		handle = nil -- ended on its own
		playNext()
	end
end

frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function () if entry then finish() end end)

-- Discoveries waiting to be read aloud: { id, newOnly }.
local waiting = {}
local MAX_WAITING = 5

-- Stopped by hand: what waits goes too.
function audio.Stop()
	waiting = {}
	if entry then finish() end
end

-- The clips of an entry for this character, once its text is loaded (done(clips), maybe empty): the opening and each
-- part it shows. newOnly: only the parts not read yet (the whole entry when it was never opened; every part when it
-- was read with an older version of the addon, which kept no parts).
function audio.ClipsFor(id, newOnly, done)
	LC.LoadText(id, function (t)
		local clips = {}
		if not t or not t.shown then done(clips) return end
		local fresh = not LC.WasOpened(id)
		local read = LC.ReadParts(id)
		local opening = audio.Clip(id)
		if (not newOnly or fresh) and audio.Has(opening) then table.insert(clips, opening) end
		for _, part in ipairs(t.shown) do
			local clip = audio.Clip(id, part)
			if audio.Has(clip) and (not newOnly or fresh or not (read and read[part])) then table.insert(clips, clip) end
		end
		done(clips)
	end)
end

-- Reads an entry without the codex: the whole of it, or (newOnly) what is new in it. Nothing when it has no clip.
function audio.PlayEntry(id, newOnly)
	audio.ClipsFor(id, newOnly, function (clips)
		if #clips > 0 then audio.Play(id, clips) end
	end)
end

-- A discovery to read aloud: now, or after what is being read.
function audio.Announce(id, newOnly)
	if entry then
		for _, w in ipairs(waiting) do
			if w.id == id then w.newOnly = w.newOnly and newOnly return end
		end
		if #waiting < MAX_WAITING then table.insert(waiting, { id = id, newOnly = newOnly }) end
		return
	end
	audio.ClipsFor(id, newOnly, function (clips)
		if #clips == 0 then return end
		-- something started while the text loaded: this one waits after all
		if entry then
			if #waiting < MAX_WAITING then table.insert(waiting, { id = id, newOnly = newOnly }) end
			return
		end
		audio.Play(id, clips)
	end)
end

announceNext = function ()
	local w = table.remove(waiting, 1)
	if w then audio.Announce(w.id, w.newOnly) end
end

-- Reads the clips of an entry one after the other.
function audio.Play(id, clips)
	local keep = waiting
	audio.Stop()
	waiting = keep
	if #clips == 0 then return end
	queue = {}
	for i, clip in ipairs(clips) do queue[i] = clip end
	entry = id
	frame:SetScript("OnUpdate", tick)
	playNext()
end
