import '../models/syllabus_models.dart';
import '../providers/reference_data_store.dart';
import 'api_service.dart';

class SyllabusService {
  /// Curriculum bundles are non-user-specific reference data — cached
  /// long-TTL and shared across the app via [ReferenceDataStore].
  Future<CurriculumBundle> getCurriculum({
    required String collegeCode,
    required String courseCode,
    String? regulation,
  }) =>
      ReferenceDataStore.instance.getCurriculum(
        collegeCode: collegeCode,
        courseCode: courseCode,
        regulation: regulation,
      );

  Future<void> clearCache() =>
      ReferenceDataStore.instance.clearAllCurriculumCache();

  Future<void> clearCurriculumCache({
    required String collegeCode,
    required String courseCode,
  }) =>
      ReferenceDataStore.instance.clearCurriculumCache(
        collegeCode: collegeCode,
        courseCode: courseCode,
      );

  List<CurriculumSubject> getSubjectsForSemester(
    CurriculumBundle bundle, {
    required int semester,
  }) {
    return bundle.subjects
        .where((s) => s.semester == semester && !s.isOption)
        .toList();
  }

  List<CurriculumSubject> getElectiveOptions(
    CurriculumBundle bundle, {
    required String electiveType,
  }) {
    return bundle.subjects
        .where((s) => s.isOption && s.electiveType == electiveType)
        .toList();
  }

  // Saved subjects are user-created data (what the student actually
  // selected), not reference data — fetched directly from the API rather
  // than through ReferenceDataStore. Callers that want this cached go
  // through AppStateNotifier.savedSubjectsBox instead.
  Future<SavedSyllabus?> getSavedSyllabus(int semester) async {
    try {
      final json = await ApiService.instance
          .get('/syllabus/subjects/$semester') as Map<String, dynamic>;
      return SavedSyllabus.fromJsonOrNull(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<SavedSubject>?> getSavedSubjects(int semester) async {
    final saved = await getSavedSyllabus(semester);
    return saved?.subjects;
  }

  Future<void> saveSubjects({
    required int semester,
    required String regulation,
    required List<SavedSubject> subjects,
  }) async {
    await ApiService.instance.post('/syllabus/subjects', {
      'semester': semester,
      'regulation': regulation,
      'subjects': subjects.map((s) => s.toJson()).toList(),
    });
  }
}
