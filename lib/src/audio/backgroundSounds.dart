// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const Set<BackgroundSound> backgroundSounds = {
  // Filenames with whitespace break package:audioplayers on iOS
  // (as of February 2022), so we use no whitespace.
  BackgroundSound('Water_2.wav', 'flowOfWater'),
};

class BackgroundSound {
  final String filename;

  final String name;

  final String? artist;

  const BackgroundSound(this.filename, this.name, {this.artist});

  @override
  String toString() => 'BackgroundSound<$filename>';
}
