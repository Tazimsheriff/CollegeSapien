import 'package:flutter/material.dart';
import '../models/syllabus_models.dart';
import '../models/timetable_models.dart';
import '../providers/app_state_notifier.dart';
import '../services/timetable_service.dart';
import '../utils/breakpoints.dart';
import '../utils/app_spacing.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/searchable_dropdown.dart';
import 'syllabus/syllabus_selection_screen.dart';

class TimetableListScreen extends StatefulWidget {
  const TimetableListScreen({super.key});

  @override
  State<TimetableListScreen> createState() => _TimetableListScreenState();
}

class _TimetableListScreenState extends State<TimetableListScreen> {
  static const _weekdayOrder = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  final TimetableService _timetableService = TimetableService();
  List<TimetableSubject> _subjects = [];
  bool _isLoading = true;
  // Sticks once the student taps a day tab; before that the view falls back
  // to _defaultDay() below so it stays live as _subjects loads/changes.
  String? _userSelectedDay;

  String get _selectedDay => _userSelectedDay ?? _defaultDay();

  @override
  void initState() {
    super.initState();
    final cached = AppStateNotifier.instance.timetableSubjects;
    if (cached != null) {
      _subjects = cached;
      _isLoading = false;
    }
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    if (_subjects.isEmpty) setState(() => _isLoading = true);
    try {
      final subjects = await _timetableService.getAllSubjects();
      setState(() {
        _subjects = subjects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading subjects: $e')),
        );
      }
    }
  }

  int _slotMinutes(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return h * 60 + m;
  }

  bool _slotsOverlap(Map<String, String> a, Map<String, String> b) {
    if (a['day'] != b['day']) return false;
    final aStart = _slotMinutes(a['startTime'] ?? '00:00');
    final aEnd = _slotMinutes(a['endTime'] ?? '00:00');
    final bStart = _slotMinutes(b['startTime'] ?? '00:00');
    final bEnd = _slotMinutes(b['endTime'] ?? '00:00');
    return aStart < bEnd && bStart < aEnd;
  }

  // Checks the slots about to be saved against every class already on any
  // other subject (same-day, overlapping time) and against each other, so a
  // student can't double-book a period. Returns a user-facing message for
  // the first conflict found, or null if there are none.
  String? _findSlotConflict(
    List<Map<String, String>> newSlots,
    Iterable<TimetableSubject> otherSubjects,
  ) {
    for (var i = 0; i < newSlots.length; i++) {
      final slot = newSlots[i];
      for (final other in otherSubjects) {
        for (final c in other.classes) {
          final existingSlot = {
            'day': c.day,
            'startTime': c.startTime,
            'endTime': c.endTime,
          };
          if (_slotsOverlap(slot, existingSlot)) {
            return '${slot['day']} ${slot['startTime']}–${slot['endTime']} '
                'overlaps ${other.name}\'s ${c.startTime}–${c.endTime} slot.';
          }
        }
      }
      for (var j = i + 1; j < newSlots.length; j++) {
        if (_slotsOverlap(slot, newSlots[j])) {
          return 'You have two overlapping slots on ${slot['day']}.';
        }
      }
    }
    return null;
  }

  // MON-FRI are always shown (even with nothing scheduled yet); SAT/SUN
  // only show up once at least one class actually lands on them, so the
  // tab bar doesn't waste space on weekend days nobody uses.
  List<String> _visibleDays() {
    final hasSat = _subjects.any((s) => s.classes.any((c) => c.day == 'SAT'));
    final hasSun = _subjects.any((s) => s.classes.any((c) => c.day == 'SUN'));
    return ['MON', 'TUE', 'WED', 'THU', 'FRI', if (hasSat) 'SAT', if (hasSun) 'SUN'];
  }

  List<({TimetableSubject subject, TimetableClass cls})> _classesForDay(
      String day) {
    final items = <({TimetableSubject subject, TimetableClass cls})>[];
    for (final s in _subjects) {
      for (final c in s.classes) {
        if (c.day == day) items.add((subject: s, cls: c));
      }
    }
    items.sort((a, b) =>
        _slotMinutes(a.cls.startTime).compareTo(_slotMinutes(b.cls.startTime)));
    return items;
  }

