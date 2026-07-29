import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cache/cache_box.dart';
import '../models/api_models.dart';
import '../models/cgpa_models.dart';
import '../models/timetable_models.dart';
import '../models/syllabus_models.dart';
import '../models/event_models.dart';
import 'session_action.dart';

/// Single source of truth for all user-created data: profile, attendance,
/// timetable, saved subjects, events. Cache-first (instant paint from
/// SharedPreferences), TTL-aware, updated optimistically after mutations.
///
/// A singleton so non-widget services (TimetableService, SyllabusService,
/// etc.) can read/write it without threading BuildContext, same as
/// AuthService.instance. Still registered in the widget tree via
/// `ChangeNotifierProvider.value` so existing `Provider.of<AppStateNotifier>`
/// call sites keep working unchanged.
class AppStateNotifier extends ChangeNotifier {
  AppStateNotifier._() {
    for (final box in _boxes) {
      box.addListener(notifyListeners);
    }
  }

  static final AppStateNotifier instance = AppStateNotifier._();

  static const attendanceTtl = Duration(minutes: 5);
  static const timetableTtl = Duration(hours: 1);
  static const eventsTtl = Duration(minutes: 30);
  static const userProfileTtl = Duration(hours: 24);
  static const savedSubjectsTtl = Duration(hours: 1);
  static const cgpaSemestersTtl = Duration(hours: 24);
  static const filesUploadedStatTtl = Duration(minutes: 10);

  final userProfileBox = CacheBox<UserProfile?>(
    prefsKey: 'cache_user_profile',
    ttl: userProfileTtl,
    decode: (json) =>
        json == null ? null : UserProfile.fromJson(json as Map<String, dynamic>),
    encode: (value) => value?.toJson(),
  );

  final attendanceBox = CacheBox<List<AttendanceSummary>>(
    prefsKey: 'cache_attendance_summary',
    ttl: attendanceTtl,
    decode: (json) => (json as List<dynamic>)
        .map((item) => AttendanceSummary.fromJson(item as Map<String, dynamic>))
        .toList(),
    encode: (value) => value.map((item) => item.toJson()).toList(),
  );

  final timetableBox = CacheBox<List<TimetableSubject>>(
    prefsKey: 'cache_timetable_subjects',
    ttl: timetableTtl,
    decode: (json) => (json as List<dynamic>)
        .map((item) => TimetableSubject.fromJson(item as Map<String, dynamic>))
        .toList(),
    encode: (value) => value.map((item) => item.toJson()).toList(),
  );

  // Small piece of metadata that rides along with the timetable fetch but
  // isn't part of the subjects list itself — kept as its own box rather
  // than folded into TimetableSubject so setTimetableSubjects()'s signature
  // (used by /auth/sync callers) doesn't need to change.
  final timetableTrackingStartDateBox = CacheBox<String?>(
    prefsKey: 'cache_timetable_tracking_start_date',
    ttl: timetableTtl,
    decode: (json) => json as String?,
    encode: (value) => value,
  );

  final savedSubjectsBox = CacheBox<List<SavedSubject>>(
    prefsKey: 'cache_saved_subjects',
    ttl: savedSubjectsTtl,
    decode: (json) => (json as List<dynamic>)
        .map((item) => SavedSubject.fromJson(item as Map<String, dynamic>))
        .toList(),
    encode: (value) => value.map((item) => item.toJson()).toList(),
  );

  final eventsBox = CacheBox<List<EventItem>>(
    prefsKey: 'cache_events',
    ttl: eventsTtl,
    decode: (json) => (json as List<dynamic>)
        .map((item) => EventItem.fromJson(item as Map<String, dynamic>))
        .toList(),
    encode: (value) => value.map((item) => item.toJson()).toList(),
  );

  // The user's own CGPA entries — source of truth for both the CGPA
  // calculator screen and the profile screen's CGPA stat (derived from
  // this rather than cached separately as a redundant formatted string).
  final cgpaSemestersBox = CacheBox<List<CgpaSemesterEntry>>(
    prefsKey: 'cache_cgpa_semesters',
    ttl: cgpaSemestersTtl,
    decode: (json) => (json as List<dynamic>)
        .map((item) => CgpaSemesterEntry.fromJson(item as Map<String, dynamic>))
        .toList(),
    encode: (value) => value.map((item) => item.toJson()).toList(),
  );

  // No cheaper source of truth to derive this from locally (it's a live
  // count over the resources hub), so it's cached as its own short-TTL stat.
  final filesUploadedStatBox = CacheBox<String>(
    prefsKey: 'cache_files_uploaded_stat',
    ttl: filesUploadedStatTtl,
    decode: (json) => json as String,
    encode: (value) => value,
  );

