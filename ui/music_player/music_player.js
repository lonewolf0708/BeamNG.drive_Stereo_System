angular.module('beamngMusicPlayer', [])
    .controller('MusicPlayerController', ['$scope', function($scope) {
        // --- Mock / Initial Data ---
        $scope.currentTrack = {
            title: 'Song Title', // Placeholder
            artist: 'Artist Name', // Placeholder
            album: 'Album Name'    // Placeholder
        };
        $scope.trackNumber = 0; // Placeholder
        $scope.totalTracks = 0; // Placeholder

        $scope.isPlaying = false;
        $scope.isPaused = false; // Added for more granular state
        $scope.isAtEnd = false;  // Added for end of playlist
        $scope.isShuffleOn = false;
        $scope.repeatMode = 'none'; // 'none', 'one', 'all'
        $scope.volume = 0.5; // Default volume
        $scope.maxVolume = 1; // Default max volume

        // New state variables for UI control
        $scope.systemActive = true; // Assume active until Lua tells us otherwise
        $scope.ignitionOn = true;   // Assume on until Lua tells us otherwise

        // --- UI Action Functions (JS to Lua) ---
        $scope.playPause = function() {
            console.log("UI: playPause called");
            if (typeof bngApi !== 'undefined') {
                bngApi.engineLua('extensions.auto.StereoSystem.playPause(true)'); // Argument 'true' for userPlayPaused
            } else {
                // Mock behavior for local testing
                $scope.isPlaying = !$scope.isPlaying;
                $scope.isPaused = !$scope.isPlaying;
                 console.warn("bngApi not defined. playPause mock executed.");
            }
        };

        $scope.prevTrack = function() {
            console.log("UI: prevTrack called");
            if (typeof bngApi !== 'undefined') {
                bngApi.engineLua('extensions.auto.StereoSystem.previousTrack(false)'); // Argument 'false' for playOnRepeat
            } else {
                $scope.currentTrack = { title: 'Mock Prev Song', artist: 'Mock Artist', album: 'Mock Album P' };
                console.warn("bngApi not defined. prevTrack mock executed.");
            }
        };

        $scope.nextTrack = function() {
            console.log("UI: nextTrack called");
            if (typeof bngApi !== 'undefined') {
                bngApi.engineLua('extensions.auto.StereoSystem.nextTrack()');
            } else {
                $scope.currentTrack = { title: 'Mock Next Song', artist: 'Mock Artist', album: 'Mock Album N' };
                console.warn("bngApi not defined. nextTrack mock executed.");
            }
        };

        $scope.toggleShuffle = function() {
            console.log("UI: toggleShuffle called");
            if (typeof bngApi !== 'undefined') {
                bngApi.engineLua('extensions.auto.StereoSystem.toggleShuffleMode()');
            } else {
                $scope.isShuffleOn = !$scope.isShuffleOn;
                console.warn("bngApi not defined. toggleShuffle mock executed.");
            }
        };

        $scope.toggleRepeat = function() {
            console.log("UI: toggleRepeat called");
            if (typeof bngApi !== 'undefined') {
                bngApi.engineLua('extensions.auto.StereoSystem.toggleRepeatMode()');
            } else {
                 if ($scope.repeatMode === 'none') $scope.repeatMode = 'song';
                 else if ($scope.repeatMode === 'song') $scope.repeatMode = 'playlist';
                 else $scope.repeatMode = 'none';
                console.warn("bngApi not defined. toggleRepeat mock executed.");
            }
        };

        $scope.setVolume = function() { // Called by ng-change on volume slider
            console.log("UI: setVolume called. New volume:", $scope.volume);
            if (typeof bngApi !== 'undefined') {
                bngApi.engineLua('extensions.auto.StereoSystem.setVolume(' + $scope.volume + ')');
            } else {
                console.warn("bngApi not defined. setVolume mock executed.");
            }
        };

        // --- Functions to be called by Lua (Lua to JS) ---
        // This is a placeholder for how Lua might update the Angular scope.
        // For example, when a new song starts playing.
        // These $on events might be deprecated if direct window functions are used,
        // but can be kept for internal Angular-based event handling if needed.
        $scope.$on('trackChanged', function(event, newTrack) {
            $scope.currentTrack = newTrack;
            // isPlaying state should be managed by setPlaybackStateDisplay
            $scope.$apply(); // Notify Angular of changes if called from outside Angular digest cycle
        });

        $scope.$on('playbackStateChanged', function(event, isPlaying) {
            $scope.isPlaying = isPlaying;
            $scope.$apply();
        });

        // --- Functions callable from Lua via executeJS ---
        window.updateTrackDisplay = function(title, artist, album, trackNumber, totalTracks) {
            $scope.$apply(function() {
                // Only update if the system is considered active, otherwise keep cleared info
                if ($scope.systemActive) {
                    $scope.currentTrack.title = title;
                    $scope.currentTrack.artist = artist;
                    $scope.currentTrack.album = album;
                    $scope.trackNumber = trackNumber;
                    $scope.totalTracks = totalTracks;
                } else {
                    // This case should ideally be handled by setPlaybackStateDisplay clearing track info
                }
            });
        };

        // Modified to include systemActive state
        window.setPlaybackStateDisplay = function(isPlaying, isPaused, isAtEnd, systemIsActive) {
            $scope.$apply(function() {
                $scope.systemActive = systemIsActive; // Update system active state

                if ($scope.systemActive) {
                    $scope.isPlaying = isPlaying;
                    $scope.isPaused = isPaused;
                    $scope.isAtEnd = isAtEnd;
                } else {
                    // If system is not active, force UI to a default "off" state
                    $scope.currentTrack.title = 'System Off'; // Clear track info
                    $scope.currentTrack.artist = '';
                    $scope.currentTrack.album = '';
                    $scope.trackNumber = 0;
                    $scope.totalTracks = 0;
                    $scope.isPlaying = false;
                    $scope.isPaused = true; // Typically paused when system is off
                    $scope.isAtEnd = true;  // Or at end
                }
            });
        };

        window.setVolumeDisplay = function(volumeLevel, maxVolume) {
            $scope.$apply(function() {
                $scope.volume = volumeLevel;
                $scope.maxVolume = maxVolume;
            });
        };

        window.setShuffleDisplay = function(isShuffleOn) {
            $scope.$apply(function() {
                $scope.isShuffleOn = isShuffleOn;
            });
        };

        window.setRepeatDisplay = function(repeatModeString) {
            $scope.$apply(function() {
                $scope.repeatMode = repeatModeString;
            });
        };

        window.showNotificationInUi = function(message, type, duration) {
            console.log('Notification:', { message: message, type: type, duration: duration });

            $scope.$apply(function() {
                // Update ignitionOn and systemActive based on notification types
                if (type === 'ignition_off') {
                    $scope.ignitionOn = false;
                    // When ignition goes off, system effectively becomes inactive for UI purposes
                    $scope.systemActive = false;
                    $scope.currentTrack.title = 'Ignition Off'; // Clear track info
                    $scope.currentTrack.artist = '';
                    $scope.currentTrack.album = '';
                    $scope.trackNumber = 0;
                    $scope.totalTracks = 0;
                    $scope.isPlaying = false;
                    $scope.isPaused = true;
                } else if (type === 'ignition_on') {
                    $scope.ignitionOn = true;
                    // System might still be off, Lua will send its actual state via requestFullStateUpdate or setPlaybackStateDisplay
                    // For now, assume system might become active, but rely on specific state updates
                } else if (type === 'system_off') {
                    $scope.systemActive = false;
                    $scope.currentTrack.title = 'System Off'; // Clear track info
                    $scope.currentTrack.artist = '';
                    $scope.currentTrack.album = '';
                    $scope.trackNumber = 0;
                    $scope.totalTracks = 0;
                    $scope.isPlaying = false;
                    $scope.isPaused = true;
                } else if (type === 'system_on') {
                    $scope.systemActive = true;
                    // Ignition must also be on for this to be fully true, but this reflects stereo power state
                }

                // Simple visual notification (can be expanded with HTML elements)
                $scope.notification = { message: message, type: type, visible: true };
                setTimeout(function() {
                    $scope.$apply(function() {
                        $scope.notification.visible = false;
                    });
                }, duration || 3000);
            });
        };

        // Initial state request from Lua when controller loads
        if (typeof bngApi === 'undefined') { // For local testing without BeamNG.drive environment
            console.warn("bngApi is not defined. Running in local test mode. Lua calls will not work. Mock data used.");
            // Apply some mock data if running in browser for testing
            $scope.systemActive = true;
            $scope.ignitionOn = true;
            window.updateTrackDisplay("Test Track", "Test Artist", "Test Album", 1, 5);
            window.setPlaybackStateDisplay(false, true, false, $scope.systemActive); // playing, paused, atEnd, systemActive
            window.setVolumeDisplay(0.5, 1.0);
            window.setShuffleDisplay(false);
            window.setRepeatDisplay("off");
        } else {
            console.log("Music player UI initialized. Requesting full state from Lua...");
            bngApi.engineLua('extensions.auto.StereoSystem.requestFullStateUpdate()');
        }
    }]);
