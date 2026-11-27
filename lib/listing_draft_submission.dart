/// One immutable submission. The same listing ID and photo path are kept
/// until the server acknowledges the draft.
class ListingDraftSubmission {
  ListingDraftSubmission(Map<String, Object?> values, {this.photoPath})
      : row = Map.unmodifiable(values);

  final Map<String, Object?> row;
  final String? photoPath;
  bool _photoUploaded = false;

  Future<void> send({
    required Future<void> Function(String path) uploadPhoto,
    required Future<bool> Function(String path) photoExists,
    required Future<void> Function(Map<String, Object?> row) saveDraft,
  }) async {
    final path = photoPath;
    if (path != null && !_photoUploaded) {
      try {
        await uploadPhoto(path);
      } catch (_) {
        // The object can already exist if the upload succeeded and its
        // response was lost. The path is unique to this exact submission.
        if (!await photoExists(path)) rethrow;
      }
      _photoUploaded = true;
    }
    await saveDraft(row);
  }
}