  // Today if it has classes; otherwise the next visible day (wrapping) that
  // does, so opening the screen on a free Tuesday jumps straight to
  // Wednesday's list instead of showing an empty page.
  String _defaultDay() {
    final visible = _visibleDays();
    if (visible.isEmpty) return 'MON';
    final today = _weekdayOrder[(DateTime.now().weekday - 1) % 7];
    var start = visible.contains(today) ? today : visible.first;
    if (_classesForDay(start).isEmpty) {
      final startIndex = visible.indexOf(start);
      for (var i = 1; i <= visible.length; i++) {
        final candidate = visible[(startIndex + i) % visible.length];
        if (_classesForDay(candidate).isNotEmpty) {
          start = candidate;
          break;
        }
      }
    }
    return start;
  }

  // Where the next class on [day] could start: right after the last one
  // already scheduled, or 9am if the day's still empty. Used to pre-fill
  // the Add Slot dialog with a sensible 1-hour default instead of always
  // defaulting to 9-10.
  double _nextAvailableStartHour(String day) {
    final classes = _classesForDay(day);
    if (classes.isEmpty) return 9;
    final lastEnd = _slotMinutes(classes.last.cls.endTime) / 60;
    return lastEnd.clamp(6, 21).toDouble();
  }

  Future<void> _showSubjectSheet({
    TimetableSubject? subject,
    String? initialDay,
    double? initialStartHour,
  }) async {
    final isEditing = subject != null;

    final List<Map<String, String>> slots = subject?.classes
            .map((c) => {
                  'day': c.day,
                  'startTime': c.startTime,
                  'endTime': c.endTime,
                })
            .toList() ??
        [];

    final days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final types = ['CORE', 'LAB', 'BREAK'];
    bool isSaving = false;

    // Room and type are shared across every slot of a subject (a class
    // doesn't change room/type slot-to-slot in practice) rather than asked
    // for per-slot — seeded from the first existing class when editing.
    final roomController = TextEditingController(
      text: subject != null && subject.classes.isNotEmpty
          ? subject.classes.first.room
          : '',
    );
    String selectedType = subject != null && subject.classes.isNotEmpty
        ? subject.classes.first.type
        : types.first;

    // Inline day/time slot-builder state. Declared here (not inside the
    // StatefulBuilder's build callback) so it survives across rebuilds
    // triggered by setSheetState, same as `slots` below.
    final builderDays = <String>{initialDay ?? 'MON'};
    double builderStartHour = initialStartHour ?? 9;
    double builderEndHour = (builderStartHour + 1).clamp(6, 22).toDouble();

    // When editing a subject whose code isn't in the user's saved syllabus
    // subjects (e.g. a legacy free-text entry), keep it selectable by
    // synthesizing an entry rather than forcing a re-pick.
    SavedSubject? selectedSubject;
    if (isEditing) {
      final saved = AppStateNotifier.instance.savedSubjects ?? [];
      final match = saved.where((s) => s.subjectCode == subject.code);
      selectedSubject = match.isNotEmpty
          ? match.first
          : SavedSubject(subjectCode: subject.code, subjectName: subject.name);
    }

    Widget buildSheetContent(BuildContext ctx) {
      return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final rawSavedSubjects = AppStateNotifier.instance.savedSubjects ?? [];
            final hasAssignedSubjects = rawSavedSubjects.isNotEmpty &&
                !AppStateNotifier.instance.savedSubjectsFromCurriculum;
            final availableSubjects = <SavedSubject>[
              if (selectedSubject != null &&
                  !rawSavedSubjects
                      .any((s) => s.subjectCode == selectedSubject!.subjectCode))
                selectedSubject!,
              if (hasAssignedSubjects) ...rawSavedSubjects,
            ];
            final showSubjectCta = !hasAssignedSubjects && selectedSubject == null;

            // Recomputed on every rebuild (i.e. whenever a slot is added or
            // removed via setSheetState below), so the error clears itself
            // the moment the offending slot is deleted — no separate state
            // to keep in sync, and no network call since _subjects is
            // already loaded locally.
            final otherSubjects =
                _subjects.where((s) => !isEditing || s.id != subject.id);
            final conflictError = _findSlotConflict(slots, otherSubjects);

            String formatHour(double h) {
              final totalMinutes = (h * 60).round();
              final hh = totalMinutes ~/ 60;
              final mm = totalMinutes % 60;
              return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
            }

            void addSlotGroup() {
              if (builderDays.isEmpty) return;
              setSheetState(() {
                for (final day in days.where(builderDays.contains)) {
                  slots.add({
                    'day': day,
                    'startTime': formatHour(builderStartHour),
                    'endTime': formatHour(builderEndHour),
                  });
                }
              });
            }

            Future<void> saveSubject() async {
              if (selectedSubject == null) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Select a subject first.')),
                  );
                }
                return;
              }
              final name = selectedSubject!.subjectName;
              final code = selectedSubject!.subjectCode;
              final room = roomController.text.trim();

