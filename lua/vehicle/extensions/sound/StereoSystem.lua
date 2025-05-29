-- StereoSystem.lua
-- Manages music playback within the vehicle.

local M = {}

-- --- Configuration ---
local MAX_VOLUME = 10
local VOLUME_STEP = 1

-- --- State Variables ---
local tracks = {
    -- Example tracks (replace with actual track loading)
    {title = "Sunset Drive", artist = "Synthwave Kid", album = "Retrowave Hits", duration = 240},
    {title = "Midnight City", artist = "M83", album = "Hurry Up, We're Dreaming", duration = 200},
    {title = "Nightcall", artist = "Kavinsky", album = "OutRun", duration = 250},
    {title = "A Real Hero", artist = "College & Electric Youth", album = "Drive Soundtrack", duration = 270}
}
local currentTrackIndex = 1
local isSystemOn = false
local isPlaying = false
local isPaused = false -- To distinguish between stopped and paused
local isShuffleOn = false
local repeatMode = "off" -- "off", "song", "playlist"
local currentVolume = 5
local playbackPosition = 0 -- Seconds into the current track
local playbackTimer = 0 -- Timer for simulating playback

-- --- Helper Functions ---
local function getTrackCount()
    return #tracks
end

local function getCurrentTrack()
    if getTrackCount() == 0 or currentTrackIndex < 1 or currentTrackIndex > getTrackCount() then
        return nil
    end
    return tracks[currentTrackIndex]
end

-- --- UI Update Functions (Lua to JavaScript) ---
-- These functions call global JavaScript functions defined in music_player.js
local function updateUiTrackInfo(title, artist, album, trackNumber, totalTracks)
    if not isSystemOn then return end
    local titleStr = title or "N/A"
    local artistStr = artist or "N/A"
    local albumStr = album or "N/A"
    local trackNumStr = trackNumber or 0
    local totalTracksStr = totalTracks or 0
    -- Ensure strings are properly escaped for JavaScript
    local jsCommand = string.format("if(window.updateTrackDisplay) { window.updateTrackDisplay('%s', '%s', '%s', %d, %d); }",
                                    titleStr:gsub("'", "\\'"), artistStr:gsub("'", "\\'"), albumStr:gsub("'", "\\'"),
                                    trackNumStr, totalTracksStr)
    gui.executeJS(jsCommand)
end

local function updateUiPlaybackState(playing, paused, atEnd)
    if not isSystemOn then return end
    local jsCommand = string.format("if(window.setPlaybackStateDisplay) { window.setPlaybackStateDisplay(%s, %s, %s); }",
                                    tostring(playing), tostring(paused), tostring(atEnd))
    gui.executeJS(jsCommand)
end

local function updateUiVolume(volumeLevel, maxVol)
    if not isSystemOn then return end
    local jsCommand = string.format("if(window.setVolumeDisplay) { window.setVolumeDisplay(%.2f, %.2f); }",
                                    volumeLevel / maxVol, 1.0) -- UI expects 0-1 range
    gui.executeJS(jsCommand)
end

local function updateUiShuffleMode(shuffleOn)
    if not isSystemOn then return end
    local jsCommand = string.format("if(window.setShuffleDisplay) { window.setShuffleDisplay(%s); }", tostring(shuffleOn))
    gui.executeJS(jsCommand)
end

local function updateUiRepeatMode(repeatModeStr)
    if not isSystemOn then return end
    local jsCommand = string.format("if(window.setRepeatDisplay) { window.setRepeatDisplay('%s'); }", repeatModeStr:gsub("'", "\\'"))
    gui.executeJS(jsCommand)
end

local function showUiNotification(message, type, duration)
    -- if not isSystemOn and type ~= "systemStatus" then return end -- Allow some system messages even if off
    local messageStr = message or ""
    local typeStr = type or "info"
    local durationMs = duration or 3000
    local jsCommand = string.format("if(window.showNotificationInUi) { window.showNotificationInUi('%s', '%s', %d); }",
                                    messageStr:gsub("'", "\\'"), typeStr:gsub("'", "\\'"), durationMs)
    gui.executeJS(jsCommand)
