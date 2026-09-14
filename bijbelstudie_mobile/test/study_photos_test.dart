import 'dart:io';

import 'package:bijbelstudie_mobile/features/studies/data/study_photos.dart';
import 'package:bijbelstudie_mobile/features/studies/present/study_banner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors `tests/studyPhotos.test.ts` in the website repo.
void main() {
  test('covers the whole catalogue: 66 book studies plus the authored ones', () {
    // Same count as the website's STUDY_PHOTOS. A change here means the two
    // tables have drifted - copy the entry and its files from the website.
    // (Daniel's book study is the authored `daniel`, hence 65 `boek-` ids.)
    expect(kStudyPhotos.length, 76);
    expect(kStudyPhotos.keys.where((id) => id.startsWith('boek-')).length, 65);
  });

  test('never gives two studies the same photo', () {
    final ids = kStudyPhotos.values.toList();
    expect(ids.toSet().length, ids.length);
  });

  test('backs every entry with both bundled files', () {
    for (final studyId in kStudyPhotos.keys) {
      final photo = studyPhotoFor(studyId)!;
      expect(File(photo.banner).existsSync(), isTrue, reason: photo.banner);
      expect(File(photo.thumb).existsSync(), isTrue, reason: photo.thumb);
    }
  });

  test('registers the photo folder as an asset directory', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- $kStudyPhotoDir/'));
  });

  test('returns null for a study without a photo', () {
    expect(studyPhotoFor('bestaat-niet'), isNull);
  });

  test('picks the thumbnail for square-ish boxes, like the website', () {
    expect(StudyBanner.useThumb(BoxConstraints.tight(const Size(52, 52))), isTrue);
    expect(StudyBanner.useThumb(BoxConstraints.tight(const Size(320, 120))), isFalse);
    expect(StudyBanner.useThumb(const BoxConstraints()), isFalse);
  });
}
