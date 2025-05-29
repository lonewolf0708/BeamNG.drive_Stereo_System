// Changed module to 'beamng.apps'
angular.module('beamng.apps')
    .directive('musicPlayerUi', ['$rootScope', function($rootScope) { // Inject $rootScope for broadcasting from window functions
        return {
            restrict: 'E', // Element directive
            templateUrl: '/ui/modules/apps/music_player/music_player.html', // Adjusted path
            replace: true,
            scope: {}, // Isolated scope
            controller: function($scope, $element, $attrs) {
                // --- Mock / Initial Data (now part of directive's scope) ---
                $scope.currentTrack = {
                    title: 'Song Title', // Placeholder
                    artist: 'Artist Name', // Placeholder
                    album: 'Album Name'    // Placeholder
                };
                $scope.trackNumber = 0; // Placeholder
                $scope.totalTracks = 0; // Placeholder

                $scope.isPlaying = false;
                $scope.isPaused = false;
                $scope.isAtEnd = false;
                $scope.isShuffleOn = false;
                $scope.repeatMode = 'none'; // 'none', 'one', 'all'
                $scope.volume = 0.5;
                $scope.maxVolume = 1;

                $scope.systemActive = true;
                $scope.ignitionOn = true;
                $scope.notification = { message: '', type: '', visible: false };


                // --- UI Action Functions (JS to Lua) ---
                $scope.playPause = function() {
                    console.log("UI: playPause called");
                    if (typeof bngApi !== 'undefined') {
                        bngApi.engineLua('extensions.auto.StereoSystem.playPause(true)');
                    } else {
                        $scope.isPlaying = !$scope.isPlaying;
                        $scope.isPaused = !$scope.isPlaying;
                        console.warn("bngApi not defined. playPause mock executed.");
                    }
                };

                $scope.prevTrack = function() {
                    console.log("UI: prevTrack called");
                    if (typeof bngApi !== 'undefined') {
                        bngApi.engineLua('extensions.auto.StereoSystem.previousTrack(false)');
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

                $scope.setVolume = function() {
                    console.log("UI: setVolume called. New volume:", $scope.volume);
                    if (typeof bngApi !== 'undefined') {
                        bngApi.engineLua('extensions.auto.StereoSystem.setVolume(' + $scope.volume + ')');
                    } else {
                        console.warn("bngApi not defined. setVolume mock executed.");
                    }
                };

                // --- Event Listeners for data from Lua (via $rootScope.$broadcast) ---
                $scope.$on('musicPlayer.updateTrackDisplay', function(event, data) {
                    if ($scope.systemActive) { // Check systemActive before updating
                        $scope.currentTrack.title = data.title;
                        $scope.currentTrack.artist = data.artist;
                        $scope.currentTrack.album = data.album;
                        $scope.trackNumber = data.trackNumber;
                        $scope.totalTracks = data.totalTracks;
                    }
                    // $scope.$apply(); // Not needed if $broadcast is from Angular context
                });

                $scope.$on('musicPlayer.setPlaybackStateDisplay', function(event, data) {
                    $scope.systemActive = data.systemIsActive;
                    if ($scope.systemActive) {
                        $scope.isPlaying = data.isPlaying;
                        $scope.isPaused = data.isPaused;
                        $scope.isAtEnd = data.isAtEnd;
                    } else {
                        $scope.currentTrack.title = 'System Off';
                        $scope.currentTrack.artist = '';
                        $scope.currentTrack.album = '';
                        $scope.trackNumber = 0;
                        $scope.totalTracks = 0;
                        $scope.isPlaying = false;
                        $scope.isPaused = true;
                        $scope.isAtEnd = true;
                    }
                    // $scope.$apply();
                });

                $scope.$on('musicPlayer.setVolumeDisplay', function(event, data) {
                    $scope.volume = data.volumeLevel;
                    $scope.maxVolume = data.maxVolume; // Though UI max is 1
                    // $scope.$apply();
                });

                $scope.$on('musicPlayer.setShuffleDisplay', function(event, data) {
                    $scope.isShuffleOn = data.isShuffleOn;
                    // $scope.$apply();
                });

                $scope.$on('musicPlayer.setRepeatDisplay', function(event, data) {
                    $scope.repeatMode = data.repeatModeString;
                    // $scope.$apply();
                });

                $scope.$on('musicPlayer.showNotificationInUi', function(event, data) {
                    console.log('Received broadcast Notification:', data);
                     if (data.type === 'ignition_off') {
                        $scope.ignitionOn = false;
                        $scope.systemActive = false;
                        $scope.currentTrack.title = 'Ignition Off';
                        $scope.currentTrack.artist = '';
                        $scope.currentTrack.album = '';
                        $scope.trackNumber = 0;
                        $scope.totalTracks = 0;
                        $scope.isPlaying = false;
                        $scope.isPaused = true;
                    } else if (data.type === 'ignition_on') {
                        $scope.ignitionOn = true;
                    } else if (data.type === 'system_off') {
                        $scope.systemActive = false;
                        $scope.currentTrack.title = 'System Off';
                        $scope.currentTrack.artist = '';
                        $scope.currentTrack.album = '';
                        $scope.trackNumber = 0;
                        $scope.totalTracks = 0;
                        $scope.isPlaying = false;
                        $scope.isPaused = true;
                    } else if (data.type === 'system_on') {
                        $scope.systemActive = true;
                    }

                    $scope.notification.message = data.message;
                    $scope.notification.type = data.type;
                    $scope.notification.visible = true;
                    setTimeout(function() {
                        $scope.$apply(function() { // Need $apply for timeout
                           $scope.notification.visible = false;
                        });
                    }, data.duration || 3000);
                    // $scope.$apply(); // Potentially needed if initial notification setting is outside digest
                });


                // Initial state request from Lua when controller loads
                if (typeof bngApi === 'undefined') {
                    console.warn("bngApi is not defined. Running in local test mode. Mock data used.");
                    $scope.systemActive = true;
                    $scope.ignitionOn = true;
                    // Directly set scope for mock, as broadcast won't be caught by same scope easily
                    $scope.currentTrack.title = "Test Track";
                    $scope.currentTrack.artist = "Test Artist";
                    $scope.currentTrack.album = "Test Album";
                    $scope.trackNumber = 1;
                    $scope.totalTracks = 5;
                    $scope.isPlaying = false;
                    $scope.isPaused = true;
                    $scope.isAtEnd = false;
                    // $scope.systemActive is already true for mock
                    $scope.volume = 0.5;
                    $scope.isShuffleOn = false;
                    $scope.repeatMode = "off";
                } else {
                    console.log("Music player UI directive initialized. Requesting full state from Lua...");
                    bngApi.engineLua('extensions.auto.StereoSystem.requestFullStateUpdate()');
                }
            }
        };
    }]);

// --- Global Functions callable from Lua via executeJS (now use $rootScope.$broadcast) ---
// Helper to get $rootScope, assuming Angular app is on document.body or a known element
function getRootScope() {
    var appElement = document.querySelector('music-player-ui') || document.body; // Fallback to body
    var injector = angular.element(appElement).injector();
    return injector ? injector.get('$rootScope') : null;
}

window.updateTrackDisplay = function(title, artist, album, trackNumber, totalTracks) {
    var $rootScope = getRootScope();
    if ($rootScope) {
        $rootScope.$broadcast('musicPlayer.updateTrackDisplay', { title: title, artist: artist, album: album, trackNumber: trackNumber, totalTracks: totalTracks });
        $rootScope.$apply(); // Ensure digest cycle runs if called from non-Angular context
    } else {
        console.error("MusicPlayer: $rootScope not found for updateTrackDisplay");
    }
};

window.setPlaybackStateDisplay = function(isPlaying, isPaused, isAtEnd, systemIsActive) {
    var $rootScope = getRootScope();
    if ($rootScope) {
        $rootScope.$broadcast('musicPlayer.setPlaybackStateDisplay', { isPlaying: isPlaying, isPaused: isPaused, isAtEnd: isAtEnd, systemIsActive: systemIsActive });
        $rootScope.$apply();
    } else {
        console.error("MusicPlayer: $rootScope not found for setPlaybackStateDisplay");
    }
};

window.setVolumeDisplay = function(volumeLevel, maxVolume) {
    var $rootScope = getRootScope();
    if ($rootScope) {
        $rootScope.$broadcast('musicPlayer.setVolumeDisplay', { volumeLevel: volumeLevel, maxVolume: maxVolume });
        $rootScope.$apply();
    } else {
        console.error("MusicPlayer: $rootScope not found for setVolumeDisplay");
    }
};

window.setShuffleDisplay = function(isShuffleOn) {
    var $rootScope = getRootScope();
    if ($rootScope) {
        $rootScope.$broadcast('musicPlayer.setShuffleDisplay', { isShuffleOn: isShuffleOn });
        $rootScope.$apply();
    } else {
        console.error("MusicPlayer: $rootScope not found for setShuffleDisplay");
    }
};

window.setRepeatDisplay = function(repeatModeString) {
    var $rootScope = getRootScope();
    if ($rootScope) {
        $rootScope.$broadcast('musicPlayer.setRepeatDisplay', { repeatModeString: repeatModeString });
        $rootScope.$apply();
    } else {
        console.error("MusicPlayer: $rootScope not found for setRepeatDisplay");
    }
};

window.showNotificationInUi = function(message, type, duration) {
    var $rootScope = getRootScope();
    if ($rootScope) {
        $rootScope.$broadcast('musicPlayer.showNotificationInUi', { message: message, type: type, duration: duration });
        $rootScope.$apply();
    } else {
        console.error("MusicPlayer: $rootScope not found for showNotificationInUi");
    }
};
