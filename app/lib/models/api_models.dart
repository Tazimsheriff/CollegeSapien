import 'timetable_models.dart';
import 'syllabus_models.dart';

class College {
  final String id;
  final String name;
  final String code;

  College({
    required this.id,
    required this.name,
    required this.code,
  });

  factory College.fromJson(Map<String, dynamic> json) {
    return College(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
      };
}

class UserProfile {
  final String uid;
  final String email;
  final String name;
  final String? collegeId;
  final String? collegeName;
  final String? department;
  final int semester;
  final bool isVerified;
  final String role;

  UserProfile({
    required this.uid,
    required this.email,
    required this.name,
    this.collegeId,
    this.collegeName,
    this.department,
    required this.semester,
    required this.isVerified,
    required this.role,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      collegeId: json['collegeId'] as String?,
      collegeName: json['collegeName'] as String?,
      department: json['department'] as String?,
      semester: json['semester'] as int? ?? 1,
      isVerified: json['isVerified'] as bool? ?? false,
      role: json['role'] as String? ?? 'user',
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'name': name,
        'collegeId': collegeId,
        'collegeName': collegeName,
        'department': department,
        'semester': semester,
        'isVerified': isVerified,
        'role': role,
      };
}

class AuthSyncResult {
  final bool onboardingRequired;
  final UserProfile? user;
  final bool emailVerified;
  final List<AttendanceSummary>? attendanceSummary;
  final List<TimetableSubject>? timetableSubjects;
  final SavedSyllabus? savedSubjects;

  AuthSyncResult({
    required this.onboardingRequired,
    required this.user,
    required this.emailVerified,
    this.attendanceSummary,
    this.timetableSubjects,
    this.savedSubjects,
  });

  factory AuthSyncResult.fromJson(Map<String, dynamic> json) {
    final auth = json['auth'] as Map<String, dynamic>? ?? {};
    final userJson = json['user'] as Map<String, dynamic>?;
    final attendanceJson = json['attendanceSummary'] as List<dynamic>?;
    final timetableJson = json['timetable'] as Map<String, dynamic>?;
    final timetableSubjectsJson = timetableJson?['subjects'] as List<dynamic>?;
    return AuthSyncResult(
      onboardingRequired:
          json['onboardingRequired'] as bool? ?? userJson == null,
      user: userJson == null ? null : UserProfile.fromJson(userJson),
      emailVerified: auth['emailVerified'] as bool? ??
          userJson?['isVerified'] as bool? ??
          false,
      attendanceSummary: attendanceJson
          ?.map((e) => AttendanceSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      timetableSubjects: timetableSubjectsJson
          ?.map((e) => TimetableSubject.fromJson(e as Map<String, dynamic>))
          .toList(),
      savedSubjects: SavedSyllabus.fromJsonOrNull(
          json['savedSubjects'] as Map<String, dynamic>?),
    );
  }
}

class AttendanceSummary {
  final String subjectId;
  final String subjectName;
  final String subjectCode;
  final int attended;
  final int absent;
  final int total;
  final double percentage;
  final int safeToSkip;
  final int requiredToReachThreshold;

  AttendanceSummary({
    required this.subjectId,
    required this.subjectName,
    required this.subjectCode,
    required this.attended,
    required this.absent,
    required this.total,
    required this.percentage,
    required this.safeToSkip,
    required this.requiredToReachThreshold,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      subjectId: json['subjectId'] as String? ?? '',
      subjectName: json['subjectName'] as String? ?? '',
      subjectCode: json['subjectCode'] as String? ?? '',
      attended: json['attended'] as int? ?? 0,
      absent: json['absent'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      percentage: (json['percentage'] as num? ?? 0).toDouble(),
      safeToSkip: json['safeToSkip'] as int? ?? 0,
      requiredToReachThreshold: json['requiredToReachThreshold'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'subjectName': subjectName,
        'subjectCode': subjectCode,
        'attended': attended,
        'absent': absent,
        'total': total,
        'percentage': percentage,
        'safeToSkip': safeToSkip,
        'requiredToReachThreshold': requiredToReachThreshold,
      };
}

class HubResource {
  final String id;
  final String name;
  final String category;
  final String? department;
  final String? uploadedBy;
  final String? status;
  final String? fileUrl;
  final String? storagePath;
  final String uploaderName;
  final String? subjectId;
  final String? subjectName;
  final String? regulation;
  final List<String> keywords;

  HubResource({
    required this.id,
    required this.name,
    required this.category,
    this.department,
    this.uploadedBy,
    this.status,
    this.fileUrl,
    this.storagePath,
    required this.uploaderName,
    this.subjectId,
    this.subjectName,
    this.regulation,
    this.keywords = const [],
  });

  factory HubResource.fromJson(Map<String, dynamic> json) {
    return HubResource(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      department: json['department'] as String?,
      uploadedBy: json['uploadedBy'] as String?,
      status: json['status'] as String?,
      fileUrl: json['fileUrl'] as String? ?? json['link'] as String?,
      storagePath: json['storagePath'] as String?,
      uploaderName: json['uploaderName'] as String? ??
          json['uploadedBy'] as String? ??
          'Student',
      subjectId: json['subjectId'] as String?,
      subjectName: json['subjectName'] as String?,
      regulation: json['regulation'] as String?,
      keywords: (json['keywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'department': department,
        'uploadedBy': uploadedBy,
        'status': status,
        'fileUrl': fileUrl,
        'storagePath': storagePath,
        'uploaderName': uploaderName,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'regulation': regulation,
        'keywords': keywords,
      };
}

class AdminReport {
  final String id;
  final String resourceId;
  final String reason;
  final String type;
  final String reportedBy;
  final String? collegeId;
  final String status;

  AdminReport({
    required this.id,
    required this.resourceId,
    required this.reason,
    required this.type,
    required this.reportedBy,
    required this.status,
    this.collegeId,
  });

  factory AdminReport.fromJson(Map<String, dynamic> json) {
    return AdminReport(
      id: json['id'] as String? ?? '',
      resourceId: json['resourceId'] as String? ?? '',
      reason: json['reason'] as String? ?? 'No reason provided',
      type: json['type'] as String? ?? 'unknown',
      reportedBy: json['reportedBy'] as String? ?? '',
      collegeId: json['collegeId'] as String?,
      status: json['status'] as String? ?? 'pending',
    );
  }
}

class AdminUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? collegeId;

  AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.collegeId,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String? ?? json['uid'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed user',
      email: json['email'] as String? ?? '',
      role: (json['role'] as String? ?? 'user').toLowerCase(),
      collegeId: json['collegeId'] as String?,
    );
  }

  AdminUser copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? collegeId,
  }) {
    return AdminUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      collegeId: collegeId ?? this.collegeId,
    );
  }
}
