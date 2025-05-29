local M = {}

local speaker
-- Removed msgDirNotExists, msgShorted, msgEmpty, msgVolumeAt, msgVolumeMuted, msgShuffleOn
local tracksFolder = "music"
-- Removed guiActive, guiShuffle, guiRepeat, guiFile, guiPlaying, guiVolume, guiTrackCount
local cachedTracks = {}
local trackFiles = {}
local shuffleIndex
local caching
local cachePos
local cacheSize = 3
local halfCacheSize
local nextDownTime = 0
local nextUpTime = 0
local prevDownTime = 0
local prevUpTime = 0
local wasHolding
local wasHolding2
local dirExists
local shuffle
local delayedPlay = false
local delayedPlayTime = 0
local loopedOnce
local profile = "AudioMusic2D"
local shortedInWater
local shortAtTime = 0
local engine
local vehicleElectrics
local delayedVolUp = false
local paused
local delayedVolUpTime = 0
local MAX_VOLUME = 16
local DESKTOP_VOLUME = 6
local MIN_VOLUME_VALUE = .001575
local VOLUME_QUANTA = 1
local volume
local volumeDownTime
local prevVolumeDownTime
local volumeUpTime
local prevVolumeUpTime
local volumeButtonDown
local volumeButtonUp
local wasOn
local wasPlaying
local displayedDetails
local MSG_DURATION = 5 -- This might be reused for showUiNotification duration, or removed if not.
local initialized = false
local trackIndex
local isVehicle
local playDuration
local repeatMode
local restartFromBeginning
local endOfPlayList
local file
local fileIsOpen
local fileHelper
local metaString
local mp3Duration
local wavDuration
local id3V1
local id3V2
local ape
local lyrics
local displayedRecoveredMessage

local fileTypes = {}
fileTypes[".mp3"] = true
fileTypes[".wav"] = true

-- --- START: New UI Update Functions ---
local function escapeJsString(str)
    if type(str) ~= "string" then return "" end
    return str:gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "\\r")
end

local function updateUiTrackInfo(title, artist, album, currentTrackNum, totalTracksNum)
    local titleStr = escapeJsString(title or "N/A")
    local artistStr = escapeJsString(artist or "N/A")
    local albumStr = escapeJsString(album or "N/A")
    local trackNum = currentTrackNum or 0
    local totalTracksCount = totalTracksNum or 0
    local jsCommand = string.format("if(window.updateTrackDisplay) { window.updateTrackDisplay('%s', '%s', '%s', %d, %d); }",
                                    titleStr, artistStr, albumStr, trackNum, totalTracksCount)
    gui.executeJS(jsCommand)
end

-- Modified to include systemActive
local function updateUiPlaybackState(isPlayingState, isPausedState, isAtEndState, systemIsActive)
    local jsCommand = string.format("if(window.setPlaybackStateDisplay) { window.setPlaybackStateDisplay(%s, %s, %s, %s); }",
                                    tostring(isPlayingState), tostring(isPausedState), tostring(isAtEndState), tostring(systemIsActive))
    gui.executeJS(jsCommand)
end

local function updateUiVolume(volumeLevel, maxSystemVolume)
    local normalizedVolume = 0
    if maxSystemVolume > 0 and volumeLevel >= MIN_VOLUME_VALUE then -- MIN_VOLUME_VALUE is effectively mute
        normalizedVolume = volumeLevel / maxSystemVolume
    end
    -- Ensure it's between 0 and 1 for the UI slider
    normalizedVolume = math.max(0, math.min(1, normalizedVolume))
    local jsCommand = string.format("if(window.setVolumeDisplay) { window.setVolumeDisplay(%.2f, 1.0); }", normalizedVolume) -- maxVolume for UI is always 1.0
    gui.executeJS(jsCommand)
end

local function updateUiShuffleMode(isShuffleOnState)
    local jsCommand = string.format("if(window.setShuffleDisplay) { window.setShuffleDisplay(%s); }", tostring(isShuffleOnState))
    gui.executeJS(jsCommand)
end

local function updateUiRepeatMode(repeatModeNum)
    local modeStr = "off"
    if repeatModeNum == 2 then modeStr = "playlist"
    elseif repeatModeNum == 3 then modeStr = "song"
    end
    local jsCommand = string.format("if(window.setRepeatDisplay) { window.setRepeatDisplay('%s'); }", modeStr)
    gui.executeJS(jsCommand)
end

local function showUiNotification(message, type, duration)
    local messageStr = escapeJsString(message or "")
    local typeStr = escapeJsString(type or "info")
    local durationMs = duration or 3000
    local jsCommand = string.format("if(window.showNotificationInUi) { window.showNotificationInUi('%s', '%s', %d); }",
                                    messageStr, typeStr, durationMs)
    gui.executeJS(jsCommand)
end
-- --- END: New UI Update Functions ---

local function luaMod(x, mod)
	local y = x % mod
	if y == 0 then
		y = mod
	end
	return y
end

local function swapElements(arr, i1, i2)
	local copy = deepcopy(arr[i1])
	arr[i1] = deepcopy(arr[i2])
	arr[i2] = deepcopy(copy)
end

