// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import '../settings/settings.dart';
import 'backgroundSounds.dart';
import 'sounds.dart';

/// Allows playing backgroundSound and sound. A facade to `package:audioplayers`.
class AudioController {
  static final _log = Logger('AudioController');

  final AudioPlayer _backgroundSoundPlayer;

  /// This is a list of [AudioPlayer] instances which are rotated to play
  /// sound effects.
  final List<AudioPlayer> _sfxPlayers;

  int _currentSfxPlayer = 0;

  final Queue<BackgroundSound> _playlist;

  final Random _random = Random();

  SettingsController? _settings;

  ValueNotifier<AppLifecycleState>? _lifecycleNotifier;

  /// Creates an instance that plays backgroundSound and sound.
  ///
  /// Use [polyphony] to configure the number of sound effects (SFX) that can
  /// play at the same time. A [polyphony] of `1` will always only play one
  /// sound (a new sound will stop the previous one). See discussion
  /// of [_sfxPlayers] to learn why this is the case.
  ///
  /// Background backgroundSound does not count into the [polyphony] limit. backgroundSound will
  /// never be overridden by sound effects because that would be silly.
  AudioController({int polyphony = 2})
      : assert(polyphony >= 1),
        _backgroundSoundPlayer = AudioPlayer(playerId: 'backgroundSoundPlayer'),
        _sfxPlayers = Iterable.generate(
                polyphony, (i) => AudioPlayer(playerId: 'sfxPlayer#$i'))
            .toList(growable: false),
        _playlist = Queue.of(List<BackgroundSound>.of(backgroundSounds)..shuffle()) {
    _backgroundSoundPlayer.onPlayerComplete.listen(_changeBackgroundSound);
  }

  /// Enables the [AudioController] to listen to [AppLifecycleState] events,
  /// and therefore do things like stopping playback when the game
  /// goes into the background.
  void attachLifecycleNotifier(
      ValueNotifier<AppLifecycleState> lifecycleNotifier) {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);

