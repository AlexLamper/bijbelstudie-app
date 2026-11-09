import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One extra question the assistant's empty state offers first, above its
/// three standing suggestions.
///
/// Set by whoever knows what the reader is looking at - today only the
/// onboarding guide, which offers a question about the verse the reader just
/// marked ("Wat betekent vers 3?") - and cleared by the same owner. Null shows
/// the standing suggestions alone.
final aiSuggestedQuestionProvider = NotifierProvider<AiSuggestedQuestion, String?>(
  AiSuggestedQuestion.new,
);

class AiSuggestedQuestion extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? question) => state = question;
}
