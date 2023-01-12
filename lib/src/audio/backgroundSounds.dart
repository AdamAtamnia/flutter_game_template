// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const Set<BackgroundSound> backgroundSounds = {
  // Filenames with whitespace break package:audioplayers on iOS
  // (as of February 2022), so we use no whitespace.
  BackgroundSound('Mr_Smith-Azul.mp3', 'Azul', artist: 'Mr Smith'),
  BackgroundSound('Mr_Smith-Sonorus.mp3', 'Sonorus', artist: 'Mr Smith'),
  BackgroundSound('Mr_Smith-Sunday_Solitude.mp3', 'SundaySolitude', artist: 'Mr Smith'),
};

class BackgroundSound {
  final String filename;

  final String name;

  final String? artist;

  const BackgroundSound(this.filename, this.name, {this.artist});

  @override
  String toString() => 'Song<$filename>';
}