    lifecycleNotifier.addListener(_handleAppLifecycle);
    _lifecycleNotifier = lifecycleNotifier;
  }

  /// Enables the [AudioController] to track changes to settings.
  /// Namely, when any of [SettingsController.muted],
  /// [SettingsController.backgroundSoundOn] or [SettingsController.soundsOn] changes,
  /// the audio controller will act accordingly.
  void attachSettings(SettingsController settingsController) {
    if (_settings == settingsController) {
      // Already attached to this instance. Nothing to do.
      return;
    }

    // Remove handlers from the old settings controller if present
    final oldSettings = _settings;
    if (oldSettings != null) {
      oldSettings.muted.removeListener(_mutedHandler);
      oldSettings.backgroundSoundOn.removeListener(_backgroundSoundOnHandler);
      oldSettings.soundsOn.removeListener(_soundsOnHandler);
    }

    _settings = settingsController;

    // Add handlers to the new settings controller
    settingsController.muted.addListener(_mutedHandler);
    settingsController.backgroundSoundOn.addListener(_backgroundSoundOnHandler);
    settingsController.soundsOn.addListener(_soundsOnHandler);

    if (!settingsController.muted.value && settingsController.backgroundSoundOn.value) {
      _startBackgroundSound();
    }
  }

  void dispose() {
    _lifecycleNotifier?.removeListener(_handleAppLifecycle);
    _stopAllSound();
    _backgroundSoundPlayer.dispose();
    for (final player in _sfxPlayers) {
      player.dispose();
    }
  }

  /// Preloads all sound effects.
  Future<void> initialize() async {
    _log.info('Preloading sound effects');
    // This assumes there is only a limited number of sound effects in the game.
    // If there are hundreds of long sound effect files, it's better
    // to be more selective when preloading.
    await AudioCache.instance.loadAll(SfxType.values
        .expand(soundTypeToFilename)
        .map((path) => 'sfx/$path')
        .toList());
  }

  /// Plays a single sound effect, defined by [type].
  ///
  /// The controller will ignore this call when the attached settings'
  /// [SettingsController.muted] is `true` or if its
  /// [SettingsController.soundsOn] is `false`.
  void playSfx(SfxType type) {
    final muted = _settings?.muted.value ?? true;
    if (muted) {
      _log.info(() => 'Ignoring playing sound ($type) because audio is muted.');
      return;
    }
    final soundsOn = _settings?.soundsOn.value ?? false;
    if (!soundsOn) {
      _log.info(() =>
          'Ignoring playing sound ($type) because sounds are turned off.');
      return;
    }

    _log.info(() => 'Playing sound: $type');
    final options = soundTypeToFilename(type);
    final filename = options[_random.nextInt(options.length)];
    _log.info(() => '- Chosen filename: $filename');

    final currentPlayer = _sfxPlayers[_currentSfxPlayer];
    currentPlayer.play(AssetSource('sfx/$filename'),
        volume: soundTypeToVolume(type));
    _currentSfxPlayer = (_currentSfxPlayer + 1) % _sfxPlayers.length;
  }

  void _changeBackgroundSound(void _) {
    _log.info('Last BackgroundSound finished playing.');
    // Put the BackgroundSound that just finished playing to the end of the playlist.
    _playlist.addLast(_playlist.removeFirst());
    // Play the next BackgroundSound.
    _playFirstBackgroundSoundInPlaylist();
  }

  void _handleAppLifecycle() {
    switch (_lifecycleNotifier!.value) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _stopAllSound();
        break;
      case AppLifecycleState.resumed:
        if (!_settings!.muted.value && _settings!.backgroundSoundOn.value) {
          _resumeBackgroundSound();
        }
        break;
      case AppLifecycleState.inactive:
        // No need to react to this state change.
        break;
    }
  }

  void _backgroundSoundOnHandler() {
    if (_settings!.backgroundSoundOn.value) {
      // backgroundSound got turned on.
      if (!_settings!.muted.value) {
        _resumeBackgroundSound();
      }
    } else {
      // backgroundSound got turned off.
      _stopBackgroundSound();
    }
  }

  void _mutedHandler() {
    if (_settings!.muted.value) {
      // All sound just got muted.
      _stopAllSound();
    } else {
      // All sound just got un-muted.
      if (_settings!.backgroundSoundOn.value) {
        _resumeBackgroundSound();
      }
    }
  }

  Future<void> _playFirstBackgroundSoundInPlaylist() async {
    _log.info(() => 'Playing ${_playlist.first} now.');
    await _backgroundSoundPlayer.play(AssetSource('background_sound/${_playlist.first.filename}'));
  }

  Future<void> _resumeBackgroundSound() async {
    _log.info('Resuming backgroundSound');
    switch (_backgroundSoundPlayer.state) {
      case PlayerState.paused:
        _log.info('Calling _backgroundSoundPlayer.resume()');
        try {
          await _backgroundSoundPlayer.resume();
        } catch (e) {
          // Sometimes, resuming fails with an "Unexpected" error.
          _log.severe(e);
          await _playFirstBackgroundSoundInPlaylist();
        }
        break;
      case PlayerState.stopped:
        _log.info("resumeBackgroundSound() called when backgroundSound is stopped. "
            "This probably means we haven't yet started the backgroundSound. "
            "For example, the game was started with sound off.");
        await _playFirstBackgroundSoundInPlaylist();
        break;
      case PlayerState.playing:
        _log.warning('resumeBackgroundSound() called when backgroundSound is playing. '
            'Nothing to do.');
        break;
      case PlayerState.completed:
        _log.warning('resumeBackgroundSound() called when backgroundSound is completed. '
            "backgroundSound should never be 'completed' as it's either not playing "
            "or looping forever.");
        await _playFirstBackgroundSoundInPlaylist();
        break;
    }
  }

  void _soundsOnHandler() {
    for (final player in _sfxPlayers) {
      if (player.state == PlayerState.playing) {
        player.stop();
      }
    }
  }

  void _startBackgroundSound() {
    _log.info('starting backgroundSound');
    _playFirstBackgroundSoundInPlaylist();
  }

  void _stopAllSound() {
    if (_backgroundSoundPlayer.state == PlayerState.playing) {
      _backgroundSoundPlayer.pause();
    }
    for (final player in _sfxPlayers) {
      player.stop();
    }
  }

  void _stopBackgroundSound() {
    _log.info('Stopping backgroundSound');
    if (_backgroundSoundPlayer.state == PlayerState.playing) {
      _backgroundSoundPlayer.pause();
    }
  }
}