local function cacheTrackIndex()
	if caching then
		return luaMod(trackIndex - cachePos + 1, #trackFiles)
	else
		return trackIndex
	end
end

local function displayTrack(state)
    -- This function is largely replaced by direct calls to updateUiTrackInfo and updateUiPlaybackState
    -- However, we still need to update the metaString for internal use if necessary,
    -- and decide what state to pass to the UI.

    local currentTr = trackFiles[trackIndex]
    if not currentTr then
        updateUiTrackInfo("No Track", "N/A", "N/A", 0, #trackFiles)
        updateUiPlaybackState(false, paused, true, electrics.values.stereoSystemOn == 1 and vehicleElectrics.values.ignition == true and not shortedInWater) -- No track implies at end
        return
    end

    buildMetaDataString() -- Ensure metaString is up to date

    local systemIsCurrentlyActive = electrics.values.stereoSystemOn == 1 and vehicleElectrics.values.ignition == true and not shortedInWater
    local isActuallyPlaying = (state == 'playing' or state == 'resuming') and not paused and systemIsCurrentlyActive
    updateUiTrackInfo(currentTr.title, currentTr.artist, currentTr.album, trackIndex, #trackFiles)
    updateUiPlaybackState(isActuallyPlaying, paused, endOfPlayList, systemIsCurrentlyActive)

    if state == 'playing' or state == 'resuming' then
        if currentTr.version1LayerI then
            showUiNotification('Warning - ' .. string.sub(currentTr.file, 8) .. ' contains MPEG-1 Layer I frame, may not be supported.', 'warning', MSG_DURATION * 1000)
        end
        if currentTr.duration ~= currentTr.duration then -- Checks for NaN
            showUiNotification('Error - could not obtain duration of ' .. string.sub(currentTr.file, 8), 'error', MSG_DURATION * 1000)
        end
    elseif state == 'pausing' then
         showUiNotification("Track " .. trackIndex .. " paused.", "info", MSG_DURATION * 1000)
    elseif state == 'stopping' then
         showUiNotification("Playback stopped.", "info", MSG_DURATION * 1000)
    -- Other states like 'current', 'resetting' might just update info without specific notification,
    -- or can have specific notifications if desired.
    end
end

local function displayRepeatMode()
    -- Replaced by updateUiRepeatMode(repeatMode)
    updateUiRepeatMode(repeatMode)
end

local function displayState(notifyDirectoryIssues)
    -- This function's messages are now handled by showUiNotification
    if isVehicle then
        if shortedInWater then
            showUiNotification("Stereo: system shorted", "error", MSG_DURATION * 1000) -- Type "error" could also set systemActive=false in JS
        elseif vehicleElectrics.values.ignition ~= true then
            showUiNotification("Stereo: ignition is off", "ignition_off", MSG_DURATION * 1000)
        elseif not notifyDirectoryIssues then
            showUiNotification('Stereo: system is off', "system_off", MSG_DURATION * 1000)
        end
        if notifyDirectoryIssues then
            if dirExists and #trackFiles == 0 then
                showUiNotification("Stereo: the music folder is empty", "warning", MSG_DURATION * 1000)
            elseif not dirExists then
                showUiNotification("Stereo: the music folder doesn't exist", "error", MSG_DURATION * 1000)
            end
        end
    end
end

local function toggleRepeatMode()
	if #trackFiles > 0 and vehicleElectrics.values.ignition == true and not shortedInWater and isVehicle then
        repeatMode = repeatMode + 1
        if repeatMode == 4 then
            repeatMode = 1
        end
        updateUiRepeatMode(repeatMode) -- Updated
        -- Show notification for the mode change
        local modeStr = "off"
        if repeatMode == 2 then modeStr = "playlist"
        elseif repeatMode == 3 then modeStr = "song" end
        showUiNotification("Repeat mode: " .. modeStr, "info", MSG_DURATION * 1000)
    else
        displayState(true)
    end
end

local function buildMetaDataString()
    metaString = ""
    local track = trackFiles[trackIndex]
    if track.title ~= nil then
        metaString = metaString .. "Title: " .. track.title
    end
    if track.artist ~= nil then
        metaString = metaString .. "\nArtist: " .. track.artist
    end
    if track.album ~= nil then
        metaString = metaString .. "\nAlbum: " .. track.album
    end
    if track.trck ~= nil then
        metaString = metaString .. "\nTrack: " .. track.trck
    end
    if track.genre ~= nil then
        metaString = metaString .. "\nGenre: " .. track.genre
    end
    if track.year ~= nil then
        metaString = metaString .. "\nYear: " .. track.year
    end
end

local function displayDetails()
    if electrics.values.stereoSystemOn == 1 then
        displayedDetails = true
        updateUiVolume(volume, MAX_VOLUME) -- Updated
        updateUiShuffleMode(shuffle)       -- Updated
        updateUiRepeatMode(repeatMode)     -- Updated

        if not delayedPlay then
            local currentTr = trackFiles[trackIndex]
            if paused and not endOfPlayList and currentTr then
                updateUiTrackInfo(currentTr.title, currentTr.artist, currentTr.album, trackIndex, #trackFiles)
                updateUiPlaybackState(false, true, false, true)
                showUiNotification("Playback paused.", "info", MSG_DURATION*1000)
            elseif endOfPlayList then
                showUiNotification("Stereo: reached the end of the playlist", "info", MSG_DURATION * 1000)
                if currentTr then  updateUiTrackInfo(currentTr.title, currentTr.artist, currentTr.album, trackIndex, #trackFiles) end
                updateUiPlaybackState(false, paused, true, true)
            end
        end
    end
end

local function increaseVolume()
    if electrics.values.stereoSystemOn == 1 and isVehicle then
        if volume < MAX_VOLUME and volume >= VOLUME_QUANTA then
            volume = volume + VOLUME_QUANTA
        elseif volume < VOLUME_QUANTA then
            volume = VOLUME_QUANTA
        end
        if not paused and cachedTracks[cacheTrackIndex()] and cachedTracks[cacheTrackIndex()].sfx then
            obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, volume)
        end
        updateUiVolume(volume, MAX_VOLUME) -- Updated
    else
        displayState(false) -- This will show a notification like "system off"
    end
end

local function decreaseVolume()
    if electrics.values.stereoSystemOn == 1 and isVehicle then
        if volume > VOLUME_QUANTA then
            volume = volume - VOLUME_QUANTA
        elseif volume == VOLUME_QUANTA then
            volume = MIN_VOLUME_VALUE -- Effectively mute
        end
        if not paused and cachedTracks[cacheTrackIndex()] and cachedTracks[cacheTrackIndex()].sfx then
            obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, volume)
        end
        updateUiVolume(volume, MAX_VOLUME) -- Updated
    else
        displayState(false) -- This will show a notification like "system off"
    end
end

-- New function to set volume from UI (0.0 to 1.0)
function M.setVolume(uiVolume)
    if electrics.values.stereoSystemOn == 1 and isVehicle then
        -- Scale UI volume (0-1) to system volume (MIN_VOLUME_VALUE - MAX_VOLUME)
        if uiVolume <= 0.01 then -- Treat very low values as mute
            volume = MIN_VOLUME_VALUE
        else
            volume = uiVolume * MAX_VOLUME
        end
        -- Clamp volume to system limits
        volume = math.max(MIN_VOLUME_VALUE, math.min(MAX_VOLUME, volume))

        if not paused and cachedTracks[cacheTrackIndex()] and cachedTracks[cacheTrackIndex()].sfx then
            obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, volume)
        end
        updateUiVolume(volume, MAX_VOLUME)
        -- showUiNotification("Volume set to " .. string.format("%.0f", uiVolume * 100) .. "%", "info", 1500)
    else
        -- displayState(false) -- Already handled by button checks in UI potentially
        showUiNotification("Cannot set volume: System is off or not available.", "warning", 2000)
    end
end


local function decreaseVolumeButtonDown()
    volumeDownTime = os.time()
    prevVolumeDownTime = volumeDownTime
    volumeButtonDown = true
end

local function decreaseVolumeButtonUp()
    volumeDownTime = 0
    volumeButtonDown = false
end

local function increaseVolumeButtonDown()
    volumeUpTime = os.time()
    prevVolumeUpTime = volumeUpTime
    volumeButtonUp = true
end

local function increaseVolumeButtonUp()
    volumeUpTime = 0
    volumeButtonUp = false
end

local function getMetaData(fromShuffle)
    if fileIsOpen then
        file:close()
        fileIsOpen = false
    end
    if trackFiles[trackIndex].gettingMetaData then
        file = io.open(trackFiles[trackIndex].file, 'rb')
        fileIsOpen = true
        if trackFiles[trackIndex].endOfAudio == -1 then
            trackFiles[trackIndex].endOfAudio = fileHelper.fileSize(file)
            trackFiles[trackIndex].fileSeek = 0
        end
    end
    if trackFiles[trackIndex].detectedTags then
        buildMetaDataString()
        if electrics.values.stereoSystemOn == 1 then
            if fromShuffle then
                -- displayTrack('current') -- This implies just updating info, not starting playback
                local currentTr = trackFiles[trackIndex]
                if currentTr then
                    updateUiTrackInfo(currentTr.title, currentTr.artist, currentTr.album, trackIndex, #trackFiles)
                    updateUiPlaybackState(not paused, paused, endOfPlayList)
                end
            elseif not fromShuffle then
                displayTrack('playing') -- This implies starting playback and updating info
            end
        end
    end
end

local function systemPlayTrack(track)
    wasPlaying = true
    endOfPlayList = false
    restartFromBeginning = false
    if track and track.sfx then
        obj:setVolume(track.sfx, volume)
        obj:setPitch(track.sfx, 1)
        obj:cutSFX(track.sfx) -- Cut before playing to ensure it starts from beginning
        getMetaData(false) -- Updates metaString and calls displayTrack('playing') internally
        obj:playSFX(track.sfx)
        paused = false
        playDuration = 0
        -- displayTrack('playing') is called within getMetaData if conditions are met
    else
        showUiNotification("Error: Track data or SFX missing.", "error", 3000)
        updateUiPlaybackState(false, true, true, false) -- Paused, at end, system not active
    end
end

local function setNextDownTime()
	nextDownTime = os.time()
end

local function setPrevDownTime()
	prevDownTime = os.time()
end

local function setNextUpTime()
	if wasHolding then
		wasHolding = false
	else
		nextUpTime = os.time()
	end
end

local function setPrevUpTime()
	if wasHolding2 then
		wasHolding2 = false
	else
		prevUpTime = os.time()
	end
end

local function loadCacheAndGetFiles(directory)
	trackFiles = {}
    if fileIsOpen then
        file:close()
        fileIsOpen = false
    end
	if FS:directoryExists(directory) then
		caching = true
		dirExists = true
		local files = FS:findFiles(directory, "*.*", -1, true, false)
        local i = 1
		for _, file in ipairs(files) do
			local extension = string.lower(string.sub(file, -4))
			if fileTypes[extension] then
				local tr = {}
				tr.file = file
				tr.index = i
                tr.duration = 0
                tr.gettingMetaData = true
                tr.calculating = true
                tr.fileType = extension
                tr.detectedTags = false
                tr.title = string.sub(file, 8, -5)
                tr.artist = nil
                tr.album = nil
                tr.trck = nil
                tr.year = nil
                tr.genre = nil
                tr.albumArtist = nil
                tr.albumPos = nil
                tr.checkForLyrics = false
                tr.version1LayerI = false
                tr.version1LayerIDisplayed = false
                tr.endOfAudio = -1
                tr.fileSeek = -1
				table.insert(trackFiles, tr)
                i = i + 1
			end
		end
		if #trackFiles <= cacheSize then
			caching = false
		end
		if caching then
			cachePos = #trackFiles + 1 - halfCacheSize
			for i = 1, cacheSize do
				local index = luaMod(i - halfCacheSize, #trackFiles)
				cachedTracks[i] = {}
				cachedTracks[i].sfx = nil
				cachedTracks[i].name = trackFiles[index].file
			end
		else
			for i = 1, #trackFiles, 1 do
				cachedTracks[i] = {}
				cachedTracks[i].sfx = nil
				cachedTracks[i].name = trackFiles[i].file
			end
		end
	else
		dirExists = false
	end
end

local function init()
    local dataString = readFile(v.vehicleDirectory .. 'info.json')
    isVehicle = false
    if dataString then
        dataString = string.lower(dataString)
        local data = jsonDecode(dataString)
        if data.type then
            if data.type == 'car' or data.type == 'truck' or data.type == 'automation' or data.type == 'traffic' then
                isVehicle = true
            end
        end
        vehicleElectrics = require("electrics")
        engine = powertrain.getDevice('mainEngine')
        shortedInWater = false
        restartFromBeginning = false
        electrics.values.stereoSystemOn = 0
        mp3Duration = require('lua/vehicle/extensions/auto/metadata/duration/MP3Duration')
        wavDuration = require('lua/vehicle/extensions/auto/metadata/duration/WAVDuration')
        id3V1 = require('lua/vehicle/extensions/auto/metadata/ID3V1')
        id3V2 = require('lua/vehicle/extensions/auto/metadata/ID3V2')
        ape = require('lua/vehicle/extensions/auto/metadata/APE')
        lyrics = require('lua/vehicle/extensions/auto/metadata/Lyrics3')
        ape.initVariables()
        id3V2.initVariables()
        mp3Duration.initVariables()
        wavDuration.initVariables()
        fileHelper = require('lua/vehicle/extensions/auto/utilities/FileHelper')
        wasOn = false
        fileIsOpen = false
        wasPlaying = false
        paused = true
        shuffle = false
        repeatMode = 2
        displayedDetails = false
        playDuration = 0
        endOfPlayList = false
        math.randomseed(os.time())
        trackIndex = 1
        halfCacheSize = math.floor(cacheSize/2)
        volume = DESKTOP_VOLUME
        if isVehicle then
            loadCacheAndGetFiles(tracksFolder)
            if v.data.refNodes and v.data.refNodes[0] then
                speaker = v.data.refNodes[0].ref or v.data.refNodes[0].leftCorner
            end
        else
            isVehicle = false
        end
    end
end

local function killStereoSystem()
	electrics.values.stereoSystemOn = 0
	wasPlaying = false
    paused = true
    wasOn = false
	for _, track in ipairs(cachedTracks) do
        obj:cutSFX(track.sfx)
		obj:deleteSFXSource(track.sfx, true)
		track.sfx = nil
	end
end

local function toggleStereoSystem()
	if #trackFiles > 0 and vehicleElectrics.values.ignition == true and not shortedInWater and isVehicle then
		if electrics.values.stereoSystemOn == 1 then
			killStereoSystem()
            showUiNotification("Stereo: system is now off", "system_off", MSG_DURATION * 1000)
            updateUiPlaybackState(false, true, endOfPlayList, false) -- System off, paused, not active
		else
			electrics.values.stereoSystemOn = 1
            wasOn = true
			delayedPlay = true
            -- displayDetails() will be called if needed by subsequent state updates.
			for _, trackData in ipairs(cachedTracks) do
                if trackData.name then
				    trackData.sfx = obj:createSFXSource(trackData.name, profile, trackData.name, speaker)
                end
			end
            showUiNotification("Stereo: system is now on", "system_on", MSG_DURATION * 1000)
            -- Full state update will ensure UI consistency
            if M.requestFullStateUpdate then M.requestFullStateUpdate() end
		end
	else
        displayState(true)
	end
end

local function updateCache(incr)
	if incr == 1 then
		cachePos = luaMod(cachePos + halfCacheSize, #trackFiles)
		obj:deleteSFXSource(cachedTracks[1].sfx, true)
		for i = 1, cacheSize - halfCacheSize do
			cachedTracks[i] = deepcopy(cachedTracks[i + halfCacheSize])
		end
		if shuffleIndex == 2 and shuffle then
			obj:deleteSFXSource(cachedTracks[cacheTrackIndex()].sfx, true)
			cachedTracks[cacheTrackIndex()].sfx = obj:createSFXSource(trackFiles[trackIndex].file, profile, trackFiles[trackIndex].file, speaker)
			cachedTracks[cacheTrackIndex()].name = trackFiles[trackIndex].file
			delayedPlay = true
		end
		local index = luaMod(trackIndex + 1, #trackFiles)
		cachedTracks[3].sfx = obj:createSFXSource(trackFiles[index].file, profile, trackFiles[index].file, speaker)
		cachedTracks[3].name = trackFiles[index].file
	elseif incr == -1 then
		cachePos = luaMod(cachePos - halfCacheSize, #trackFiles)
		obj:deleteSFXSource(cachedTracks[3].sfx, true)
		for i = cacheSize, cacheSize - halfCacheSize, -1 do
			cachedTracks[i] = deepcopy(cachedTracks[i - halfCacheSize])
		end
		local index = luaMod(trackIndex - 1, #trackFiles)
		cachedTracks[1].sfx = obj:createSFXSource(trackFiles[index].file, profile, trackFiles[index].file, speaker)
		cachedTracks[1].name = trackFiles[index].file
	end
end

local function nextTrack()
	if electrics.values.stereoSystemOn == 1 and isVehicle then
		obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx)
		local newCachePos = trackIndex
		trackIndex = luaMod(trackIndex + 1, #trackFiles)
		local swap = true
		if trackIndex == #trackFiles and shuffle then
			loopedOnce = true
			swap = false
		end
		if trackIndex == shuffleIndex and shuffle then
			if shuffleIndex ~= 1 then
				shuffleIndex = luaMod(shuffleIndex + 1, #trackFiles)
			end
			if swap then
				local maxIndex = #trackFiles
				if shuffleIndex < newCachePos then
					maxIndex = cachePos
				end
				local tmpShuffleIndex = shuffleIndex
				local moreRandom = math.random(1, 2)
				if moreRandom == 2 then
					tmpShuffleIndex = math.random(shuffleIndex, maxIndex)
				end
				local rIndex = math.random(tmpShuffleIndex, maxIndex)
				swapElements(trackFiles, rIndex, shuffleIndex)
			end
			if shuffleIndex == 1 and swap then
				shuffleIndex = luaMod(shuffleIndex + 1, #trackFiles)
			end
		end
		if shuffle and not caching and #cachedTracks == cacheSize and trackIndex == 1 then
			for i = 1, 2 do
				local rIndex = math.random(1, 2)
				if rIndex == 1 then
					swapElements(cachedTracks, i, i + 1)
					swapElements(trackFiles, i, i + 1)
				end
			end
		end
		if cacheTrackIndex() == cacheSize and caching then
			updateCache(1)
		end
		if not delayedPlay then
			systemPlayTrack(cachedTracks[cacheTrackIndex()])
		end
	else
        displayState(false)
    end
end

local function previousTrack(playOnRepeat)
	if electrics.values.stereoSystemOn == 1 and isVehicle then
        if (playDuration >= 3) or (shuffle and not loopedOnce and trackIndex == 1) or playOnRepeat then
            if not paused or playOnRepeat then
                systemPlayTrack(cachedTracks[cacheTrackIndex()])
            else
                playDuration = 0
                restartFromBeginning = true
                endOfPlayList = false
                -- displayTrack('resetting') -- Notify UI instead
                local currentTr = trackFiles[trackIndex]
                if currentTr then updateUiTrackInfo(currentTr.title, currentTr.artist, currentTr.album, trackIndex, #trackFiles) end
                updateUiPlaybackState(false, true, false, true) -- Not playing, but paused, not at end, system active
                showUiNotification("Track " ..trackIndex.. " reset to beginning.", "info", MSG_DURATION*1000)
            end
        else
            if cachedTracks[cacheTrackIndex()] and cachedTracks[cacheTrackIndex()].sfx then
                obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx)
            end
            trackIndex = luaMod(trackIndex - 1, #trackFiles)
            if cacheTrackIndex() == 1 and caching then 
                updateCache(-1)
            end
            systemPlayTrack(cachedTracks[cacheTrackIndex()])
        end
	else
        displayState(false)
    end
end

local function playPause(userPlayPaused)
	if electrics.values.stereoSystemOn == 1 and vehicleElectrics.values.ignition == true and not shortedInWater and isVehicle then
        local currentCachedTrack = cachedTracks[cacheTrackIndex()]
        if not currentCachedTrack or not currentCachedTrack.sfx then
            showUiNotification("Cannot play/pause: Track data or SFX not loaded.", "error", 3000)
            updateUiPlaybackState(false, true, true, true) -- Error state: not playing, paused, at end, system assumed active
            return
        end

        if not paused then -- Was playing, now pause it
            if userPlayPaused then 
                showUiNotification("Playback paused", "info", MSG_DURATION*1000)
            end
            wasPlaying = false 
            paused = true
			obj:setVolume(currentCachedTrack.sfx, MIN_VOLUME_VALUE) 
			obj:setPitch(currentCachedTrack.sfx, 0) 
            updateUiPlaybackState(false, true, endOfPlayList, true)
		else -- Was paused, now play it
            if restartFromBeginning then
                systemPlayTrack(currentCachedTrack) 
            else
                obj:setPitch(currentCachedTrack.sfx, 1) 
                paused = false
                showUiNotification("Playback resumed", "info", MSG_DURATION*1000)
            end
			delayedVolUp = true 
            wasPlaying = true 
            updateUiPlaybackState(true, false, endOfPlayList, true)
		end
    else
        -- Notify UI that action can't be taken due to system/ignition state
        if vehicleElectrics.values.ignition ~= true then
            showUiNotification("Cannot play/pause: Ignition is off.", "ignition_off", 2000)
        elseif electrics.values.stereoSystemOn ~= 1 then
             showUiNotification("Cannot play/pause: System is off.", "system_off", 2000)
        elseif shortedInWater then
             showUiNotification("Cannot play/pause: System shorted.", "error", 2000)
        else
            displayState(false) -- Generic "system off" or other issue
        end
    end
end

local function onReset()
    if wasOn then
        for i, cached in ipairs(cachedTracks) do
            if cached.sfx and (i ~= cacheTrackIndex() or endOfPlayList or restartFromBeginning) then
                obj:cutSFX(cached.sfx)
            end
        end
	end
    if shortedInWater then
        shortedInWater = false
        displayedRecoveredMessage = true
        showUiNotification("Stereo: system recovered", "info", MSG_DURATION * 1000)
        displayDetails() -- Update UI with current state
    end
    -- Request full UI update on reset to ensure sync
    if M.requestFullStateUpdate then M.requestFullStateUpdate() end
end

local function scanForTracks()
    if isVehicle then
        if dirExists then
            showUiNotification("Stereo: scan - there were " .. tostring(#trackFiles) .. " track(s) detected. Scanning for new tracks...", "info", MSG_DURATION * 1000)
        end
        wasPlaying = false
        displayedDetails = false
        if shuffle then
            shuffle = false
            updateUiShuffleMode(false)
            showUiNotification("Stereo: shuffle mode reset to off", "info", MSG_DURATION * 1000)
        end
        if wasOn then -- If system was on, turn it off, then rescan might turn it back on if tracks are found
            showUiNotification("Stereo: system reset for scan.", "info", MSG_DURATION * 1000)
            killStereoSystem() -- This also updates UI to off state
        end
        trackIndex = 1
        local oldNum = #trackFiles
        loadCacheAndGetFiles(tracksFolder) -- This function needs to be checked if it also uses gui.message

        if dirExists then
            if #trackFiles > oldNum then
                local dif = #trackFiles - oldNum
                showUiNotification("Stereo: scan - found " .. dif .. " new track(s). Total: " .. #trackFiles, "success", MSG_DURATION * 1000)
            elseif #trackFiles < oldNum then
                local dif = oldNum - #trackFiles
                showUiNotification("Stereo: scan - " .. dif .. " track(s) removed. Total: " .. #trackFiles, "info", MSG_DURATION * 1000)
            else
                showUiNotification("Stereo: scan - no new tracks found. Total: " .. #trackFiles, "info", MSG_DURATION * 1000)
            end
        else
             showUiNotification("Stereo: scan - the music folder doesn't exist", "error", MSG_DURATION * 1000)
        end
        -- After scan, update track info and playback state (likely stopped)
        if #trackFiles > 0 then
            local currentTr = trackFiles[trackIndex]
            if currentTr then updateUiTrackInfo(currentTr.title, currentTr.artist, currentTr.album, trackIndex, #trackFiles) end
        else
            updateUiTrackInfo("No Tracks", "N/A", "N/A", 0, 0)
        end
        updateUiPlaybackState(false, true, #trackFiles == 0, electrics.values.stereoSystemOn == 1 and vehicleElectrics.values.ignition == true and not shortedInWater) -- Not playing, paused, atEnd if no tracks
        updateUiVolume(volume, MAX_VOLUME) -- Send current volume
    end
end

local function operator(first, second)
	if first.index < second.index then
		return true
	else
		return false
	end
end

local function toggleShuffleMode()
	if #trackFiles > 0 and vehicleElectrics.values.ignition == true and not shortedInWater and isVehicle then
		shuffle = not shuffle
        updateUiShuffleMode(shuffle) -- Update UI
		if shuffle then
			loopedOnce = false
            showUiNotification("Stereo: shuffle mode is on", "info", MSG_DURATION * 1000)
			local startInd = 1
			if electrics.values.stereoSystemOn == 1 then
                local currentCachedIdx = cacheTrackIndex()
				if currentCachedIdx ~= 1 and cachedTracks[1] and cachedTracks[currentCachedIdx] then -- ensure indices are valid
					if cachedTracks[1].sfx then obj:deleteSFXSource(cachedTracks[1].sfx, true) end
					cachedTracks[1] = deepcopy(cachedTracks[currentCachedIdx])
					cachedTracks[currentCachedIdx].sfx = nil -- Avoid deleting it twice if it was moved
					swapElements(trackFiles, 1, trackIndex)
				end
				startInd = 2
			end
			shuffleIndex = startInd
			for i = startInd, #cachedTracks do
                if cachedTracks[i] and (i ~= cacheTrackIndex() or electrics.values.stereoSystemOn == 0) and cachedTracks[i].sfx ~= nil then
					obj:deleteSFXSource(cachedTracks[i].sfx, true)
                    cachedTracks[i].sfx = nil
				end
			end
			for i = startInd, #cachedTracks do
                if not trackFiles or #trackFiles == 0 then break end -- Safety break
				local tmpShuffleIndex = shuffleIndex
                if tmpShuffleIndex > #trackFiles then tmpShuffleIndex = #trackFiles end -- Bound check
                if tmpShuffleIndex < 1 then tmpShuffleIndex = 1 end

				local moreRandom = math.random(1, 2)
				if moreRandom == 2 then
					tmpShuffleIndex = math.random(shuffleIndex, #trackFiles)
				end
				local rIndex = math.random(tmpShuffleIndex, #trackFiles)
                if not trackFiles[rIndex] then goto continue_loop end -- skip if random index is bad

				if electrics.values.stereoSystemOn == 1 then
                    if cachedTracks[i] then
					    cachedTracks[i].sfx = obj:createSFXSource(trackFiles[rIndex].file, profile, trackFiles[rIndex].file, speaker)
                    end
				elseif cachedTracks[i] then
					cachedTracks[i].sfx = nil
				end
                if cachedTracks[i] then cachedTracks[i].name = trackFiles[rIndex].file end
				swapElements(trackFiles, rIndex, shuffleIndex)
				shuffleIndex = shuffleIndex + 1
                if shuffleIndex > #trackFiles then shuffleIndex = #trackFiles end -- Bound check
                ::continue_loop::
			end
			if caching then
				shuffleIndex = 3 -- This might need adjustment based on cacheSize
			end
			trackIndex = 1
			cachePos = 1
		else
            showUiNotification("Stereo: shuffle mode is off", "info", MSG_DURATION * 1000)
            if cachedTracks and cachedTracks[cacheTrackIndex()] then -- Ensure valid before proceeding
                for i, trackData in ipairs(cachedTracks) do  -- Renamed 'track' to 'trackData'
                    if trackData and (i ~= cacheTrackIndex() or electrics.values.stereoSystemOn == 0) and trackData.sfx ~= nil then
                        obj:deleteSFXSource(trackData.sfx, true)
                        trackData.sfx = nil
                    end
                end
                local copy = deepcopy(cachedTracks[cacheTrackIndex()])
                if trackFiles[trackIndex] then -- Check if trackFiles[trackIndex] is valid
                    trackIndex = trackFiles[trackIndex].index
                else -- Fallback if trackFiles[trackIndex] is nil
                    trackIndex = 1 -- Or some other default
                end
                cachePos = luaMod(trackIndex - halfCacheSize, #trackFiles)
                if cachedTracks[cacheTrackIndex()] then cachedTracks[cacheTrackIndex()] = deepcopy(copy) end
                table.sort(trackFiles, operator)
                for i = 1, #cachedTracks do
                    local current_idx = i -- Renamed 'index' to 'current_idx'
                    if caching then
                        current_idx = luaMod(cachePos + i - 1, #trackFiles)
                    end
                    if i ~= cacheTrackIndex() then
                        if electrics.values.stereoSystemOn == 1 and trackFiles[current_idx] then
                            if cachedTracks[i] then cachedTracks[i].sfx = obj:createSFXSource(trackFiles[current_idx].file, profile, trackFiles[current_idx].file, speaker) end
                        elseif cachedTracks[i] then
                            cachedTracks[i].sfx = nil
                        end
                        if cachedTracks[i] and trackFiles[current_idx] then cachedTracks[i].name = trackFiles[current_idx].file end
                    end
                end
            end
		end
        getMetaData(true) -- This calls displayTrack which updates UI
	else
        displayState(true)
	end
end

local function detectedTagsAtBack()
    local oldEnd = trackFiles[trackIndex].endOfAudio
    id3V1.detectID3V1Tag(file, trackFiles[trackIndex])
    id3V2.detectID3V2TagAtBack(file, trackFiles[trackIndex])
    ape.detectAPETagAtBack(file, trackFiles[trackIndex])
    lyrics.detectLyricsTag(file, trackFiles[trackIndex])
    if trackFiles[trackIndex].checkForLyrics then
        return false
    end
    return oldEnd ~= trackFiles[trackIndex].endOfAudio
end

local function detectedTagsAtFront()
    local oldPos = file:seek()
    id3V2.detectID3V2Tag(file, trackFiles[trackIndex], false)
    ape.detectAPETag(file, false)
    trackFiles[trackIndex].fileSeek = file:seek()
    return oldPos ~= file:seek()
end

local function checkForEndOfTrack(dt)
    if not paused then
        playDuration = playDuration + dt
        if playDuration >= trackFiles[trackIndex].duration and not trackFiles[trackIndex].calculating then
            paused = true
            wasPlaying = false
            if repeatMode == 1 then -- Off (play through then stop)
                if trackIndex ~= #trackFiles then
                    nextTrack()
                else
                    endOfPlayList = true
                    if cachedTracks[cacheTrackIndex()] and cachedTracks[cacheTrackIndex()].sfx then obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx) end
                    showUiNotification("Stereo: reached the end of the playlist", "info", MSG_DURATION * 1000)
                    updateUiPlaybackState(false, true, true, true) -- Not playing, paused, at end, system active
                end
            elseif repeatMode == 2 then -- Playlist
                nextTrack()
            elseif repeatMode == 3 then
                previousTrack(true)
            end
        end
    end
end

local function getMetaDataFromFile()
    if #trackFiles > 0 and trackFiles[trackIndex].gettingMetaData and fileIsOpen then
        if trackFiles[trackIndex].calculating and (trackFiles[trackIndex].detectedTags or trackFiles[trackIndex].fileType == '.wav') then
            if currentTr.version1LayerI and not currentTr.version1LayerIDisplayed then
                currentTr.version1LayerIDisplayed = true
                showUiNotification('Warning - ' .. string.sub(currentTr.file, 8) .. ' contains MPEG-1 Layer I frame.', 'warning', MSG_DURATION*1000)
            end
            if currentTr.fileType == ".mp3" then
                mp3Duration.calculateDuration(file, currentTr)
            elseif currentTr.fileType == ".wav" then
                wavDuration.calculateDuration(file, currentTr)
            end
            if not currentTr.calculating then
                currentTr.gettingMetaData = false
                if currentTr.duration ~= currentTr.duration then -- NaN check
                    showUiNotification('Error - could not obtain duration of ' .. string.sub(currentTr.file, 8), 'error', MSG_DURATION*1000)
                end
                file:close()
                fileIsOpen = false
                if currentTr.fileType == '.wav' then -- WAV might not have tags parsed other way
                    currentTr.detectedTags = true -- Assume true for WAV after duration calc
                    buildMetaDataString() -- Update metaString
                    if electrics.values.stereoSystemOn == 1 then
                        displayTrack('playing') -- Update UI with new info
                    end
                end
            end
        elseif currentTr.fileType == '.mp3' and not currentTr.detectedTags then
            while detectedTagsAtBack() do end
            while detectedTagsAtFront() do end
            currentTr.detectedTags = true
            buildMetaDataString() -- Update metaString
            if electrics.values.stereoSystemOn == 1 then
                displayTrack('playing') -- Update UI
            end
        end
    end
end

local function updateGFX(dt)
    if not initialized then
        init()
        initialized = true
    end
    if isVehicle then
        if (vehicleElectrics.values.ignition ~= true or shortedInWater) and wasOn then
            displayedDetails = false
        end
        if (vehicleElectrics.values.ignition ~= true or shortedInWater) and electrics.values.stereoSystemOn == 1 then
            if not paused then
                playPause(false)
            end
            electrics.values.stereoSystemOn = 0
            if not shortedInWater then
                wasPlaying = true 
            end
            if not shortedInWater then
                showUiNotification("Stereo: ignition turned off", "ignition_off", MSG_DURATION * 1000)
            end
            updateUiPlaybackState(false, true, endOfPlayList, false) -- Update UI, system not active
        elseif vehicleElectrics.values.ignition == true and not shortedInWater and wasOn and electrics.values.stereoSystemOn == 0 then
            electrics.values.stereoSystemOn = 1 
            if wasPlaying then 
                playPause(false) 
            end
            if not displayedRecoveredMessage then
                showUiNotification("Stereo: ignition turned on", "ignition_on", MSG_DURATION * 1000)
            end
            -- displayDetails() -- This updates all UI elements; full state update might be better
            if M.requestFullStateUpdate then M.requestFullStateUpdate() end
        end
        if displayedRecoveredMessage then
            displayedRecoveredMessage = false
        end
        checkForEndOfTrack(dt)
        getMetaDataFromFile()
        if delayedPlay then
            delayedPlayTime = delayedPlayTime + dt
            if delayedPlayTime > 1/15 then
                delayedPlay = false
                delayedPlayTime = 0
                systemPlayTrack(cachedTracks[cacheTrackIndex()])
            end
        end
        if delayedVolUp then
            delayedVolUpTime = delayedVolUpTime + dt
            if delayedVolUpTime > 1/4 then
                delayedVolUp = false
                delayedVolUpTime = 0
                obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, volume)
            end
        end
        if os.time() - nextDownTime > 1 and nextUpTime == 0 and nextDownTime ~= 0 then
            nextDownTime = 0
            wasHolding = true
            toggleStereoSystem()
        elseif nextUpTime ~= 0 and nextDownTime ~= 0 then
            nextDownTime = 0
            nextUpTime = 0
            nextTrack()
        end
        if os.time() - prevDownTime > 1 and prevUpTime == 0 and prevDownTime ~= 0 then
            prevDownTime = 0
            wasHolding2 = true
            toggleShuffleMode()
        elseif prevUpTime ~= 0 and prevDownTime ~= 0 then
            prevDownTime = 0
            prevUpTime = 0
            previousTrack(false)
        end
        if volumeButtonDown then
            if volumeDownTime == os.time() then
                decreaseVolume()
            end
            volumeDownTime = volumeDownTime + dt
            if volumeDownTime - prevVolumeDownTime > .15 then
                prevVolumeDownTime = prevVolumeDownTime + .15
                decreaseVolume()
            end
        end
        if volumeButtonUp then
            if volumeUpTime == os.time() then
                increaseVolume()
            end
            volumeUpTime = volumeUpTime + dt
            if volumeUpTime - prevVolumeUpTime > .15 then
                prevVolumeUpTime = prevVolumeUpTime + .15
                increaseVolume()
            end
        end
        if not dirExists then
            if FS:directoryExists(tracksFolder) then
                dirExists = true
            end
        end
        if engine then
            local isFlooding = engine.canFlood
            for _, n in ipairs(engine.waterDamageNodes) do
                isFlooding = isFlooding and obj:inWater(n)
                if not isFlooding then
                    break
                end
            end
            if isFlooding and not shortedInWater then
                shortAtTime = shortAtTime + dt
                if shortAtTime > 4 then
                    shortAtTime = 0
                    shortedInWater = true
                    showUiNotification("Stereo: system shorted in water!", "error", MSG_DURATION * 1000) 
                    updateUiPlaybackState(false, true, true, false) -- Not playing, paused, at end, system not active
                end
            else
                shortAtTime = 0
            end
        end
    end
end

-- New function to send full state to UI
function M.requestFullStateUpdate()
    if not initialized then return end 

    local systemIsActive = isVehicle and electrics.values.stereoSystemOn == 1 and vehicleElectrics.values.ignition == true and not shortedInWater
    local ignitionIsOn = isVehicle and vehicleElectrics.values.ignition == true

    if not ignitionIsOn then
        showUiNotification("Stereo: ignition is off", "ignition_off", 100) -- Short notification as state is being set
    elseif not (isVehicle and electrics.values.stereoSystemOn == 1 and not shortedInWater) then
         showUiNotification("Stereo: system is off", "system_off", 100)
    end
    -- If shorted, that implies system is not active for UI purposes
    if shortedInWater then
        systemIsActive = false
        showUiNotification("Stereo: system shorted", "error", 100)
    end


    if not systemIsActive then
        local offReason = "System Off"
        if not ignitionIsOn then offReason = "Ignition Off"
        elseif shortedInWater then offReason = "System Shorted"
        elseif not (isVehicle and electrics.values.stereoSystemOn == 1) then offReason = "System Off" -- More specific
        end
        updateUiTrackInfo(offReason, "", "", 0, #trackFiles)
    else
        local currentTr = trackFiles[trackIndex]
        if currentTr then
            buildMetaDataString() 
            updateUiTrackInfo(currentTr.title, currentTr.artist, currentTr.album, trackIndex, #trackFiles)
        else
            updateUiTrackInfo("No Track Loaded", "N/A", "N/A", 0, #trackFiles)
        end
    end
    
    updateUiPlaybackState(not paused and systemIsActive, paused, endOfPlayList, systemIsActive)
    updateUiVolume(volume, MAX_VOLUME)
    updateUiShuffleMode(shuffle)
    updateUiRepeatMode(repeatMode)
end


M.updateGFX = updateGFX
M.onReset = onReset
M.toggleStereoSystem = toggleStereoSystem
M.setNextDownTime = setNextDownTime -- Likely for hardware controls, keep for now
M.setNextUpTime = setNextUpTime     -- Likely for hardware controls, keep for now
M.setPrevDownTime = setPrevDownTime   -- Likely for hardware controls, keep for now
M.setPrevUpTime = setPrevUpTime     -- Likely for hardware controls, keep for now
M.scanForTracks = scanForTracks
M.toggleShuffleMode = toggleShuffleMode
M.playPause = playPause
M.decreaseVolumeButtonUp = decreaseVolumeButtonUp -- Keep for hardware controls
M.decreaseVolumeButtonDown = decreaseVolumeButtonDown -- Keep for hardware controls
M.increaseVolumeButtonUp = increaseVolumeButtonUp -- Keep for hardware controls
M.increaseVolumeButtonDown = increaseVolumeButtonDown -- Keep for hardware controls
M.toggleRepeatMode = toggleRepeatMode
-- Expose nextTrack and previousTrack (were not explicitly in M before)
M.nextTrack = nextTrack
M.previousTrack = previousTrack
-- Expose increaseVolume and decreaseVolume for potential mapping if UI uses buttons instead of slider for steps
M.increaseVolume = increaseVolume
M.decreaseVolume = decreaseVolume
-- M.setVolume is already defined above with the M. prefix

return M