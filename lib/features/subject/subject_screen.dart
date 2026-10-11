import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/string_extension.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
import '../tutorial/tutorial_controller.dart';
import 'add_subject_screen.dart';
import 'edit_subject_screen.dart';
import 'subject_provider.dart';
import 'subject_model.dart';
import '../settings/setup_guide_screen.dart';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  String _searchQuery = '';
  final Set<String> _collapsedSubjectIds = <String>{};
  final Set<String> _knownSubjectIds = <String>{};

  void _syncCollapsedState(List<Subject> subjects) {
    final currentIds = subjects.map((subject) => subject.id).toSet();

    for (final subject in subjects) {
      if (_knownSubjectIds.add(subject.id)) {
        _collapsedSubjectIds.add(subject.id);
      }
    }

    _knownSubjectIds.removeWhere((id) => !currentIds.contains(id));
    _collapsedSubjectIds.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final allSubjects = subjectProvider.subjects;
    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    _syncCollapsedState(allSubjects);

    // Sort subjects alphabetically
    final subjects = List<Subject>.from(allSubjects)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final filteredSubjects = subjects.where((s) {
      final nameMatches = s.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final acronymMatches = (s.acronym ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
      return nameMatches || acronymMatches;
    }).toList();

    if (subjects.isEmpty) {
      return _buildNoSubjectsState(context, rs, semesterEnded, semesterProvider);
    }

    return Column(
      children: [
        if (semesterEnded)
          Container(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 10),
            color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                  size: rs.scale(16),
                ),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: Text(
                    'Semester has ended. Viewing archived subjects.',
                    style: GoogleFonts.inter(
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      fontSize: rs.font(12),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),



        // Monotone Minimal Search Input (Pill Capsule)
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: rs.width(14),
            vertical: rs.height(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rs.scale(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.white.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(rs.scale(28)),
                  border: Border.all(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08),
                    width: 0.9,
                  ),
                ),
                child: TextField(
                  style: GoogleFonts.inter(
                    fontSize: rs.font(13.5),
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search subjects or codes...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: rs.font(13),
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: rs.scale(18),
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: rs.scale(16),
                              color: isDarkMode ? Colors.white54 : Colors.black54,
                            ),
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: rs.width(16),
                      vertical: rs.height(12),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
            ),
          ),
        ),

        // List of Subjects
        Expanded(
          child: filteredSubjects.isEmpty
              ? Center(
                  child: Text(
                    'No subjects found',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(14),
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(
                    left: rs.width(14),
                    right: rs.width(14),
                    top: rs.height(6),
                    bottom: rs.height(100),
                  ),
                  itemCount: filteredSubjects.length,
                  itemBuilder: (context, index) {
                    final subject = filteredSubjects[index];
                    final sortedSchedule = _sortedSchedule(subject.activeSchedule);
                    final isExpanded = !_collapsedSubjectIds.contains(subject.id);

                    // Compute subject-level attendance percentage
                    final subjectRecords = attendanceProvider.attendanceRecords
                        .where((r) => r.subjectId == subject.id)
                        .toList();
                    final validRecords = subjectRecords
                        .where((r) => r.status != AttendanceStatus.cancelled)
                        .toList();
                    final attendedCount = validRecords
                        .where((r) => r.status == AttendanceStatus.attended)
                        .length;
                    final totalMarked = validRecords.length;
                    final double? attendancePct =
                        totalMarked > 0 ? (attendedCount / totalMarked) * 100 : null;

                    return _SubjectCardItem(
                      key: ValueKey(subject.id),
                      subject: subject,
                      sortedSchedule: sortedSchedule,
                      isExpanded: isExpanded,
                      attendancePct: attendancePct,
                      attendedCount: attendedCount,
                      totalMarked: totalMarked,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          if (expanded) {
                            _collapsedSubjectIds.remove(subject.id);
                          } else {
                            _collapsedSubjectIds.add(subject.id);
                          }
                        });
                      },
                      semesterEnded: semesterEnded,
                      onEdit: () {
                        FocusScope.of(context).unfocus();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditSubjectScreen(subject: subject),
                          ),
                        );
                      },
                      onDelete: () => _showDeleteConfirmation(context, subjectProvider, subject),
                      timeFormatProvider: timeFormatProvider,
                    );
                  },
                ),
        ),
      ],
    );
  }



  List<TimeSlot> _sortedSchedule(List<TimeSlot> schedule) {
    final sortedSchedule = List<TimeSlot>.from(schedule);
    sortedSchedule.sort((a, b) {
      final dayCompare = a.day.index.compareTo(b.day.index);
      if (dayCompare != 0) return dayCompare;
      return _timeToDouble(a).compareTo(_timeToDouble(b));
    });
    return sortedSchedule;
  }

  double _timeToDouble(TimeSlot slot) {
    return slot.startTime.hour + (slot.startTime.minute / 60.0);
  }

  void _showDeleteConfirmation(BuildContext context, SubjectProvider provider, Subject subject) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF141416) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
              width: 0.8,
            ),
          ),
          title: Text(
            'Delete Subject',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          content: Text(
            'Are you sure you want to delete "${subject.name}"? This action cannot be undone.',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: isDarkMode ? Colors.white70 : Colors.black87,
              height: 1.4,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? Colors.white : Colors.black,
                foregroundColor: isDarkMode ? Colors.black : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Delete',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              onPressed: () {
                HapticFeedback.vibrate();
                provider.deleteSubject(subject);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showReplacingSnackBar(
                  SnackBar(content: Text('Subject "${subject.name}" deleted')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoSubjectsState(
    BuildContext context,
    ResponsiveScale rs,
    bool semesterEnded,
    SemesterProvider semesterProvider,
  ) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: rs.width(16),
        vertical: rs.height(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEmptySubjectHeroCard(context, rs, semesterEnded),
          SizedBox(height: rs.height(14)),
          _buildCompactAISuggestionCard(context, rs),
        ],
      ),
    );
  }

  Widget _buildEmptySubjectHeroCard(
    BuildContext context,
    ResponsiveScale rs,
    bool semesterEnded,
  ) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(rs.scale(24)),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF131316) : Colors.white,
        borderRadius: BorderRadius.circular(rs.scale(20)),
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: rs.scale(54),
            height: rs.scale(54),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.school_outlined,
                size: rs.scale(26),
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          SizedBox(height: rs.height(16)),
          Text(
            'NO SUBJECTS ADDED',
            style: GoogleFonts.inter(
              fontSize: rs.font(15),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: rs.height(8)),
          Text(
            semesterEnded
                ? 'This semester has ended, but you can still add subjects to record historical data.'
                : 'Build your weekly schedule to enable smart attendance tracking.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: rs.font(12.5),
              color: isDarkMode ? Colors.white54 : Colors.black54,
              height: 1.4,
            ),
          ),
          SizedBox(height: rs.height(20)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDarkMode ? Colors.white : Colors.black,
                foregroundColor: isDarkMode ? Colors.black : Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(vertical: rs.height(12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(rs.scale(16)),
                ),
              ),
              icon: Icon(Icons.add_rounded, size: rs.scale(18)),
              label: Text(
                'Add Your First Subject',
                style: GoogleFonts.inter(
                  fontSize: rs.font(13.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: semesterEnded
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      final tutorialController = Provider.of<TutorialController>(context, listen: false);
                      if (tutorialController.isActive && tutorialController.currentStepIndex == 4) {
                        tutorialController.nextStep();
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddSubjectScreen(),
                        ),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAISuggestionCard(BuildContext context, ResponsiveScale rs) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(rs.scale(16)),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF131316) : Colors.white,
        borderRadius: BorderRadius.circular(rs.scale(18)),
        border: Border.all(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: rs.width(7), vertical: rs.height(2.5)),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(rs.scale(6)),
                ),
                child: Text(
                  'TIP',
                  style: GoogleFonts.inter(
                    fontSize: rs.font(9.5),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              SizedBox(width: rs.width(8)),
              Text(
                'Fast Setup with AI',
                style: GoogleFonts.inter(
                  fontSize: rs.font(13),
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(8)),
          Text(
            'Import your schedule in seconds. Take a screenshot of your timetable, copy our prompt, and let Gemini or ChatGPT set up your subjects.',
            style: GoogleFonts.inter(
              fontSize: rs.font(12),
              color: isDarkMode ? Colors.white54 : Colors.black54,
              height: 1.35,
            ),
          ),
          SizedBox(height: rs.height(10)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: rs.width(8), vertical: rs.height(4)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Text(
                'Learn How to Import',
                style: GoogleFonts.inter(
                  fontSize: rs.font(11.5),
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              label: Icon(
                Icons.arrow_forward_rounded,
                size: rs.scale(13),
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SetupGuideScreen(initialPage: 3),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- Tesla x Nothing Monotone Subject Card Item ---
class _SubjectCardItem extends StatefulWidget {
  final Subject subject;
  final List<TimeSlot> sortedSchedule;
  final bool isExpanded;
  final double? attendancePct;
  final int attendedCount;
  final int totalMarked;
  final ValueChanged<bool> onExpansionChanged;
  final bool semesterEnded;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final TimeFormatProvider timeFormatProvider;

  const _SubjectCardItem({
    super.key,
    required this.subject,
    required this.sortedSchedule,
    required this.isExpanded,
    required this.attendancePct,
    required this.attendedCount,
    required this.totalMarked,
    required this.onExpansionChanged,
    required this.semesterEnded,
    required this.onEdit,
    required this.onDelete,
    required this.timeFormatProvider,
  });

  @override
  State<_SubjectCardItem> createState() => _SubjectCardItemState();
}

class _SubjectCardItemState extends State<_SubjectCardItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconTurns;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _iconTurns = _controller.drive(
      Tween<double>(begin: 0.0, end: 0.5).chain(
        CurveTween(curve: Curves.easeInOut),
      ),
    );
    _heightFactor = _controller.drive(
      CurveTween(curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _SubjectCardItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    final newExpanded = !widget.isExpanded;
    if (newExpanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onExpansionChanged(newExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final subject = widget.subject;
    final sortedSchedule = widget.sortedSchedule;
    final attendancePct = widget.attendancePct;
    final targetAttendance = subject.targetAttendance;
    final bool hasAttendanceData = attendancePct != null;
    final bool isOnTrack = hasAttendanceData && attendancePct >= targetAttendance;


    return Padding(
      padding: EdgeInsets.only(bottom: rs.height(8)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rs.scale(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(rs.scale(16)),
              border: Border.all(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          // Tappable Header Row
          InkWell(
            borderRadius: BorderRadius.circular(rs.scale(16)),
            onTap: _handleTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: rs.width(13),
                vertical: rs.height(11),
              ),
              child: Row(
                children: [
                  // Encircled Subject PFP Node
                  Container(
                    width: rs.scale(34),
                    height: rs.scale(34),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? subject.color.withValues(alpha: 0.16)
                          : subject.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: subject.color,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(rs.scale(3)),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            subject.displayAcronym,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: GoogleFonts.inter(
                              color: isDarkMode ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w700,
                              fontSize: rs.font(11),
                              letterSpacing: 0.4,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rs.width(10)),
                  // Title and Subtitle Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: rs.font(14.5),
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: rs.height(2)),
                        Row(
                          children: [
                            Text(
                              'Target $targetAttendance%',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                color: isDarkMode ? Colors.white54 : Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '  |  ${sortedSchedule.length} slots/wk',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                color: isDarkMode ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions: Edit, Delete, Expand
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      size: rs.scale(16),
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                    ),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.semesterEnded ? null : widget.onEdit,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: rs.scale(16),
                      color: isDarkMode ? Colors.white38 : Colors.black38,
                    ),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.semesterEnded ? null : widget.onDelete,
                  ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: rs.scale(18),
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Mini Attendance Health Bar (Tesla Charge Style Meter)
          if (hasAttendanceData)
            Padding(
              padding: EdgeInsets.only(
                left: rs.width(13),
                right: rs.width(13),
                bottom: rs.height(10),
              ),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: rs.width(10), vertical: rs.height(6)),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(rs.scale(10)),
                  border: Border.all(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '${attendancePct.toStringAsFixed(1)}%',
                      style: GoogleFonts.inter(
                        fontSize: rs.font(12.5),
                        fontWeight: FontWeight.w700,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    SizedBox(width: rs.width(8)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 4,
                          color: isDarkMode ? Colors.white12 : Colors.black12,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (attendancePct / 100).clamp(0.0, 1.0),
                            child: Container(
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: rs.width(8)),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: rs.width(6), vertical: rs.height(1.5)),
                      decoration: BoxDecoration(
                        color: isOnTrack
                            ? (isDarkMode ? Colors.white : Colors.black)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(rs.scale(6)),
                        border: !isOnTrack
                            ? Border.all(
                                color: isDarkMode ? Colors.white38 : Colors.black38,
                                width: 0.8,
                              )
                            : null,
                      ),
                      child: Text(
                        isOnTrack ? 'ON TRACK' : 'OFF TRACK',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(8.5),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: isOnTrack
                              ? (isDarkMode ? Colors.black : Colors.white)
                              : (isDarkMode ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Collapsible Schedule Slots Details
          ClipRect(
            child: AnimatedBuilder(
              animation: _controller.view,
              builder: (context, child) {
                return Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _heightFactor.value,
                  child: child,
                );
              },
              child: Padding(
                padding: EdgeInsets.only(
                  left: rs.width(13),
                  right: rs.width(13),
                  bottom: rs.height(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      height: 1,
                      thickness: 0.8,
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    ),
                    SizedBox(height: rs.height(8)),
                    if (sortedSchedule.isNotEmpty)
                      Wrap(
                        spacing: rs.width(6),
                        runSpacing: rs.height(5),
                        children: sortedSchedule.map((timeSlot) {
                          final dayLabel = timeSlot.specificDate == null
                              ? timeSlot.day.name.capitalize().substring(0, 3).toUpperCase()
                              : '${timeSlot.day.name.capitalize().substring(0, 3).toUpperCase()} ${timeSlot.specificDate!.day}/${timeSlot.specificDate!.month}';
                          final room = subject.getEffectiveRoom(timeSlot);
                          final block = subject.getEffectiveBlock(timeSlot);
                          final roomText = room != null
                              ? '  |  $room${block != null && block.isNotEmpty ? " ($block)" : ""}'
                              : '';
                          return Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: rs.width(8),
                              vertical: rs.height(4),
                            ),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(rs.scale(8)),
                              border: Border.all(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '$dayLabel ${timeSlot.formatTimeRange(widget.timeFormatProvider.timeFormat)}$roomText',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(10.5),
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: rs.height(2)),
                        child: Text(
                          'No schedule configured for this subject.',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(11),
                            color: isDarkMode ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
          ),
        ),
      ),
    ),
  );
}
}