end

-- --- Internal Logic ---
local function displayCurrentTrack()
    if not isSystemOn then
        showUiNotification("Stereo system is off.", "systemStatus", 2000)
        updateUiTrackInfo("System Off", "", "", 0, getTrackCount()) -- Clear track info
        updateUiPlaybackState(false, false, false)
        return
    end

    local track = getCurrentTrack()
    if track then
        updateUiTrackInfo(track.title, track.artist, track.album, currentTrackIndex, getTrackCount())
        updateUiPlaybackState(isPlaying, isPaused, false) -- Assuming not atEnd unless explicitly set
    else
        updateUiTrackInfo("No Track", "N/A", "N/A", 0, getTrackCount())
        updateUiPlaybackState(false, false, true) -- No track means at end of (empty) playlist
        showUiNotification("No tracks available or selection out of bounds.", "warning", 3000)
    end
end

local function stopPlayback()
    isPlaying = false
    isPaused = false
    playbackPosition = 0
    -- Stop any timers, etc.
    displayCurrentTrack()
end

local function startPlayback(trackIdx)
    if getTrackCount() == 0 then
        showUiNotification("Music folder empty. Cannot play.", "warning", 3000)
        stopPlayback()
        return
    end

    currentTrackIndex = trackIdx
    if currentTrackIndex < 1 then currentTrackIndex = getTrackCount() end
    if currentTrackIndex > getTrackCount() then currentTrackIndex = 1 end

    isPlaying = true
    isPaused = false
    playbackPosition = 0
    local track = getCurrentTrack()
    if track then
        showUiNotification("Playing: " .. track.title, "trackChange", 3000)
    end
    displayCurrentTrack()
    -- Reset and start playback timer if implementing simulated playback
end


-- --- Public API Functions (Callable from UI via bngApi.engineLua) ---
function M.toggleStereoSystem()
    isSystemOn = not isSystemOn
    if isSystemOn then
        showUiNotification("Stereo System ON", "systemStatus", 2000)
        -- Update all UI elements to reflect current state
        displayCurrentTrack()
        updateUiVolume(currentVolume, MAX_VOLUME)
        updateUiShuffleMode(isShuffleOn)
        updateUiRepeatMode(repeatMode)
    else
        stopPlayback() -- Also updates UI for system off state
        showUiNotification("Stereo System OFF", "systemStatus", 2000)
    end
end

function M.playPause()
    if not isSystemOn or getTrackCount() == 0 then
        showUiNotification("Cannot play/pause. System off or no tracks.", "warning", 2000)
        return
    end

    if isPlaying then
        isPlaying = false
        isPaused = true
        showUiNotification("Playback Paused", "info", 2000)
    else
        -- If was paused, resume. If was stopped (e.g. end of track or first play), start current/first track.
        isPlaying = true
        isPaused = false
        if playbackPosition == 0 then -- Indicates it was stopped or new track
             local track = getCurrentTrack()
             if track then showUiNotification("Playing: " .. track.title, "trackChange", 3000) end
        else
             showUiNotification("Playback Resumed", "info", 2000)
        end
    end
    displayCurrentTrack() -- This will call updateUiPlaybackState
end

function M.nextTrack()
    if not isSystemOn or getTrackCount() == 0 then return end
    local newIndex = currentTrackIndex + 1
    if newIndex > getTrackCount() then
        if repeatMode == "playlist" then
            newIndex = 1
        else
            showUiNotification("End of playlist.", "info", 2000)
            stopPlayback() -- Stop at end of playlist if not repeating all
            updateUiPlaybackState(false, false, true) -- Explicitly set atEnd
            return
        end
    end
    startPlayback(newIndex)
end

function M.previousTrack()
    if not isSystemOn or getTrackCount() == 0 then return end
    local newIndex = currentTrackIndex - 1
    if newIndex < 1 then
        if repeatMode == "playlist" then
            newIndex = getTrackCount()
        else
            showUiNotification("Beginning of playlist.", "info", 2000)
            -- Potentially stop or just stay at first track, depending on desired behavior
            currentTrackIndex = 1
            playbackPosition = 0
            if not isPlaying then isPaused = true end -- if it wasn't playing, mark as paused at start
            displayCurrentTrack()
            return
        end
    end
    startPlayback(newIndex)