  late final List<CacheBoxLike> _boxes = [
    userProfileBox,
    attendanceBox,
    timetableBox,
    timetableTrackingStartDateBox,
    savedSubjectsBox,
    eventsBox,
    cgpaSemestersBox,
    filesUploadedStatBox,
  ];

  // True when the cached saved subjects were seeded from the curriculum
  // instead of the user's own saved selection — the home screen uses this
  // to show the "tap to update with your electives" hint. Small/simple
  // enough to keep as a plain flag rather than its own CacheBox.
  bool _savedSubjectsFromCurriculum = false;
  static const _savedSubjectsFallbackKey = 'cache_saved_subjects_fallback';

  // Hydration from local storage — call once at startup.
  Future<void> loadFromLocalCache() async {
    await Future.wait(_boxes.map((box) => box.hydrate()));
    try {
      final prefs = await SharedPreferences.getInstance();
      _savedSubjectsFromCurriculum =
          prefs.getBool(_savedSubjectsFallbackKey) ?? false;
    } catch (_) {}
    notifyListeners();
  }

  // Getters (backward-compatible facade)
  UserProfile? get userProfile => userProfileBox.valueOrNull;

  // Regardless of TTL — for offline-tolerant fallbacks. Replaces the old
  // AuthService._profile secondary copy, which could drift from this one.
  UserProfile? get userProfileStale => userProfileBox.staleValueOrNull;

  List<AttendanceSummary>? get attendanceSummary => attendanceBox.valueOrNull;

  List<TimetableSubject>? get timetableSubjects => timetableBox.valueOrNull;

  List<SavedSubject>? get savedSubjects => savedSubjectsBox.valueOrNull;

  bool get savedSubjectsFromCurriculum => _savedSubjectsFromCurriculum;

  List<EventItem>? get events => eventsBox.valueOrNull;

  // True once profile + attendance + timetable are all within their TTLs —
  // lets callers skip re-hitting /auth/sync when the cache is still good.
  bool get hasFreshHomeData =>
      userProfileBox.isValid && attendanceBox.isValid && timetableBox.isValid;

  // Setters
  void setUserProfile(UserProfile? data) => userProfileBox.set(data);

  void setAttendanceSummary(List<AttendanceSummary> data) =>
      attendanceBox.set(data);

  void setTimetableSubjects(List<TimetableSubject> data) =>
      timetableBox.set(data);

  void setSavedSubjects(List<SavedSubject> data, {bool fromCurriculum = false}) {
    savedSubjectsBox.set(data);
    _savedSubjectsFromCurriculum = fromCurriculum;
    notifyListeners();
    _saveBoolToPrefs(_savedSubjectsFallbackKey, fromCurriculum);
  }

  void setEvents(List<EventItem> data) => eventsBox.set(data);

  // Invalidation
  void invalidateAttendanceSummary() => attendanceBox.invalidate();

  void invalidateTimetableSubjects() {
    timetableBox.invalidate();
    timetableTrackingStartDateBox.invalidate();
  }

  void invalidateUserProfile() => userProfileBox.invalidate();

  void invalidateSavedSubjects() {
    savedSubjectsBox.invalidate();
    _savedSubjectsFromCurriculum = false;
    notifyListeners();
    _removeFromPrefs(_savedSubjectsFallbackKey);
  }

  // Clears everything tied to the user's college/department/semester —
  // used after a profile change wipes the academic data on the server.
  void invalidateAcademicData() {
    attendanceBox.invalidate();
    timetableBox.invalidate();
    timetableTrackingStartDateBox.invalidate();
    savedSubjectsBox.invalidate();
    _savedSubjectsFromCurriculum = false;
    notifyListeners();
    _removeFromPrefs(_savedSubjectsFallbackKey);
  }

  void invalidateEvents() => eventsBox.invalidate();

  // Wipes every cached field — must be called on sign-out / account switch
  // so a second account on the same device never inherits stale data.
  void invalidateAll() {
    for (final box in _boxes) {
      box.invalidate();
    }
    _savedSubjectsFromCurriculum = false;
    _pendingSessionAction = SessionAction.none;
    notifyListeners();
    _removeFromPrefs(_savedSubjectsFallbackKey);
  }

  // Session redirect mechanism — lets background work (e.g. splash screen's
  // reconciliation sync) tell the app to bounce to Login/Onboarding even
  // when a different screen is already showing. See SessionGuard.
  SessionAction _pendingSessionAction = SessionAction.none;
  SessionAction get pendingSessionAction => _pendingSessionAction;

  void requestSessionAction(SessionAction action) {
    if (action == _pendingSessionAction) return;
    _pendingSessionAction = action;
    notifyListeners();
  }

  void clearSessionAction() {
    _pendingSessionAction = SessionAction.none;
  }

  // Preferences helpers (only needed for the standalone bool flag above —
  // everything else goes through CacheBox).
  Future<void> _saveBoolToPrefs(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _removeFromPrefs(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}
