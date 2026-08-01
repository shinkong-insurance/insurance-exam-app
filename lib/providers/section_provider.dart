import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/section.dart';
import '../repositories/question_repository.dart';
import 'question_provider.dart';

final allSectionsProvider = FutureProvider<List<Section>>((ref) {
  return ref.read(questionRepositoryProvider).getAllSections();
});

final chapterSectionsProvider =
    FutureProvider.family<List<Section>, int>((ref, chapterId) {
  return ref.read(questionRepositoryProvider).getSectionsByChapter(chapterId);
});
