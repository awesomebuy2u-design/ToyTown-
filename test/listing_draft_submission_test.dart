import 'package:flutter_test/flutter_test.dart';
import 'package:toytown/listing_draft_submission.dart';

void main() {
  const path = 'family/listing.webp';

  test('retry keeps the same draft and skips an acknowledged photo upload',
      () async {
    final values = <String, Object?>{'id': 'listing', 'title': 'Кіт'};
    final draft = ListingDraftSubmission(values, photoPath: path);
    var uploads = 0;
    final saved = <Map<String, Object?>>[];
    Future<void> send() => draft.send(
          uploadPhoto: (path) async {
            uploads++;
          },
          photoExists: (_) async => false,
          saveDraft: (row) async {
            saved.add(row);
            if (saved.length == 1) throw StateError('Lost insert response');
          },
        );

    await expectLater(send(), throwsStateError);
    values['title'] = 'Змінена назва';
    await send();

    expect(uploads, 1);
    expect(saved, List.filled(2, {'id': 'listing', 'title': 'Кіт'}));
  });

  test('a lost upload response is recovered only if that photo exists',
      () async {
    final draft = ListingDraftSubmission({'id': 'listing'}, photoPath: path);
    var exists = false;
    var saves = 0;
    Future<void> send() => draft.send(
          uploadPhoto: (_) async => throw StateError('Lost upload response'),
          photoExists: (uploadedPath) async {
            expect(uploadedPath, path);
            return exists;
          },
          saveDraft: (_) async {
            saves++;
          },
        );

    await expectLater(send(), throwsStateError);
    expect(saves, 0);
    exists = true;
    await send();
    expect(saves, 1);
  });
}
