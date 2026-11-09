-- Voiceover for the codex entries. A clip is audio/<entry>.mp3 for the opening and
-- audio/<entry>_<part>.mp3 for each part, so only what the character has earned is read.
--
-- The clips play as sound effects (PlaySoundFile), so the zone music, ambience and the world around
-- go on underneath. Stopping a clip partway needs WowClient64MC.exe: there PlaySoundFile also returns
-- a handle and StopSound(handle) stops it (a stock 3.3.5 client can't stop a PlaySoundFile sound).
-- The voice follows the master and sound effects volume. It goes on when the codex is closed or
-- another entry is opened; it stops when it ends, on Stop, when another entry is played, or on logout.

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

local function finish()
	local was = entry
	stopClip()
	queue, entry, current, endsAt = nil, nil, nil, nil
	frame:SetScript("OnUpdate", nil)
	if was then LC.Fire("AUDIO", was) end
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

function audio.Stop()
	if entry then finish() end
end

-- Reads the clips of an entry one after the other.
function audio.Play(id, clips)
	audio.Stop()
	if #clips == 0 then return end
	queue = {}
	for i, clip in ipairs(clips) do queue[i] = clip end
	entry = id
	frame:SetScript("OnUpdate", tick)
	playNext()
end
