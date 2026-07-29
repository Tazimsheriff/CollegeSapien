import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codesapiens/screens/timetable_list_screen.dart';
import 'package:codesapiens/screens/timetable_detail_screen.dart';
import 'package:codesapiens/screens/syllabus/syllabus_selection_screen.dart';
import 'package:codesapiens/models/timetable_models.dart';

void runTimetableTests() {
  group('Timetable & Syllabus Flow', () {
    testWidgets('Verify Timetable List Screen Tabs & Dialogs', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: TimetableListScreen()));
      await tester.pumpAndSettle();

      // Verify page title
      expect(find.text('Timetable'), findsOneWidget);

      // Verify day selector tabs
      expect(find.text('MON'), findsOneWidget);
      expect(find.text('TUE'), findsOneWidget);
      expect(find.text('WED'), findsOneWidget);

      // Tap on a day tab (e.g., TUE)
      await tester.tap(find.text('TUE'));
      await tester.pumpAndSettle();

      // TODO: the photo-import chooser dialog (Take Photo / Choose from
      // Gallery / Enter Manually) this block asserts on doesn't exist in
      // the current screen — commented out until it's rebuilt or this test
      // is rewritten for the actual add-subject flow (SearchableDropdown +
      // multi-day slot builder) in timetable_list_screen.dart.
      // final addIcon = find.byIcon(Icons.add);
      // if (addIcon.evaluate().isNotEmpty) {
      //   await tester.tap(addIcon);
      //   await tester.pumpAndSettle();
      //
      //   // Verify the Add Timetable dialog opens
      //   expect(find.text('Add Timetable'), findsOneWidget);
      //   expect(find.text('Take Photo'), findsOneWidget);
      //   expect(find.text('Choose from Gallery'), findsOneWidget);
      //   expect(find.text('Enter Manually'), findsOneWidget);
      //
      //   // Tap "Enter Manually"
      //   await tester.tap(find.text('Enter Manually'));
      //   await tester.pumpAndSettle();
      //
      //   // Verify the manual entry sheet is displayed
      //   expect(find.widgetWithText(TextFormField, 'Subject Name'), findsOneWidget);
      //   expect(find.widgetWithText(TextFormField, 'Subject Code'), findsOneWidget);
      // }
    });

    testWidgets('Verify Timetable Detail Screen Timeline', (WidgetTester tester) async {
      // Create mock TimetableSubject
      final mockSubject = TimetableSubject(
        id: '1',
        code: 'CS301',
        name: 'Software Engineering',
        classes: [
          TimetableClass(
            day: 'MON',
            startTime: '09:00',
            endTime: '10:00',
            period: 'AM',
            room: 'Room 302',
            type: 'Lecture',
            duration: 1,
          )
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: TimetableDetailScreen(subject: mockSubject),
      ));
      await tester.pumpAndSettle();

      // Verify subject detail elements
      expect(find.text('Time Table'), findsOneWidget);
      expect(find.text('MON'), findsOneWidget);
      
      // Tap on the back button
      final backButton = find.byIcon(Icons.arrow_back);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
    });

    testWidgets('Verify Syllabus Selection Screen Form', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SyllabusSelectionScreen()));
      await tester.pumpAndSettle();

      // Verify title or key text
      expect(find.text('Syllabus'), findsOneWidget);
      expect(find.text('Select your syllabus to get started'), findsOneWidget);

      // Verify save button exists
      expect(find.text('Save & Continue'), findsOneWidget);
    });
  });
}