              setSheetState(() => isSaving = true);

              try {
                final existing = await _timetableService.getAllSubjects();

                final classes = slots.map((s) {
                  final start = s['startTime'] ?? '09:00';
                  return TimetableClass(
                    day: s['day'] ?? 'MON',
                    startTime: start,
                    endTime: s['endTime'] ?? start,
                    period: (int.tryParse(start.split(':').first) ?? 9) >= 12
                        ? 'PM'
                        : 'AM',
                    room: room,
                    type: selectedType,
                    duration: 1,
                  );
                }).toList();

                final newSubject = TimetableSubject(
                  id: isEditing
                      ? subject.id
                      : code.toLowerCase().replaceAll(' ', '_'),
                  name: name,
                  code: code,
                  classes: classes,
                );

                final List<TimetableSubject> merged;
                if (isEditing) {
                  merged = existing
                      .map((s) => s.id == subject.id ? newSubject : s)
                      .toList();
                } else {
                  merged = [...existing, newSubject];
                }
                await _timetableService.saveSubjects(merged);

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() => _subjects = merged);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEditing
                          ? 'Subject updated successfully!'
                          : 'Subject added successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  setSheetState(() => isSaving = false);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error saving subject: $e')),
                  );
                }
              }
            }

            Widget buildDaysAndTime() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Days and time',
                    style: TextStyle(
                        fontFamily: 'Public Sans',
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Select all days for this time slot.',
                    style: TextStyle(
                      fontFamily: 'Public Sans',
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: days.map((d) {
                      final isOn = builderDays.contains(d);
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setSheetState(() {
                            if (isOn) {
                              builderDays.remove(d);
                            } else {
                              builderDays.add(d);
                            }
                          }),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isOn ? Colors.black : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.black, width: 1.5),
                            ),
                            child: Text(
                              d.substring(0, 1),
                              style: TextStyle(
                                fontFamily: 'Public Sans',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isOn ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('Start  ',
                          style: TextStyle(
                              fontFamily: 'Public Sans', fontSize: 12)),
                      Text(
                        formatHour(builderStartHour),
                        style: const TextStyle(
                            fontFamily: 'Public Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Slider(
                    value: builderStartHour,
                    min: 6,
                    max: 22,
                    divisions: 64,
                    label: formatHour(builderStartHour),
                    onChanged: (v) => setSheetState(() {
                      builderStartHour = v;
                      if (builderEndHour < builderStartHour + 0.25) {
                        builderEndHour = (builderStartHour + 0.25).clamp(6, 22);
                      }
                    }),
                  ),
                  Row(
                    children: [
                      const Text('End  ',
                          style: TextStyle(
                              fontFamily: 'Public Sans', fontSize: 12)),
                      Text(
                        formatHour(builderEndHour),
                        style: const TextStyle(
                            fontFamily: 'Public Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Slider(
                    value: builderEndHour,
                    min: 6,
                    max: 22,
                    divisions: 64,
                    label: formatHour(builderEndHour),
                    onChanged: (v) => setSheetState(() {
                      builderEndHour = v;
                      if (builderStartHour > builderEndHour - 0.25) {
                        builderStartHour = (builderEndHour - 0.25).clamp(6, 22);
                      }
                    }),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: builderDays.isEmpty ? null : addSlotGroup,
                      icon: const Icon(Icons.add),
                      label: const Text('Add this time slot'),
                    ),
                  ),
                ],
              );
            }

            Widget buildSlotList() {
              if (slots.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No class slots added yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              // Slots sharing the same time (added together across
              // multiple days) collapse into one row, e.g.
              // "MON/WED/FRI 09:00-10:00", instead of a row per day.
              final grouped = <String, List<int>>{};
              for (var i = 0; i < slots.length; i++) {
                final s = slots[i];
                final key = '${s['startTime']}|${s['endTime']}';
                grouped.putIfAbsent(key, () => []).add(i);
              }
              return Column(
                children: grouped.values.map((indices) {
                  final first = slots[indices.first];
                  final dayLabels = indices.map((i) => slots[i]['day']!).toList()
                    ..sort((a, b) => days.indexOf(a).compareTo(days.indexOf(b)));
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${dayLabels.join('/')} ${first['startTime']}–${first['endTime']}',
                      style: const TextStyle(
                          fontFamily: 'Public Sans', fontWeight: FontWeight.w600),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setSheetState(() {
                        for (final i in indices.toList()
                          ..sort((a, b) => b.compareTo(a))) {
                          slots.removeAt(i);
                        }
                      }),
                    ),
                  );
                }).toList(),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEditing ? 'Edit Subject' : 'Add Subject',
                      style: const TextStyle(
                        fontFamily: 'Lexend Mega',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (showSubjectCta)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8B0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No subjects assigned yet',
                              style: TextStyle(
                                  fontFamily: 'Public Sans',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Confirm your actual subjects for this semester before building a timetable.',
                              style: TextStyle(
                                  fontFamily: 'Public Sans',
                                  fontSize: 12,
                                  color: Colors.black87),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await Navigator.push(
                                    ctx,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SyllabusSelectionScreen(),
                                    ),
                                  );
                                  setSheetState(() {});
                                },
                                icon: const Icon(Icons.checklist),
                                label: const Text('Configure subjects'),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      SearchableDropdown<SavedSubject>(
                        items: availableSubjects,
                        value: selectedSubject,
                        labelBuilder: (s) =>
                            '${s.subjectCode} — ${s.subjectName}',
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (s) =>
                            setSheetState(() => selectedSubject = s),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: roomController,
                      decoration: const InputDecoration(
                        labelText: 'Room (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Type — applies to every slot below',
                      style: TextStyle(
                          fontFamily: 'Public Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: types.map((t) {
                        final isOn = selectedType == t;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setSheetState(() => selectedType = t),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isOn ? Colors.black : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.black, width: 1.5),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontFamily: 'Public Sans',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: isOn ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Colors.black26),
                    const SizedBox(height: 12),
                    buildDaysAndTime(),
                    const SizedBox(height: 16),
                    const Text(
                      'Class Slots',
                      style: TextStyle(
                        fontFamily: 'Public Sans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    buildSlotList(),
                    if (conflictError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD9D9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red, width: 1),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                conflictError,
                                style: const TextStyle(
                                  fontFamily: 'Public Sans',
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (isSaving || conflictError != null)
                            ? null
                            : saveSubject,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD966),
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.black, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : Text(
                                isEditing ? 'Update Subject' : 'Save Subject',
                                style: const TextStyle(
                                  fontFamily: 'Public Sans',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }

    final width = MediaQuery.of(context).size.width;
    if (Breakpoints.isAtLeastDesktop(width)) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFFFFF8E4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          child: ConstrainedBox(
            // Merging subject picker + room/type + day-and-time builder into
            // one sheet made this noticeably taller than the old form, so
            // give it more of the viewport (still scrolls if it doesn't fit).
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: buildSheetContent(ctx),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFFFFF8E4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: Colors.black, width: 2),
        ),
        builder: buildSheetContent,
      );
    }
  }

  Future<void> _removeSubject(TimetableSubject subject) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8E4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: const Text(
          'Remove Subject',
          style: TextStyle(fontFamily: 'Lexend Mega', fontSize: 16),
        ),
        content: Text('Remove "${subject.name}" from your timetable?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final existing = await _timetableService.getAllSubjects();
      final updated = existing.where((s) => s.id != subject.id).toList();
      await _timetableService.saveSubjects(updated);
      setState(() => _subjects = updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Subject removed.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing subject: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEEEC3),
      body: SafeArea(
        bottom: false,
        child: ResponsiveLayout(
          mobile: (_) => _mobileBody(context),
          desktop: (_) => _desktopBody(context),
        ),
      ),
    );
  }

  void _openAddSheet({TimetableSubject? subject}) {
    final day = _selectedDay;
    _showSubjectSheet(
      subject: subject,
      initialDay: day,
      initialStartHour: _nextAvailableStartHour(day),
    );
  }

  Widget _mobileBody(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dayItems = _classesForDay(_selectedDay);
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.045,
                vertical: 20,
              ),
              child: _buildHeader(screenWidth),
            ),
            if (!_isLoading && _subjects.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.045),
                child: _buildDaySelector(),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _subjects.isEmpty
                      ? _buildEmptyState()
                      : dayItems.isEmpty
                          ? _buildEmptyDayState()
                          : ListView.builder(
                              padding: EdgeInsets.symmetric(
                                horizontal: screenWidth * 0.045,
                              ).copyWith(
                                bottom:
                                    100 + MediaQuery.of(context).padding.bottom,
                              ),
                              itemCount: dayItems.length,
                              itemBuilder: (context, index) =>
                                  _buildDayClassCard(dayItems[index]),
                            ),
            ),
          ],
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: _buildAddButton(),
        ),
      ],
    );
  }

  Widget _desktopBody(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final dayItems = _classesForDay(_selectedDay);

    return Padding(
      padding: EdgeInsets.all(AppSpacing.pagePadding(width)),
      child: MaxWidthContent(
        maxWidth: 800,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _buildHeader(width)),
                ElevatedButton.icon(
                  onPressed: () => _openAddSheet(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Subject'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD966),
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black, width: 2),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.lg),
            if (_subjects.isEmpty)
              Expanded(child: _buildEmptyState())
            else ...[
              _buildDaySelector(),
              SizedBox(height: AppSpacing.lg),
              Expanded(
                child: dayItems.isEmpty
                    ? _buildEmptyDayState()
                    : ListView.separated(
                        itemCount: dayItems.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _buildDayClassCard(dayItems[index]),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    final visible = _visibleDays();
    final selected = _selectedDay;
    return Row(
      children: visible.map((d) {
        final isOn = d == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _userSelectedDay = d),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isOn ? const Color(0xFFFFD966) : Colors.white,
                border: Border.all(
                    color: Colors.black, width: isOn ? 2 : 1.5),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    offset: const Offset(2, 2),
                    color: Colors.black.withValues(alpha: isOn ? 1 : 0.3),
                  ),
                ],
              ),
              child: Text(
                d,
                style: const TextStyle(
                  fontFamily: 'Public Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDayClassCard(
      ({TimetableSubject subject, TimetableClass cls}) item) {
    final isBreak = item.cls.type == 'BREAK';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isBreak ? const Color(0xFFD2FFB6) : const Color(0xFFFFF8E4),
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(offset: Offset(3, 3), color: Colors.black),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openAddSheet(subject: item.subject),
            child: SizedBox(
              width: 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.cls.startTime,
                    style: const TextStyle(
                      fontFamily: 'Public Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.cls.endTime,
                    style: TextStyle(
                      fontFamily: 'Public Sans',
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () => _openAddSheet(subject: item.subject),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.subject.name,
                    style: const TextStyle(
                      fontFamily: 'Public Sans',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (item.cls.room.isNotEmpty) ...[
                        const Icon(Icons.location_on,
                            size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          item.cls.room,
                          style: const TextStyle(
                              fontFamily: 'Public Sans', fontSize: 13),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.cls.type,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              GestureDetector(
                onTap: () => _openAddSheet(subject: item.subject),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _removeSubject(item.subject),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDayState() {
    return Center(
      child: Text(
        'No classes on $_selectedDay',
        style: TextStyle(
          fontFamily: 'Public Sans',
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildHeader(double screenWidth) {
    return const Row(
      children: [
        Icon(Icons.calendar_today, size: 24, color: Colors.black),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Time Table',
            style: TextStyle(
              fontFamily: 'Lexend Mega',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: Colors.black,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_month,
            size: 80,
            color: Colors.black.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No timetables yet',
            style: TextStyle(
              fontFamily: 'Public Sans',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add a subject',
            style: TextStyle(
              fontFamily: 'Public Sans',
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFFFD966),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(
            offset: Offset(4, 4),
            color: Colors.black,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openAddSheet(),
          customBorder: const CircleBorder(),
          child: const Icon(
            Icons.add,
            size: 28,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
