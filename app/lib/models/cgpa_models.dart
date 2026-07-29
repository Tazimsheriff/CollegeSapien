class CgpaSemesterEntry {
  int semester;
  double gpa;
  int credits;

  CgpaSemesterEntry({
    required this.semester,
    required this.gpa,
    required this.credits,
  });

  factory CgpaSemesterEntry.fromJson(Map<String, dynamic> json) {
    return CgpaSemesterEntry(
      semester: (json['semester'] as num).toInt(),
      gpa: (json['gpa'] as num).toDouble(),
      credits: (json['credits'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'semester': semester,
        'gpa': gpa,
        'credits': credits,
      };

  CgpaSemesterEntry copy() =>
      CgpaSemesterEntry(semester: semester, gpa: gpa, credits: credits);
}
