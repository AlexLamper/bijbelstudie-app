/// The level-up chime, synthesised into a WAV rather than shipped as an asset.
///
/// The website builds its sounds with a handful of Web Audio nodes
/// (`lib/studySound.ts`, `lib/levensboomSound.ts`); this is the same idea on
/// this side. A rising major triad is a few hundred lines of arithmetic, so
/// there is no reason to put an audio file in the app binary, keep it in sync
/// with the web's version, or have App Store review look at it.
///
/// The notes match `playLevelUp` on the website exactly, so a reader who levels
/// up on the phone and again on the website hears the same thing.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const int _sampleRate = 44100;

/// D5, F#5, A5, then the octave a beat later. Slower and softer than the
/// lesson-complete sound: finishing a lesson happens most days and wants a
/// brisk "done"; a level-up is rare and wants something that opens out.
const List<({double frequency, double at, double gain, double tail})> _notes = [
  (frequency: 587.33, at: 0.00, gain: 0.055, tail: 0.5),
  (frequency: 739.99, at: 0.13, gain: 0.055, tail: 0.5),
  (frequency: 880.00, at: 0.26, gain: 0.055, tail: 0.5),
  // The last note is the one that lands, so it is given the longest tail.
  (frequency: 1174.66, at: 0.46, gain: 0.070, tail: 1.1),
];

Uint8List? _cached;

/// A mono 16-bit WAV of the chime. Built once per process and reused.
Uint8List levelUpChimeWav() {
  final cached = _cached;
  if (cached != null) return cached;

  const total = 1.7;
  final frames = (_sampleRate * total).round();
  final samples = Float64List(frames);

  for (final note in _notes) {
    final start = (note.at * _sampleRate).round();
    final length = (note.tail * _sampleRate).round();
    for (var i = 0; i < length; i++) {
      final index = start + i;
      if (index >= frames) break;
      final t = i / _sampleRate;
      // A short attack so it does not click, then an exponential decay - the
      // shape a struck string has, and what the Web Audio ramps produce.
      final attack = t < 0.03 ? t / 0.03 : 1.0;
      final decay = math.exp(-t * (3.6 / note.tail));
      samples[index] +=
          math.sin(2 * math.pi * note.frequency * t) * note.gain * attack * decay;
    }
  }

  _cached = _encodeWav(samples);
  return _cached!;
}

/// Minimal 16-bit PCM WAV container. Values are clamped rather than normalised:
/// the gains above are chosen to sit well under full scale, and normalising
/// would make a quiet chime as loud as a notification.
Uint8List _encodeWav(Float64List samples) {
  final dataBytes = samples.length * 2;
  final out = ByteData(44 + dataBytes);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      out.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // PCM chunk size
  out.setUint16(20, 1, Endian.little); // format: PCM
  out.setUint16(22, 1, Endian.little); // channels: mono
  out.setUint32(24, _sampleRate, Endian.little);
  out.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
  out.setUint16(32, 2, Endian.little); // block align
  out.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  out.setUint32(40, dataBytes, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    out.setInt16(44 + i * 2, (clamped * 32767).round(), Endian.little);
  }

  return out.buffer.asUint8List();
}
