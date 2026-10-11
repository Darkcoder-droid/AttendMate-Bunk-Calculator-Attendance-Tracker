import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/responsive_scale.dart';
import '../semester/semester_model.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
import '../settings/swipe_action_provider.dart';
import '../settings/swipeable_card.dart';
import '../subject/subject_provider.dart';
import '../subject/subject_model.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../calendar/calendar_utils.dart';
import '../location/location_model.dart';
import '../../services/database_service.dart';

typedef DayChangedCallback = void Function(String title, bool canGoPrevious, bool canGoNext);

class TodaySchedule extends StatefulWidget {
  final ValueChanged<String>? onTitleChanged;
  final DayChangedCallback? onDayChanged;

  const TodaySchedule({super.key, this.onTitleChanged, this.onDayChanged});

  @override
  State<TodaySchedule> createState() => TodayScheduleState();
}

class TodayScheduleState extends State<TodaySchedule> {
  late DateTime _today;
  List<DateTime> _dates = [];
  int _currentIndex = 0;
  int _todayIndex = 0;
  late PageController _pageController;
  Map<String, LocationConfig> _locationById = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);

    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    _buildDatesList(semesterProvider.semester);

    _pageController = PageController(initialPage: _todayIndex);
    _currentIndex = _todayIndex;

    _loadLocations();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notifyDayChanged();
      }
    });
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await DatabaseService().loadLocations();
      if (mounted) {
        setState(() {
          _locationById = {for (final l in locs) l.id: l};
        });
      }
    } catch (_) {
      // Location display is non-critical — silently ignore
    }
  }

  @override
  void didUpdateWidget(covariant TodaySchedule oldWidget) {
    super.didUpdateWidget(oldWidget);
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    _buildDatesList(semesterProvider.semester);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _buildDatesList(Semester? semester) {
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);

    // Current week: Monday to Sunday
    final monday = _today.subtract(Duration(days: _today.weekday - 1));
    final list = <DateTime>[];
    for (int i = 0; i < 7; i++) {
      list.add(monday.add(Duration(days: i)));
    }

    _dates = list;
    final foundToday = _dates.indexWhere((d) => CalendarUtils.isSameDay(d, _today));
    _todayIndex = foundToday >= 0 ? foundToday : 0;
    if (_currentIndex >= _dates.length) {
      _currentIndex = _todayIndex;
    }
  }

  String _getScheduleTitle(DateTime date) {
    final dNorm = DateTime(date.year, date.month, date.day);
    final tNorm = DateTime(_today.year, _today.month, _today.day);
    final dayDiff = dNorm.difference(tNorm).inDays;

    if (dayDiff == 0) {
      return "Today";
    } else if (dayDiff == -1) {
      return "Yesterday";
    } else if (dayDiff == 1) {
      return "Tomorrow";
    } else {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final weekday = weekdays[date.weekday - 1];
      final month = months[date.month - 1];
      return '$weekday, ${date.day} $month';
    }
  }

  void _notifyDayChanged() {
    if (_dates.isNotEmpty && _currentIndex < _dates.length) {
      final title = _getScheduleTitle(_dates[_currentIndex]);
      widget.onTitleChanged?.call(title);
      widget.onDayChanged?.call(title, canGoPrevious, canGoNext);
    }
  }


  bool get canGoPrevious => _currentIndex > 0;
  bool get canGoNext => _currentIndex < _dates.length - 1;

  void goToPreviousDay() {
    if (canGoPrevious && _pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void goToNextDay() {
    if (canGoNext && _pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void jumpToToday() {
    if (_pageController.hasClients && _currentIndex != _todayIndex) {
      _pageController.animateToPage(
        _todayIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  List<Subject> _expandSubjectsBySlot(List<Subject> subjects) {
    final expandedSubjects = <Subject>[];
    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        expandedSubjects.add(subject.copyWith(schedule: [slot]));
      }
    }
    return expandedSubjects;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required VoidCallback onConfirm,
    String? successMessage,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF141416) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Text(
          content,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDarkMode ? Colors.white70 : Colors.black87,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: isDarkMode ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode ? Colors.white : Colors.black,
              foregroundColor: isDarkMode ? Colors.black : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () {
              HapticFeedback.vibrate();
              onConfirm();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showReplacingSnackBar(
                SnackBar(content: Text(successMessage ?? '$title action completed.')),
              );
            },
            child: Text(
              'Confirm',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeBackground({
    required SwipeAction action,
    required Alignment alignment,
    required ResponsiveScale rs,
    required bool isUnmarking,
  }) {
    final IconData icon;

    if (isUnmarking) {
      icon = Icons.undo_rounded;
    } else {
      switch (action) {
        case SwipeAction.present:
          icon = Icons.check_rounded;
          break;
        case SwipeAction.absent:
          icon = Icons.close_rounded;
          break;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222226),
        borderRadius: BorderRadius.circular(rs.scale(14)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
      ),
      padding: EdgeInsets.symmetric(horizontal: rs.width(22)),
      alignment: alignment,
      child: Icon(icon, color: Colors.white, size: rs.scale(22)),
    );
  }

  Future<void> _handleSwipeAction({
    required BuildContext context,
    required SwipeAction action,
    required bool isUnmarking,
    required Subject subject,
    required String? slotKey,
    required DateTime targetDate,
    required SubjectProvider subjectProvider,
  }) async {
    if (CalendarUtils.isLockedByManualOverride(subject, targetDate)) {
      return;
    }
    HapticFeedback.vibrate();
    final String message;
    if (isUnmarking) {
      await subjectProvider.unmarkAttendance(
        subject.id,
        targetDate,
        slotKey: slotKey,
      );
      message = 'Reset for ${subject.acronym ?? subject.name}';
    } else {
      switch (action) {
        case SwipeAction.present:
          await subjectProvider.markAttendance(
            subject.id,
            targetDate,
            AttendanceStatus.attended,
            slotKey: slotKey,
          );
          message = '${subject.acronym ?? subject.name} marked Present';
          break;
        case SwipeAction.absent:
          await subjectProvider.markAttendance(
            subject.id,
            targetDate,
            AttendanceStatus.absent,
            slotKey: slotKey,
          );
          message = '${subject.acronym ?? subject.name} marked Absent';
          break;
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _cycleAttendanceStatus({
    required BuildContext context,
    required Subject subject,
    required String? slotKey,
    required DateTime targetDate,
    required Attendance? currentAttendance,
    required SubjectProvider subjectProvider,
  }) async {
    if (CalendarUtils.isLockedByManualOverride(subject, targetDate)) return;
    HapticFeedback.lightImpact();

    final currentStatus = currentAttendance?.status;
    final String message;

    if (currentStatus == null) {
      await subjectProvider.markAttendance(
        subject.id,
        targetDate,
        AttendanceStatus.attended,
        slotKey: slotKey,
      );
      message = '${subject.acronym ?? subject.name} marked Present';
    } else if (currentStatus == AttendanceStatus.attended) {
      await subjectProvider.markAttendance(
        subject.id,
        targetDate,
        AttendanceStatus.absent,
        slotKey: slotKey,
      );
      message = '${subject.acronym ?? subject.name} marked Absent';
    } else {
      await subjectProvider.unmarkAttendance(
        subject.id,
        targetDate,
        slotKey: slotKey,
      );
      message = 'Attendance reset for ${subject.acronym ?? subject.name}';
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  // --- Week Calendar Strip (Tesla x Nothing Minimal Monotone) ---
  Widget _buildWeekCalendarStrip(BuildContext context) {
    if (_dates.isEmpty) return const SizedBox.shrink();

    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final activeDate = _dates[_currentIndex];
    final isCurrentDateToday = CalendarUtils.isSameDay(activeDate, _today);

    return Container(
      padding: EdgeInsets.only(
        top: rs.height(4),
        bottom: rs.height(8),
      ),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Monotone Month/Year Header & Minimalist Today Jump
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(activeDate).toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: rs.font(13),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                  ),
                ),
                if (!isCurrentDateToday)
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      jumpToToday();
                    },
                    borderRadius: BorderRadius.circular(rs.scale(14)),
                    child: Container(
                      padding: rs.insetsSymmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.black.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: rs.scale(11),
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                          SizedBox(width: rs.width(4)),
                          Text(
                            'TODAY',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(10.5),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: rs.height(4)),
          // Fixed Current Week Day Badges (Non-scrollable, Monotone Style)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: rs.width(10)),
            child: Row(
              children: List.generate(_dates.length, (index) {
                final date = _dates[index];
                final isSelected = index == _currentIndex;
                final isTodayDate = CalendarUtils.isSameDay(date, _today);
                const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                final weekdayLetter = weekdays[date.weekday - 1];

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: rs.width(2)),
                    child: InkWell(
                      onTap: () {
                        if (index == _currentIndex) return;
                        HapticFeedback.selectionClick();
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      borderRadius: BorderRadius.circular(rs.scale(16)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.symmetric(vertical: rs.height(6)),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDarkMode ? Colors.white : Colors.black)
                              : (isTodayDate
                                  ? (isDarkMode
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.05))
                                  : Colors.transparent),
                          borderRadius: BorderRadius.circular(rs.scale(16)),
                          border: !isSelected && isTodayDate
                              ? Border.all(
                                  color: isDarkMode
                                      ? Colors.white.withValues(alpha: 0.35)
                                      : Colors.black.withValues(alpha: 0.25),
                                  width: 0.8,
                                )
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              weekdayLetter,
                              style: GoogleFonts.inter(
                                fontSize: rs.font(10.5),
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? (isDarkMode ? Colors.black : Colors.white)
                                    : (isDarkMode
                                        ? Colors.white.withValues(alpha: 0.4)
                                        : Colors.black.withValues(alpha: 0.4)),
                              ),
                            ),
                            SizedBox(height: rs.height(2)),
                            Text(
                              '${date.day}',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(14.5),
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected
                                    ? (isDarkMode ? Colors.black : Colors.white)
                                    : (isDarkMode ? Colors.white : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final semester = semesterProvider.semester;
    if (semester != null && !semesterProvider.hasSemesterStarted) {
      final startDate = semester.startDate;
      final formattedDate = '${startDate.day}/${startDate.month}/${startDate.year}';
      return Center(
        child: Padding(
          padding: rs.insetsAll(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: rs.scale(42),
                color: isDarkMode ? Colors.white38 : Colors.black38,
              ),
              SizedBox(height: rs.height(16)),
              Text(
                'SEMESTER YET TO BEGIN',
                style: GoogleFonts.inter(
                  fontSize: rs.font(16),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'Tracking begins on $formattedDate.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: rs.font(13),
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (semester != null && semesterProvider.hasSemesterEnded) {
      return Center(
        child: Padding(
          padding: rs.insetsAll(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.school_outlined,
                size: rs.scale(42),
                color: isDarkMode ? Colors.white38 : Colors.black38,
              ),
              SizedBox(height: rs.height(16)),
              Text(
                'SEMESTER ENDED',
                style: GoogleFonts.inter(
                  fontSize: rs.font(16),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'The semester has concluded.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: rs.font(13),
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_dates.isEmpty) {
      _buildDatesList(semester);
    }

    return Column(
      children: [
        _buildWeekCalendarStrip(context),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _dates.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _notifyDayChanged();
            },
            itemBuilder: (pageContext, index) {
              final date = _dates[index];
              return _buildDaySchedule(pageContext, date);
            },
          ),
        ),
      ],
    );
  }

  // --- Day Schedule with Monotone Timeline & Tesla-style Cards ---
  Widget _buildDaySchedule(BuildContext context, DateTime targetDate) {
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final swipeProvider = Provider.of<SwipeActionProvider>(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final rs = context.rs;

    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    final bool isFutureDate = targetDate.isAfter(_today);
    final bool isToday = CalendarUtils.isSameDay(targetDate, _today);

    final displayClasses = _expandSubjectsBySlot(subjectProvider.getClassesForDate(targetDate));
    displayClasses.sort((a, b) {
      final aTime = a.schedule.first.startTime.hour * 60 + a.schedule.first.startTime.minute;
      final bTime = b.schedule.first.startTime.hour * 60 + b.schedule.first.startTime.minute;
      return aTime.compareTo(bTime);
    });

    final editableClasses = displayClasses
        .where((subject) => !CalendarUtils.isLockedByManualOverride(subject, targetDate))
        .toList();
    final lockedCount = displayClasses.length - editableClasses.length;
    final bool allLocked = displayClasses.isNotEmpty && lockedCount == displayClasses.length;

    // Check statuses for quick action highlights
    final dayRecords = attendanceProvider.attendanceRecords.where((r) =>
        CalendarUtils.isSameDay(r.date, targetDate)).toList();
    final editableIds = editableClasses.map((s) => s.id).toSet();
    final editableRecords = dayRecords.where((r) => editableIds.contains(r.subjectId)).toList();

    final bool isDayHoliday = editableRecords.isNotEmpty &&
        editableRecords.every((r) => r.status == AttendanceStatus.cancelled);
    final bool isDaySkipped = editableRecords.isNotEmpty &&
        editableRecords.every((r) => r.status == AttendanceStatus.absent);
    final bool isDayPresent = editableRecords.length >= editableClasses.length &&
        editableRecords.every((r) => r.status == AttendanceStatus.attended);

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
                    'Semester has ended. Attendance tracking is locked.',
                    style: GoogleFonts.inter(
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      fontSize: rs.font(12.5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!semesterEnded && !isFutureDate && allLocked)
          Container(
            margin: rs.insetsSymmetric(horizontal: 16, vertical: 8),
            padding: rs.insetsSymmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF161619) : const Color(0xFFF2F2F5),
              borderRadius: BorderRadius.circular(rs.scale(12)),
              border: Border.all(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: isDarkMode ? Colors.white54 : Colors.black54,
                  size: rs.scale(16),
                ),
                SizedBox(width: rs.width(10)),
                Expanded(
                  child: Text(
                    'Classes locked due to manual count update.',
                    style: GoogleFonts.inter(
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      fontWeight: FontWeight.w500,
                      fontSize: rs.font(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Quick Day Actions (Tesla x Nothing Monotone Pill Style)
        if (!semesterEnded && !isFutureDate && !allLocked && displayClasses.isNotEmpty)
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionPill(
                    icon: Icons.pause_rounded,
                    label: 'Holiday',
                    isActive: isDayHoliday,
                    isDarkMode: isDarkMode,
                    rs: rs,
                    onTap: () => _showConfirmationDialog(
                      context: context,
                      title: 'Mark as Holiday',
                      content: lockedCount > 0
                          ? 'Are you sure you want to mark ${editableClasses.length} class(es) as holiday? $lockedCount locked class(es) will remain unchanged.'
                          : (isToday
                              ? 'Are you sure you want to mark today as a holiday? All classes will be cancelled and won\'t affect attendance criteria.'
                              : 'Are you sure you want to mark this day as a holiday? All classes will be cancelled and won\'t affect attendance criteria.'),
                      onConfirm: () => subjectProvider.markDayAsHoliday(targetDate),
                      successMessage: lockedCount > 0
                          ? 'Marked ${editableClasses.length} class(es) as holiday.'
                          : 'Holiday action completed.',
                    ),
                  ),
                ),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: _buildActionPill(
                    icon: Icons.remove_rounded,
                    label: 'Skip Day',
                    isActive: isDaySkipped,
                    isDarkMode: isDarkMode,
                    rs: rs,
                    onTap: () => _showConfirmationDialog(
                      context: context,
                      title: isToday ? 'Skip Today' : 'Skip Day',
                      content: lockedCount > 0
                          ? 'Are you sure you want to skip ${editableClasses.length} class(es)? $lockedCount locked class(es) will remain unchanged.'
                          : (isToday
                              ? 'Are you sure you want to skip all classes today? This will mark all scheduled classes as absent.'
                              : 'Are you sure you want to skip all classes on this day? This will mark all scheduled classes as absent.'),
                      onConfirm: () => subjectProvider.markDayAsAbsent(targetDate),
                      successMessage: lockedCount > 0
                          ? 'Marked ${editableClasses.length} class(es) as absent.'
                          : 'Skip Day action completed.',
                    ),
                  ),
                ),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: _buildActionPill(
                    icon: Icons.check_rounded,
                    label: 'Present',
                    isActive: isDayPresent,
                    isDarkMode: isDarkMode,
                    rs: rs,
                    onTap: () => _showConfirmationDialog(
                      context: context,
                      title: isToday ? 'Mark as Present' : 'Mark Day as Present',
                      content: lockedCount > 0
                          ? 'Are you sure you want to mark ${editableClasses.length} class(es) as present? $lockedCount locked class(es) will remain unchanged.'
                          : (isToday
                              ? 'Are you sure you want to mark today as present? All classes will be marked as attended.'
                              : 'Are you sure you want to mark all classes on this day as attended?'),
                      onConfirm: () => subjectProvider.markDayAsPresent(targetDate),
                      successMessage: lockedCount > 0
                          ? 'Marked ${editableClasses.length} class(es) as present.'
                          : 'Mark as Present action completed.',
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (!semesterEnded && isFutureDate && displayClasses.isNotEmpty && !allLocked)
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: _buildActionPill(
                icon: Icons.pause_rounded,
                label: 'Mark Day as Holiday',
                isActive: isDayHoliday,
                isDarkMode: isDarkMode,
                rs: rs,
                onTap: () => _showConfirmationDialog(
                  context: context,
                  title: 'Mark as Holiday',
                  content: lockedCount > 0
                      ? 'Are you sure you want to mark ${editableClasses.length} upcoming class(es) as a holiday? $lockedCount locked class(es) will remain unchanged.'
                      : 'Are you sure you want to mark this upcoming day as a holiday? All classes will be cancelled.',
                  onConfirm: () => subjectProvider.markDayAsHoliday(targetDate),
                  successMessage: lockedCount > 0
                      ? 'Marked ${editableClasses.length} class(es) as holiday.'
                      : 'Day marked as holiday.',
                ),
              ),
            ),
          ),

        // Timeline Schedule or Empty State
        if (displayClasses.isEmpty)
          Expanded(
            child: _buildEmptyState(isToday: isToday, isDarkMode: isDarkMode, rs: rs),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.only(
                left: rs.width(16),
                right: rs.width(16),
                top: rs.height(6),
                bottom: rs.height(100),
              ),
              itemCount: displayClasses.length,
              itemBuilder: (context, index) {
                final subject = displayClasses[index];
                final timeSlot = subject.schedule.first;
                final slotKey = timeSlot.slotKey;
                final isLocked = CalendarUtils.isLockedByManualOverride(subject, targetDate);
                final overrideDate = subject.manualAttendanceOverride?.effectiveFrom;
                final attendance = attendanceProvider.getAttendanceForSubjectOnDate(
                  subject.id,
                  targetDate,
                  slotKey: slotKey,
                );

                final isFirst = index == 0;
                final isLast = index == displayClasses.length - 1;

                return _buildTimelineItem(
                  context: context,
                  subject: subject,
                  timeSlot: timeSlot,
                  slotKey: slotKey,
                  targetDate: targetDate,
                  attendance: attendance,
                  isLocked: isLocked,
                  overrideDate: overrideDate,
                  isFirst: isFirst,
                  isLast: isLast,
                  isFutureDate: isFutureDate,
                  semesterEnded: semesterEnded,
                  rs: rs,
                  isDarkMode: isDarkMode,
                  subjectProvider: subjectProvider,
                  timeFormatProvider: timeFormatProvider,
                  swipeProvider: swipeProvider,
                );
              },
            ),
          ),
      ],
    );
  }

  // --- Monotone Action Pill Button (Tesla/Nothing High-Contrast) ---
  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isDarkMode,
    required ResponsiveScale rs,
    required VoidCallback onTap,
  }) {
    // Liquid glass action pills with high contrast active state
    final bgColor = isActive
        ? (isDarkMode ? Colors.white : Colors.black)
        : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.45));

    final fgColor = isActive
        ? (isDarkMode ? Colors.black : Colors.white)
        : (isDarkMode ? Colors.white.withValues(alpha: 0.9) : Colors.black87);

    final borderColor = isActive
        ? (isDarkMode ? Colors.white : Colors.black)
        : (isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08));

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(rs.scale(20)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          vertical: rs.height(9),
          horizontal: rs.width(8),
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(rs.scale(20)),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: rs.scale(14), color: fgColor),
            SizedBox(width: rs.width(5)),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: rs.font(12),
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  color: fgColor,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Timeline Item (Tesla x Nothing Architecture) ---
  Widget _buildTimelineItem({
    required BuildContext context,
    required Subject subject,
    required TimeSlot timeSlot,
    required String? slotKey,
    required DateTime targetDate,
    required Attendance? attendance,
    required bool isLocked,
    required DateTime? overrideDate,
    required bool isFirst,
    required bool isLast,
    required bool isFutureDate,
    required bool semesterEnded,
    required ResponsiveScale rs,
    required bool isDarkMode,
    required SubjectProvider subjectProvider,
    required TimeFormatProvider timeFormatProvider,
    required SwipeActionProvider swipeProvider,
  }) {
    final showActions = !semesterEnded && !isLocked;

    // Room and Block
    final effectiveLocId = subject.getEffectiveLocationId(timeSlot);
    final locConfig = effectiveLocId != null ? _locationById[effectiveLocId] : null;
    final room = subject.getEffectiveRoom(timeSlot) ?? locConfig?.name;
    final block = subject.getEffectiveBlock(timeSlot) ?? locConfig?.block;
    final hasRoom = room != null && room.isNotEmpty;

    // Duration calculation
    final startMinutes = timeSlot.startTime.hour * 60 + timeSlot.startTime.minute;
    final endMinutes = timeSlot.endTime.hour * 60 + timeSlot.endTime.minute;
    final diffMinutes = endMinutes - startMinutes;
    String durationStr = '';
    if (diffMinutes > 0) {
      if (diffMinutes % 60 == 0) {
        durationStr = '  (${diffMinutes ~/ 60}h)';
      } else if (diffMinutes > 60) {
        durationStr = '  (${diffMinutes ~/ 60}h ${diffMinutes % 60}m)';
      } else {
        durationStr = '  (${diffMinutes}m)';
      }
    }

    // Status styling (Monotone Tesla x Nothing)
    final AttendanceStatus? status = attendance?.status;
    final bool isAttended = status == AttendanceStatus.attended;
    final bool isAbsent = status == AttendanceStatus.absent;
    final bool isHoliday = status == AttendanceStatus.cancelled;

    final IconData statusIcon;
    final String statusLabel;

    if (isLocked) {
      statusIcon = Icons.lock_outline_rounded;
      statusLabel = 'Locked';
    } else if (isAttended) {
      statusIcon = Icons.check_rounded;
      statusLabel = 'Present';
    } else if (isAbsent) {
      statusIcon = Icons.close_rounded;
      statusLabel = 'Absent';
    } else if (isHoliday) {
      statusIcon = Icons.pause_rounded;
      statusLabel = 'Holiday';
    } else if (isFutureDate) {
      statusIcon = Icons.schedule_rounded;
      statusLabel = 'Upcoming';
    } else {
      statusIcon = Icons.radio_button_unchecked_rounded;
      statusLabel = 'Awaiting';
    }

    // Monotone status button colors
    final Color statusBg;
    final Color statusFg;
    final Color statusBorder;

    if (isAttended) {
      // Solid White on Black (Tesla / Nothing Active Toggle)
      statusBg = isDarkMode ? Colors.white : Colors.black;
      statusFg = isDarkMode ? Colors.black : Colors.white;
      statusBorder = isDarkMode ? Colors.white : Colors.black;
    } else if (isAbsent || isHoliday) {
      // Clean wireframe highlight
      statusBg = isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
      statusFg = isDarkMode ? Colors.white : Colors.black87;
      statusBorder = isDarkMode ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.2);
    } else {
      // Muted awaiting state
      statusBg = isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03);
      statusFg = isDarkMode ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.55);
      statusBorder = isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);
    }

    // Monogram text
    // The Liquid Glass Minimalist Compact Card with dynamic swipe translation
    Widget buildCardContent(double dragOffset) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(rs.scale(14)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(rs.scale(14)),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: rs.width(12),
              vertical: rs.height(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Subject Name & Compact Subline (dynamically moves towards right when container moves left)
                Expanded(
                  child: Transform.translate(
                    offset: Offset(dragOffset < 0 ? -dragOffset * 1.15 : 0.0, 0.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          subject.name,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: rs.font(14),
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: rs.height(2.5)),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${timeSlot.formatTimeRange(timeFormatProvider.timeFormat)}$durationStr',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  color: isDarkMode ? Colors.white60 : Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasRoom) ...[
                              SizedBox(width: rs.width(6)),
                              Flexible(
                                child: Text(
                                  'Room $room${block != null && block.isNotEmpty ? " ($block)" : ""}',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(10.5),
                                    color: isDarkMode ? Colors.white54 : Colors.black45,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (isLocked && overrideDate != null)
                          Padding(
                            padding: EdgeInsets.only(top: rs.height(2)),
                            child: Text(
                              'Locked before ${_formatDate(overrideDate)}',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(10),
                                color: isDarkMode ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: rs.width(8)),
                // Right: Status Toggle Pill (fades when swiping left so subject can move towards right)
                Opacity(
                  opacity: dragOffset < 0
                      ? (1.0 - (-dragOffset / (rs.scale(55)))).clamp(0.0, 1.0)
                      : 1.0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: (!isLocked && !semesterEnded && !isFutureDate)
                            ? () => _cycleAttendanceStatus(
                                  context: context,
                                  subject: subject,
                                  slotKey: slotKey,
                                  targetDate: targetDate,
                                  currentAttendance: attendance,
                                  subjectProvider: subjectProvider,
                                )
                            : null,
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: EdgeInsets.symmetric(
                            horizontal: rs.width(8),
                            vertical: rs.height(4.5),
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(rs.scale(14)),
                            border: Border.all(
                              color: statusBorder,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: rs.scale(11), color: statusFg),
                              SizedBox(width: rs.width(4)),
                              Text(
                                statusLabel,
                                style: GoogleFonts.inter(
                                  color: statusFg,
                                  fontSize: rs.font(10.5),
                                  fontWeight: isAttended ? FontWeight.w700 : FontWeight.w500,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showActions) ...[
                        SizedBox(width: rs.width(4)),
                        InkWell(
                          onTap: () {
                            HapticFeedback.vibrate();
                            if (isHoliday) {
                              subjectProvider.unmarkAttendance(
                                subject.id,
                                targetDate,
                                slotKey: slotKey,
                              );
                            } else {
                              subjectProvider.markAttendance(
                                subject.id,
                                targetDate,
                                AttendanceStatus.cancelled,
                                slotKey: slotKey,
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(rs.scale(12)),
                          child: Padding(
                            padding: rs.insetsAll(4),
                            child: Icon(
                              isHoliday ? Icons.pause_circle_filled_rounded : Icons.pause_circle_outline_rounded,
                              size: rs.scale(16),
                              color: isHoliday
                                  ? (isDarkMode ? Colors.white : Colors.black)
                                  : (isDarkMode ? Colors.white30 : Colors.black26),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Swipeable Card Wrapper
    final Widget interactiveCard;
    if (semesterEnded || isFutureDate || isLocked) {
      interactiveCard = buildCardContent(0.0);
    } else {
      final isUnmarkingRight = (attendance?.status == AttendanceStatus.attended &&
              swipeProvider.rightAction == SwipeAction.present) ||
          (attendance?.status == AttendanceStatus.absent &&
              swipeProvider.rightAction == SwipeAction.absent);

      final isUnmarkingLeft = (attendance?.status == AttendanceStatus.attended &&
              swipeProvider.leftAction == SwipeAction.present) ||
          (attendance?.status == AttendanceStatus.absent &&
              swipeProvider.leftAction == SwipeAction.absent);

      interactiveCard = SwipeableCard(
        key: ValueKey('${subject.id}_${slotKey}_${targetDate.millisecondsSinceEpoch}'),
        swipeRightBackground: _buildSwipeBackground(
          action: swipeProvider.rightAction,
          alignment: Alignment.centerLeft,
          rs: rs,
          isUnmarking: isUnmarkingRight,
        ),
        swipeLeftBackground: _buildSwipeBackground(
          action: swipeProvider.leftAction,
          alignment: Alignment.centerRight,
          rs: rs,
          isUnmarking: isUnmarkingLeft,
        ),
        onSwipeRight: () => _handleSwipeAction(
          context: context,
          action: swipeProvider.rightAction,
          isUnmarking: isUnmarkingRight,
          subject: subject,
          slotKey: slotKey,
          targetDate: targetDate,
          subjectProvider: subjectProvider,
        ),
        onSwipeLeft: () => _handleSwipeAction(
          context: context,
          action: swipeProvider.leftAction,
          isUnmarking: isUnmarkingLeft,
          subject: subject,
          slotKey: slotKey,
          targetDate: targetDate,
          subjectProvider: subjectProvider,
        ),
        rs: rs,
        borderRadius: BorderRadius.circular(rs.scale(14)),
        childBuilder: (context, dragOffset) => buildCardContent(dragOffset),
      );
    }

    // Timeline Row: Monotone Vertical Track + Minimalist Node + Card
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Rail (Thin wireframe line + Symmetrical Encircled Subject PFP Node)
          SizedBox(
            width: rs.scale(38),
            child: Column(
              children: [
                // Top line
                Container(
                  width: 1.5,
                  height: rs.scale(12),
                  color: isFirst
                      ? Colors.transparent
                      : (isDarkMode
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08)),
                ),
                // Encircled Circular PFP with Custom Border
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
                // Bottom connecting line
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isLast
                        ? Colors.transparent
                        : (isDarkMode
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.08)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: rs.width(8)),
          // Right Card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: rs.height(8)),
              child: interactiveCard,
            ),
          ),
        ],
      ),
    );
  }

  // --- Liquid Glass Minimalist Empty State ---
  Widget _buildEmptyState({
    required bool isToday,
    required bool isDarkMode,
    required ResponsiveScale rs,
  }) {
    return Center(
      child: Padding(
        padding: rs.insetsAll(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rs.scale(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: rs.insetsAll(28),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.50),
                borderRadius: BorderRadius.circular(rs.scale(24)),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: rs.scale(48),
                    height: rs.scale(48),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.calendar_today_outlined,
                      size: rs.scale(20),
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  SizedBox(height: rs.height(16)),
                  Text(
                    isToday ? 'NO CLASSES TODAY' : 'NO CLASSES SCHEDULED',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(13.5),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: rs.height(6)),
                  Text(
                    'No events scheduled for this day.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: rs.font(12),
                      color: isDarkMode ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