end

function M.toggleShuffleMode()
    if not isSystemOn then return end
    isShuffleOn = not isShuffleOn
    updateUiShuffleMode(isShuffleOn)
    showUiNotification("Shuffle " .. (isShuffleOn and "ON" or "OFF"), "info", 2000)
    -- If implementing true shuffle, would need to re-shuffle playlist here
end

function M.toggleRepeatMode()
    if not isSystemOn then return end
    if repeatMode == "off" then
        repeatMode = "song"
    elseif repeatMode == "song" then
        repeatMode = "playlist"
    else
        repeatMode = "off"
    end
    updateUiRepeatMode(repeatMode)
    showUiNotification("Repeat Mode: " .. repeatMode, "info", 2000)
end

function M.setVolume(volume) -- volume is expected to be 0-1 from UI
    if not isSystemOn then return end
    currentVolume = math.max(0, math.min(MAX_VOLUME, math.floor(volume * MAX_VOLUME)))
    updateUiVolume(currentVolume, MAX_VOLUME)
    -- showUiNotification("Volume: " .. currentVolume .. "/" .. MAX_VOLUME, "info", 1500) -- Can be noisy
end

-- --- Lifecycle Functions (Example) ---
local function onExtensionLoaded()
    -- Initial setup when the extension is loaded
    -- For now, we assume the system starts off. UI will request initial state.
    -- Or, we could send an initial "off" state.
    isSystemOn = false -- Start with system off
    updateUiTrackInfo("System Off", "", "", 0, getTrackCount())
    updateUiPlaybackState(false, false, false)
    updateUiVolume(currentVolume, MAX_VOLUME)
    updateUiShuffleMode(isShuffleOn)
    updateUiRepeatMode(repeatMode)
    showUiNotification("Stereo System Ready (Off)", "systemStatus", 3000)
end

-- --- Simulated Playback (Placeholder for actual audio engine events) ---
local function onUpdate(dt)
    if isSystemOn and isPlaying and not isPaused then
        playbackTimer = playbackTimer + dt
        playbackPosition = playbackPosition + dt

        local currentTrackObj = getCurrentTrack()
        if currentTrackObj and currentTrackObj.duration and playbackPosition >= currentTrackObj.duration then
            if repeatMode == "song" then
                startPlayback(currentTrackIndex) -- Replay current song
            elseif isShuffleOn then
                startPlayback(math.random(1, getTrackCount())) -- Play random next song
            else
                M.nextTrack() -- Will handle playlist repeat or stop at end
            end
        end
    end
end

-- --- Expose Public Functions ---
M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate -- If you have a game loop update function

-- For UI to request full state update
function M.requestFullStateUpdate()
    if not isSystemOn then
        showUiNotification("Stereo system is off.", "systemStatus", 2000)
        updateUiTrackInfo("System Off", "", "", 0, getTrackCount())
        updateUiPlaybackState(false, false, false)
        updateUiVolume(currentVolume, MAX_VOLUME)
        updateUiShuffleMode(isShuffleOn)
        updateUiRepeatMode(repeatMode)
        return
    end
    displayCurrentTrack()
    updateUiVolume(currentVolume, MAX_VOLUME)
    updateUiShuffleMode(isShuffleOn)
    updateUiRepeatMode(repeatMode)
end


-- --- Track Scanning (Placeholder) ---
function M.scanForTracks(path)
    -- This would ideally scan a directory for music files
    -- For now, it just re-uses the hardcoded list or clears it.
    -- Example:
    -- tracks = {} -- Clear existing
    -- add files found in path to tracks table
    showUiNotification("Scanning for tracks (Not Implemented)", "info", 2000)
    -- After scanning, update UI
    if getTrackCount() > 0 then
        currentTrackIndex = 1
        startPlayback(currentTrackIndex) -- Or just displayCurrentTrack() if not auto-playing
    else
        stopPlayback()
        updateUiTrackInfo("No Tracks Found", "", "", 0, 0)
    end
end

return M
