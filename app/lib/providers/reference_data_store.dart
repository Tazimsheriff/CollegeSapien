import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cache/cache_box.dart';
import '../core/cache/cache_box_family.dart';
import '../models/api_models.dart';
import '../models/syllabus_models.dart';
import '../services/api_service.dart';
import '../utils/department_constants.dart';

/// Non-user-specific data shared across every user of a college/department —
/// colleges, departments, and curriculum bundles. Long TTLs, safe to keep
/// warm across sign-out/account switches (unlike AppStateNotifier, this is
/// deliberately NOT cleared on sign-out).
class ReferenceDataStore extends ChangeNotifier {
  ReferenceDataStore._() {
    collegesBox.addListener(notifyListeners);
    departmentsBox.addListener(notifyListeners);
  }

  static final ReferenceDataStore instance = ReferenceDataStore._();

  static const referenceTtl = Duration(hours: 24);
  static const curriculumTtl = Duration(days: 1);
  static const _curriculumPrefsPrefix = 'ref_curriculum_';

  final collegesBox = CacheBox<List<College>>(
    prefsKey: 'ref_colleges',
    ttl: referenceTtl,
    decode: (json) => (json as List<dynamic>)
        .map((item) => College.fromJson(item as Map<String, dynamic>))
        .toList(),
    encode: (value) => value.map((item) => item.toJson()).toList(),
  );

  final departmentsBox = CacheBox<List<Department>>(
    prefsKey: 'ref_departments',
    ttl: referenceTtl,
    decode: (json) => (json as List<dynamic>)
        .map((item) => Department.fromJson(item as Map<String, dynamic>))
        .toList(),
    encode: (value) => value.map((item) => item.toJson()).toList(),
  );

  final curriculumFamily = CacheBoxFamily<CurriculumBundle>(
    ttl: curriculumTtl,
    prefsKeyFor: (key) => '$_curriculumPrefsPrefix$key',
    decode: (json) => CurriculumBundle.fromJson(json as Map<String, dynamic>),
    encode: _curriculumToJson,
  );

  // Fallback colleges for offline & empty cache on first boot.
  static const List<Map<String, String>> _fallbackColleges = [
    {'id': 'col_ssn', 'name': 'SSN College of Engineering', 'code': 'SSN'},
    {'id': 'col_aua', 'name': 'Anna University Affiliated', 'code': 'AUA'},
    {'id': 'col_panimalar', 'name': 'Panimalar Engineering College', 'code': 'PEC'},
    {'id': 'col_sairam', 'name': 'Sri Sairam Engineering College', 'code': 'SEC'},
  ];

  bool _mastersHydrated = false;
  Future<void>? _combinedFetchInFlight;

  Future<List<College>> listColleges({bool forceRefresh = false}) async {
    await _ensureCombinedMasters(forceRefresh: forceRefresh);
    return collegesBox.staleValueOrNull ?? [];
  }

  Future<List<Department>> listDepartments({bool forceRefresh = false}) async {
    await _ensureCombinedMasters(forceRefresh: forceRefresh);
    return departmentsBox.staleValueOrNull ?? [];
  }

  Future<void> _ensureCombinedMasters({bool forceRefresh = false}) async {
    if (!_mastersHydrated) {
      await Future.wait([collegesBox.hydrate(), departmentsBox.hydrate()]);
      _mastersHydrated = true;
    }
    if (!forceRefresh && collegesBox.isValid && departmentsBox.isValid) return;
    if (_combinedFetchInFlight != null) {
      await _combinedFetchInFlight;
      return;
    }
    final future = _fetchCombinedMasters();
    _combinedFetchInFlight = future.whenComplete(() => _combinedFetchInFlight = null);
    await _combinedFetchInFlight;
  }

  Future<void> _fetchCombinedMasters() async {
    try {
      final response = await ApiService.instance.get('/colleges/combined')
          as Map<String, dynamic>;
      final collegesList = (response['colleges'] as List<dynamic>? ?? [])
          .map((item) => College.fromJson(item as Map<String, dynamic>))
          .toList();
      final deptsList = (response['departments'] as List<dynamic>? ?? [])
          .map((item) => Department.fromJson(item as Map<String, dynamic>))
          .toList();
      await collegesBox.set(collegesList);
      await departmentsBox.set(deptsList);
    } catch (_) {
      // Offline / API error: keep whatever's already cached (even if
      // stale), otherwise fall back to hardcoded defaults.
      if (collegesBox.hasValue && departmentsBox.hasValue) return;
      await collegesBox.set(_fallbackColleges
          .map((c) => College(id: c['id']!, name: c['name']!, code: c['code']!))
          .toList());
      await departmentsBox.set(defaultDepartments);
    }
  }

  Future<CurriculumBundle> getCurriculum({
    required String collegeCode,
    required String courseCode,
    String? regulation,
  }) async {
    final key = '${collegeCode}_${courseCode}_${regulation ?? 'latest'}';
    final box = curriculumFamily[key];
    if (!box.hasValue) await box.hydrate();
    try {
      return await box.getOrFetch(
        () => _fetchCurriculum(
          collegeCode: collegeCode,
          courseCode: courseCode,
          regulation: regulation,
        ),
      );
    } catch (e) {
      final stale = box.staleValueOrNull;
      if (stale != null) return stale;
      rethrow;
    }
  }

  Future<CurriculumBundle> _fetchCurriculum({
    required String collegeCode,
    required String courseCode,
    String? regulation,
  }) async {
    final query =
        StringBuffer('/curriculum?collegeCode=$collegeCode&courseCode=$courseCode');
    if (regulation != null) query.write('&regulation=$regulation');
    final json =
        await ApiService.instance.get(query.toString()) as Map<String, dynamic>;
    return CurriculumBundle.fromJson(json);
  }

  /// Clears every cached curriculum bundle, for every college/department —
  /// used when a profile change wipes academic data server-side.
  Future<void> clearAllCurriculumCache() async {
    curriculumFamily.invalidateMatching((_) => true);
    await _removePrefsByPrefix(_curriculumPrefsPrefix);
  }

  /// Clears cached curriculum bundles for one college/course (all
  /// regulations) — used by the "refresh curriculum" affordance.
  Future<void> clearCurriculumCache({
    required String collegeCode,
    required String courseCode,
  }) async {
    final prefix = '$_curriculumPrefsPrefix${collegeCode}_$courseCode';
    curriculumFamily.invalidateMatching(
        (key) => '$_curriculumPrefsPrefix$key'.startsWith(prefix));
    await _removePrefsByPrefix(prefix);
  }

  Future<void> _removePrefsByPrefix(String prefix) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}

Map<String, dynamic> _curriculumToJson(CurriculumBundle value) => {
      'collegeCode': value.collegeCode,
      'courseCode': value.courseCode,
      'regulation': value.regulation,
      'availableRegulations': value.availableRegulations,
      'subjects': value.subjects
          .map((s) => {
                'college_code': s.collegeCode,
                'course_code': s.courseCode,
                'regulation': s.regulation,
                'semester': s.semester,
                'subject_code': s.subjectCode,
                'subject_name': s.subjectName,
                'credits': s.credits,
                'category': s.category,
                'elective_type': s.electiveType,
                'record_type': s.recordType,
              })
          .toList(),
    };
