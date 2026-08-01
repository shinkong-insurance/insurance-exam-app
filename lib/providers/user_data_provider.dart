import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/user_data_repository.dart';
import '../models/exam_record.dart';

final userDataRepositoryProvider = Provider<UserDataRepository>(
  (_) => UserDataRepository(),
);

final wrongIdsProvider = FutureProvider<List<int>>((ref) {
  return ref.read(userDataRepositoryProvider).getWrongQuestionIds();
});

final favoriteIdsProvider = FutureProvider<List<int>>((ref) {
  return ref.read(userDataRepositoryProvider).getFavoriteIds();
});

final progressProvider = FutureProvider<Map<int, Map<String, int>>>((ref) {
  return ref.read(userDataRepositoryProvider).getProgress();
});

final examRecordsProvider = FutureProvider<List<ExamRecord>>((ref) {
  return ref.read(userDataRepositoryProvider).getExamRecords();
});
