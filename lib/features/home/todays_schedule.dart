import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/attendance_math.dart';
import '../semester/semester_model.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
import '../subject/subject_provider.dart';
import '../subject/subject_model.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../calendar/calendar_utils.dart';
import '../location/location_model.dart';
import '../../services/database_service.dart';

typedef DayChangedCallback = void Function(String title, bool canGoPrevious, bool canGoNext);

enum ScheduleViewMode {
  deck,
  receipt,
}

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
      // Location display is non-critical
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

  // --- Week Calendar Strip (Minimal Monotone Liquid Glass) ---
  Widget _buildWeekCalendarStrip(BuildContext context) {
    if (_dates.isEmpty) return const SizedBox.shrink();

    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final activeDate = _dates[_currentIndex];
    final isCurrentDateToday = CalendarUtils.isSameDay(activeDate, _today);

    return Container(
      padding: EdgeInsets.only(
        top: rs.height(2),
        bottom: rs.height(4),
      ),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Monotone Month/Year Header & Minimalist Today Jump
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(activeDate).toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: rs.font(12),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
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
                      padding: rs.insetsSymmetric(horizontal: 8, vertical: 3),
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
                              fontSize: rs.font(10),
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
          // Current Week Day Badges
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
                        padding: EdgeInsets.symmetric(vertical: rs.height(5)),
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
                                fontSize: rs.font(10),
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
                                fontSize: rs.font(14),
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
            // CRITICAL: Disable PageView horizontal drag so card pan gestures are 100% responsive!
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _notifyDayChanged();
            },
            itemBuilder: (pageContext, index) {
              final date = _dates[index];
              return SingleDayScheduleView(
                key: ValueKey(date.millisecondsSinceEpoch),
                targetDate: date,
                today: _today,
                locationById: _locationById,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Single Day View (Houses 3D Stacked Card Feed and Completed Summary)
// ---------------------------------------------------------------------------

class SingleDayScheduleView extends StatefulWidget {
  final DateTime targetDate;
  final DateTime today;
  final Map<String, LocationConfig> locationById;

  const SingleDayScheduleView({
    super.key,
    required this.targetDate,
    required this.today,
    required this.locationById,
  });

  @override
  State<SingleDayScheduleView> createState() => _SingleDayScheduleViewState();
}

class _SingleDayScheduleViewState extends State<SingleDayScheduleView> {
  ScheduleViewMode _viewMode = ScheduleViewMode.deck;
  int _activeCardIndex = 0;
  bool _isAccordionExpanded = false;

  List<Subject> _expandSubjectsBySlot(List<Subject> subjects) {
    final expandedSubjects = <Subject>[];
    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        expandedSubjects.add(subject.copyWith(schedule: [slot]));
      }
    }
    return expandedSubjects;
  }

  void _summonCard(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeCardIndex = index;
      _viewMode = ScheduleViewMode.deck;
      _isAccordionExpanded = false;
    });
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
              if (context.mounted && successMessage != null) {
                ScaffoldMessenger.of(context).showReplacingSnackBar(
                  SnackBar(content: Text(successMessage)),
                );
              }
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

  // --- Inline Decision Switcher Bottom Sheet ---
  void _openDecisionModificationSheet({
    required BuildContext context,
    required Subject subject,
    required TimeSlot timeSlot,
    required String? slotKey,
    required Attendance? currentAttendance,
    required SubjectProvider subjectProvider,
    required TimeFormatProvider timeFormatProvider,
    required ResponsiveScale rs,
    required bool isDarkMode,
  }) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final currentStatus = currentAttendance?.status;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: EdgeInsets.fromLTRB(
                rs.scale(20),
                rs.scale(16),
                rs.scale(20),
                rs.scale(32) + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF141416).withValues(alpha: 0.92)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 0.9,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: rs.scale(36),
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: rs.height(16)),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: subject.color.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          subject.displayAcronym,
                          style: GoogleFonts.inter(
                            fontSize: rs.font(11),
                            fontWeight: FontWeight.w800,
                            color: subject.color,
                          ),
                        ),
                      ),
                      SizedBox(width: rs.width(10)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject.name,
                              style: GoogleFonts.inter(
                                fontSize: rs.font(16),
                                fontWeight: FontWeight.w700,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              timeSlot.formatTimeRange(timeFormatProvider.timeFormat),
                              style: GoogleFonts.inter(
                                fontSize: rs.font(12),
                                color: isDarkMode ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(20)),
                  Text(
                    'MODIFY DECISION',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(11),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: isDarkMode ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  SizedBox(height: rs.height(12)),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDecisionChoiceBtn(
                          title: 'Attended',
                          icon: Icons.check_rounded,
                          color: const Color(0xFF10B981),
                          isSelected: currentStatus == AttendanceStatus.attended,
                          isDarkMode: isDarkMode,
                          rs: rs,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await subjectProvider.markAttendance(
                              subject.id,
                              widget.targetDate,
                              AttendanceStatus.attended,
                              slotKey: slotKey,
                            );
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                        ),
                      ),
                      SizedBox(width: rs.width(8)),
                      Expanded(
                        child: _buildDecisionChoiceBtn(
                          title: 'Missed',
                          icon: Icons.close_rounded,
                          color: const Color(0xFFEF4444),
                          isSelected: currentStatus == AttendanceStatus.absent || currentStatus == AttendanceStatus.plannedAbsent,
                          isDarkMode: isDarkMode,
                          rs: rs,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await subjectProvider.markAttendance(
                              subject.id,
                              widget.targetDate,
                              AttendanceStatus.absent,
                              slotKey: slotKey,
                            );
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(8)),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDecisionChoiceBtn(
                          title: 'Cancelled',
                          icon: Icons.pause_rounded,
                          color: const Color(0xFFF59E0B),
                          isSelected: currentStatus == AttendanceStatus.cancelled,
                          isDarkMode: isDarkMode,
                          rs: rs,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await subjectProvider.markAttendance(
                              subject.id,
                              widget.targetDate,
                              AttendanceStatus.cancelled,
                              slotKey: slotKey,
                            );
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                        ),
                      ),
                      SizedBox(width: rs.width(8)),
                      Expanded(
                        child: _buildDecisionChoiceBtn(
                          title: 'Reset',
                          icon: Icons.undo_rounded,
                          color: const Color(0xFF71717A),
                          isSelected: currentStatus == null,
                          isDarkMode: isDarkMode,
                          rs: rs,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await subjectProvider.unmarkAttendance(
                              subject.id,
                              widget.targetDate,
                              slotKey: slotKey,
                            );
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDecisionChoiceBtn({
    required String title,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required bool isDarkMode,
    required ResponsiveScale rs,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(rs.scale(16)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: rs.height(12), horizontal: rs.width(8)),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: isDarkMode ? 0.22 : 0.16)
                : (isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(rs.scale(16)),
            border: Border.all(
              color: isSelected ? color : (isDarkMode ? Colors.white12 : Colors.black12),
              width: isSelected ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: rs.scale(15), color: isSelected ? color : (isDarkMode ? Colors.white70 : Colors.black54)),
              SizedBox(width: rs.width(6)),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: rs.font(12.5),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : (isDarkMode ? Colors.white : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final rs = context.rs;

    final semester = semesterProvider.semester;
    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    final bool isFutureDate = widget.targetDate.isAfter(widget.today);
    final bool isToday = CalendarUtils.isSameDay(widget.targetDate, widget.today);

    // Expand classes and sort by schedule time
    final displayClasses = _expandSubjectsBySlot(subjectProvider.getClassesForDate(widget.targetDate));
    displayClasses.sort((a, b) {
      final aTime = a.schedule.first.startTime.hour * 60 + a.schedule.first.startTime.minute;
      final bTime = b.schedule.first.startTime.hour * 60 + b.schedule.first.startTime.minute;
      return aTime.compareTo(bTime);
    });

    if (displayClasses.isEmpty) {
      return _buildEmptyState(isToday: isToday, isDarkMode: isDarkMode, rs: rs);
    }

    // Clamp active card index
    if (_activeCardIndex >= displayClasses.length) {
      _activeCardIndex = 0;
    }

    int markedCount = 0;
    int attendedCount = 0;
    int absentCount = 0;
    int cancelledCount = 0;

    for (final s in displayClasses) {
      final slotKey = s.schedule.first.slotKey;
      final rec = attendanceProvider.getAttendanceForSubjectOnDate(s.id, widget.targetDate, slotKey: slotKey);
      if (rec != null) {
        markedCount++;
        if (rec.status == AttendanceStatus.attended) attendedCount++;
        if (rec.status == AttendanceStatus.absent || rec.status == AttendanceStatus.plannedAbsent) absentCount++;
        if (rec.status == AttendanceStatus.cancelled) cancelledCount++;
      }
    }

    final bool allMarked = markedCount == displayClasses.length;

    // Overall Semester Attendance Stats & Bunk Buffer
    int totalAttendedSemester = 0;
    int totalHeldSemester = 0;
    for (final sub in subjectProvider.subjects) {
      final override = sub.manualAttendanceOverride;
      if (override != null) {
        totalAttendedSemester += override.classesAttended;
        totalHeldSemester += override.classesHeld;
        final subRecords = attendanceProvider.attendanceRecords.where((r) =>
            r.subjectId == sub.id && !r.date.isBefore(override.effectiveFrom));
        for (final r in subRecords) {
          if (r.status == AttendanceStatus.attended) totalAttendedSemester++;
          if (r.status != AttendanceStatus.cancelled) totalHeldSemester++;
        }
      } else {
        final subRecords = attendanceProvider.attendanceRecords.where((r) =>
            r.subjectId == sub.id && (semester == null || !r.date.isBefore(semester.startDate)));
        for (final r in subRecords) {
          if (r.status == AttendanceStatus.attended) totalAttendedSemester++;
          if (r.status != AttendanceStatus.cancelled) totalHeldSemester++;
        }
      }
    }

    final double overallPercentage = totalHeldSemester > 0
        ? ((totalAttendedSemester / totalHeldSemester) * 100.0)
        : 100.0;

    final double targetPercentage = semester?.targetPercentage ?? 75.0;
    final int bunkBuffer = AttendanceMath.calculateBunkableClasses(
      attended: totalAttendedSemester,
      marked: totalHeldSemester,
      targetPercentage: targetPercentage,
    );

    final bool isSafe = overallPercentage >= targetPercentage;

    return Stack(
      children: [
        Column(
          children: [
            // 1. Top Metrics Header Bar
            _buildTopMetricsBar(
              markedCount: markedCount,
              totalClasses: displayClasses.length,
              overallPercentage: overallPercentage,
              isSafe: isSafe,
              isDarkMode: isDarkMode,
              rs: rs,
              allMarked: allMarked,
            ),

            // 2. Card Stepper Bar on Top (Moved to top so it is NEVER buried behind nav bar!)
            if (_viewMode == ScheduleViewMode.deck)
              _buildTopStepperBar(
                activeIndex: _activeCardIndex,
                totalClasses: displayClasses.length,
                isDarkMode: isDarkMode,
                rs: rs,
              ),

            // 3. Main Stage: 3D Stacked Deck or Completed Summary
            Expanded(
              child: (_viewMode == ScheduleViewMode.receipt || (allMarked && _viewMode == ScheduleViewMode.receipt))
                  ? DayOverSummaryView(
                      targetDate: widget.targetDate,
                      displayClasses: displayClasses,
                      attendanceProvider: attendanceProvider,
                      subjectProvider: subjectProvider,
                      timeFormatProvider: timeFormatProvider,
                      locationById: widget.locationById,
                      overallPercentage: overallPercentage,
                      bunkBuffer: bunkBuffer,
                      isSafe: isSafe,
                      markedCount: markedCount,
                      attendedCount: attendedCount,
                      absentCount: absentCount,
                      cancelledCount: cancelledCount,
                      isToday: isToday,
                      isDarkMode: isDarkMode,
                      rs: rs,
                      semesterEnded: semesterEnded,
                      isFutureDate: isFutureDate,
                      onRevisitDeck: () {
                        setState(() {
                          _viewMode = ScheduleViewMode.deck;
                        });
                      },
                      onModifyItem: (subject, slot, slotKey, attendance) {
                        _openDecisionModificationSheet(
                          context: context,
                          subject: subject,
                          timeSlot: slot,
                          slotKey: slotKey,
                          currentAttendance: attendance,
                          subjectProvider: subjectProvider,
                          timeFormatProvider: timeFormatProvider,
                          rs: rs,
                          isDarkMode: isDarkMode,
                        );
                      },
                      onMarkDayHoliday: () => _showConfirmationDialog(
                        context: context,
                        title: 'Mark as Holiday',
                        content: isToday
                            ? 'Are you sure you want to mark today as a holiday? All classes will be cancelled and will not affect attendance criteria.'
                            : 'Are you sure you want to mark this day as a holiday? All classes will be cancelled and will not affect attendance criteria.',
                        onConfirm: () => subjectProvider.markDayAsHoliday(widget.targetDate),
                        successMessage: 'Holiday action completed.',
                      ),
                      onMarkDayAbsent: () => _showConfirmationDialog(
                        context: context,
                        title: isToday ? 'Skip Today' : 'Skip Day',
                        content: isToday
                            ? 'Are you sure you want to skip all classes today? This will mark all scheduled classes as absent.'
                            : 'Are you sure you want to skip all classes on this day? This will mark all scheduled classes as absent.',
                        onConfirm: () => subjectProvider.markDayAsAbsent(widget.targetDate),
                        successMessage: 'Skip Day action completed.',
                      ),
                      onMarkDayPresent: () => _showConfirmationDialog(
                        context: context,
                        title: isToday ? 'Mark as Present' : 'Mark Day as Present',
                        content: isToday
                            ? 'Are you sure you want to mark today as present? All classes will be marked as attended.'
                            : 'Are you sure you want to mark all classes on this day as attended?',
                        onConfirm: () => subjectProvider.markDayAsPresent(widget.targetDate),
                        successMessage: 'Mark as Present action completed.',
                      ),
                    )
                  : StackedCardDeck(
                      targetDate: widget.targetDate,
                      displayClasses: displayClasses,
                      activeIndex: _activeCardIndex,
                      attendanceProvider: attendanceProvider,
                      subjectProvider: subjectProvider,
                      timeFormatProvider: timeFormatProvider,
                      locationById: widget.locationById,
                      semesterEnded: semesterEnded,
                      isFutureDate: isFutureDate,
                      isDarkMode: isDarkMode,
                      rs: rs,
                      onCardSwiped: (index, newStatus) async {
                        final subject = displayClasses[index];
                        final slotKey = subject.schedule.first.slotKey;
                        await subjectProvider.markAttendance(
                          subject.id,
                          widget.targetDate,
                          newStatus,
                          slotKey: slotKey,
                        );

                        // If all classes are marked, transition to summary
                        if (markedCount + 1 >= displayClasses.length) {
                          Future.delayed(const Duration(milliseconds: 320), () {
                            if (mounted) {
                              setState(() {
                                _viewMode = ScheduleViewMode.receipt;
                              });
                            }
                          });
                        } else {
                          // Advance to next card
                          setState(() {
                            _activeCardIndex = (_activeCardIndex + 1) % displayClasses.length;
                          });
                        }
                      },
                      onIndexChanged: (newIdx) {
                        setState(() {
                          _activeCardIndex = newIdx;
                        });
                      },
                      onViewSummaryTap: () {
                        setState(() {
                          _viewMode = ScheduleViewMode.receipt;
                        });
                      },
                    ),
            ),

            // 4. Bottom Accordion Peek Window (Clear of Floating Nav Bar)
            if (_viewMode == ScheduleViewMode.deck)
              Padding(
                padding: EdgeInsets.only(bottom: rs.scale(104)),
                child: AccordionPeekWindow(
                  displayClasses: displayClasses,
                  activeCardIndex: _activeCardIndex,
                  attendanceProvider: attendanceProvider,
                  timeFormatProvider: timeFormatProvider,
                  targetDate: widget.targetDate,
                  locationById: widget.locationById,
                  isExpanded: _isAccordionExpanded,
                  isDarkMode: isDarkMode,
                  rs: rs,
                  onToggleExpand: () {
                    setState(() {
                      _isAccordionExpanded = !_isAccordionExpanded;
                    });
                  },
                  onSummonPeriod: _summonCard,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // --- Top Metrics Header Bar (Active Day + Overall Attendance) ---
  Widget _buildTopMetricsBar({
    required int markedCount,
    required int totalClasses,
    required double overallPercentage,
    required bool isSafe,
    required bool isDarkMode,
    required ResponsiveScale rs,
    required bool allMarked,
  }) {
    return Container(
      margin: rs.insetsSymmetric(horizontal: 16, vertical: 2),
      padding: rs.insetsSymmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(rs.scale(18)),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Day Progress Chip
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: allMarked
                      ? const Color(0xFF10B981)
                      : (markedCount > 0 ? const Color(0xFFF59E0B) : Colors.white38),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: rs.width(8)),
              Text(
                allMarked ? 'Day Logged ($markedCount/$totalClasses)' : '$markedCount of $totalClasses Logged',
                style: GoogleFonts.inter(
                  fontSize: rs.font(12),
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
                ),
              ),
            ],
          ),

          // Right: Overall Attendance & View Switcher
          Row(
            children: [
              Container(
                padding: rs.insetsSymmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: isDarkMode ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  border: Border.all(
                    color: (isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '${overallPercentage.toStringAsFixed(1)}% Overall',
                  style: GoogleFonts.inter(
                    fontSize: rs.font(11),
                    fontWeight: FontWeight.w700,
                    color: isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
              ),
              SizedBox(width: rs.width(8)),
              // Mode Toggle
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _viewMode = _viewMode == ScheduleViewMode.deck
                        ? ScheduleViewMode.receipt
                        : ScheduleViewMode.deck;
                  });
                },
                borderRadius: BorderRadius.circular(rs.scale(12)),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(rs.scale(10)),
                  ),
                  child: Icon(
                    _viewMode == ScheduleViewMode.deck ? Icons.receipt_long_rounded : Icons.style_rounded,
                    size: rs.scale(15),
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Top Stepper Bar (Moved to Top to Never be Buried by Nav Bar!) ---
  Widget _buildTopStepperBar({
    required int activeIndex,
    required int totalClasses,
    required bool isDarkMode,
    required ResponsiveScale rs,
  }) {
    return Container(
      margin: rs.insetsSymmetric(horizontal: 16, vertical: 3),
      padding: rs.insetsSymmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(rs.scale(14)),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Period Button
          InkWell(
            onTap: activeIndex > 0
                ? () {
                    HapticFeedback.selectionClick();
                    _summonCard(activeIndex - 1);
                  }
                : null,
            borderRadius: BorderRadius.circular(rs.scale(12)),
            child: Padding(
              padding: rs.insetsSymmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    size: rs.scale(16),
                    color: activeIndex > 0
                        ? (isDarkMode ? Colors.white : Colors.black87)
                        : (isDarkMode ? Colors.white24 : Colors.black26),
                  ),
                  Text(
                    'Prev',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(11.5),
                      fontWeight: FontWeight.w600,
                      color: activeIndex > 0
                          ? (isDarkMode ? Colors.white : Colors.black87)
                          : (isDarkMode ? Colors.white24 : Colors.black26),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Period Indicator Dots
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Period ${activeIndex + 1} of $totalClasses',
                style: GoogleFonts.inter(
                  fontSize: rs.font(11.5),
                  fontWeight: FontWeight.w700,
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                ),
              ),
              SizedBox(width: rs.width(8)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(totalClasses, (dotIdx) {
                  final isCurrent = dotIdx == activeIndex;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _summonCard(dotIdx);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: isCurrent ? 14 : 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? (isDarkMode ? Colors.white : Colors.black)
                              : (isDarkMode ? Colors.white24 : Colors.black26),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),

          // Next Period Button
          InkWell(
            onTap: activeIndex < totalClasses - 1
                ? () {
                    HapticFeedback.selectionClick();
                    _summonCard(activeIndex + 1);
                  }
                : null,
            borderRadius: BorderRadius.circular(rs.scale(12)),
            child: Padding(
              padding: rs.insetsSymmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Next',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(11.5),
                      fontWeight: FontWeight.w600,
                      color: activeIndex < totalClasses - 1
                          ? (isDarkMode ? Colors.white : Colors.black87)
                          : (isDarkMode ? Colors.white24 : Colors.black26),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: rs.scale(16),
                    color: activeIndex < totalClasses - 1
                        ? (isDarkMode ? Colors.white : Colors.black87)
                        : (isDarkMode ? Colors.white24 : Colors.black26),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
                    'No timetable events scheduled for this day.',
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

// ---------------------------------------------------------------------------
// 3D Stacked Card Feed ("Class Chips Feed" with Swipe Cues & Precision Buttons)
// ---------------------------------------------------------------------------

class StackedCardDeck extends StatefulWidget {
  final DateTime targetDate;
  final List<Subject> displayClasses;
  final int activeIndex;
  final AttendanceProvider attendanceProvider;
  final SubjectProvider subjectProvider;
  final TimeFormatProvider timeFormatProvider;
  final Map<String, LocationConfig> locationById;
  final bool semesterEnded;
  final bool isFutureDate;
  final bool isDarkMode;
  final ResponsiveScale rs;
  final Future<void> Function(int index, AttendanceStatus newStatus) onCardSwiped;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onViewSummaryTap;

  const StackedCardDeck({
    super.key,
    required this.targetDate,
    required this.displayClasses,
    required this.activeIndex,
    required this.attendanceProvider,
    required this.subjectProvider,
    required this.timeFormatProvider,
    required this.locationById,
    required this.semesterEnded,
    required this.isFutureDate,
    required this.isDarkMode,
    required this.rs,
    required this.onCardSwiped,
    required this.onIndexChanged,
    required this.onViewSummaryTap,
  });

  @override
  State<StackedCardDeck> createState() => _StackedCardDeckState();
}

class _StackedCardDeckState extends State<StackedCardDeck>
    with TickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  late AnimationController _flyAnimController;
  late Animation<Offset> _flyOffsetAnim;
  late Animation<double> _rotationAnim;

  // Continuous animation controller for smooth animated 3D card swapping
  late AnimationController _indexAnimController;
  late Animation<double> _indexAnimation;
  double _fromIndex = 0.0;
  double _toIndex = 0.0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.activeIndex.toDouble();
    _toIndex = widget.activeIndex.toDouble();

    _flyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _flyOffsetAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _flyAnimController, curve: Curves.easeOutCubic),
    );
    _rotationAnim = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _flyAnimController, curve: Curves.easeOutCubic),
    );

    _indexAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _indexAnimation = CurvedAnimation(
      parent: _indexAnimController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant StackedCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeIndex != _toIndex.round()) {
      _fromIndex = _currentAnimatedIndex;
      _toIndex = widget.activeIndex.toDouble();
      _indexAnimController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _flyAnimController.dispose();
    _indexAnimController.dispose();
    super.dispose();
  }

  double get _currentAnimatedIndex {
    if (!_indexAnimController.isAnimating) return _toIndex;
    return lerpDouble(_fromIndex, _toIndex, _indexAnimation.value) ?? _toIndex;
  }

  void _triggerAction(AttendanceStatus status) {
    if (widget.semesterEnded) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    Offset targetFly;
    double targetRot = 0;

    switch (status) {
      case AttendanceStatus.attended:
        targetFly = Offset(screenWidth * 1.35, _dragOffset.dy);
        targetRot = 0.26;
        break;
      case AttendanceStatus.absent:
      case AttendanceStatus.plannedAbsent:
        targetFly = Offset(-screenWidth * 1.35, _dragOffset.dy);
        targetRot = -0.26;
        break;
      case AttendanceStatus.cancelled:
        targetFly = Offset(_dragOffset.dx, -screenHeight * 1.15);
        targetRot = 0;
        break;
    }

    HapticFeedback.mediumImpact();

    _flyOffsetAnim = Tween<Offset>(begin: _dragOffset, end: targetFly).animate(
      CurvedAnimation(parent: _flyAnimController, curve: Curves.easeInCubic),
    );
    _rotationAnim = Tween<double>(begin: (_dragOffset.dx / 300) * 0.18, end: targetRot).animate(
      CurvedAnimation(parent: _flyAnimController, curve: Curves.easeInCubic),
    );

    _flyAnimController.forward(from: 0.0).then((_) {
      widget.onCardSwiped(widget.activeIndex, status);
      if (mounted) {
        setState(() {
          _dragOffset = Offset.zero;
        });
        _flyAnimController.reset();
      }
    });
  }

  void _resetPosition() {
    _flyOffsetAnim = Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _flyAnimController, curve: Curves.easeOutBack),
    );
    _rotationAnim = Tween<double>(begin: (_dragOffset.dx / 300) * 0.18, end: 0.0).animate(
      CurvedAnimation(parent: _flyAnimController, curve: Curves.easeOutBack),
    );
    _flyAnimController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = Offset.zero;
        });
        _flyAnimController.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.displayClasses.length;
    if (count == 0) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final activeIndex = widget.activeIndex.clamp(0, count - 1);

    final centerCardWidth = (screenWidth * 0.70).clamp(255.0, 285.0);
    final centerCardHeight = (widget.rs.height(355)).clamp(315.0, 385.0);
    final peekOffset = centerCardWidth * 0.54;

    return Center(
      child: SizedBox(
        width: screenWidth,
        height: centerCardHeight + widget.rs.height(24),
        child: AnimatedBuilder(
          animation: Listenable.merge([_flyAnimController, _indexAnimController]),
          builder: (context, _) {
            final currentAnimatedIndex = _currentAnimatedIndex;

            // Collect visible card indices
            final visibleIndices = <int>[];
            for (int i = 0; i < count; i++) {
              if ((i - currentAnimatedIndex).abs() <= 3.5) {
                visibleIndices.add(i);
              }
            }

            // Sort so furthest from currentAnimatedIndex is rendered first (bottom of stack)
            visibleIndices.sort((a, b) {
              final distA = (a - currentAnimatedIndex).abs();
              final distB = (b - currentAnimatedIndex).abs();
              return distB.compareTo(distA);
            });

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: visibleIndices.map((i) {
                final subject = widget.displayClasses[i];
                final slot = subject.schedule.first;
                final slotKey = slot.slotKey;
                final attendance = widget.attendanceProvider.getAttendanceForSubjectOnDate(
                  subject.id,
                  widget.targetDate,
                  slotKey: slotKey,
                );
                final isLocked = CalendarUtils.isLockedByManualOverride(subject, widget.targetDate);

                final d = i - currentAnimatedIndex;
                final isCurrentActive = (i == activeIndex);

                final clampedD = d.clamp(-3.0, 3.0);
                final double baseDx = clampedD * peekOffset;
                final double baseDy = (clampedD.abs() * 7.5).clamp(0.0, 22.0);
                final double baseRot = (clampedD * 0.09).clamp(-0.24, 0.24);
                final double baseScale = (1.0 - (clampedD.abs() * 0.075)).clamp(0.72, 1.0);
                final double baseOpacity = (1.0 - (clampedD.abs() * 0.18)).clamp(0.25, 1.0);

                Offset cardOffset = Offset(baseDx, baseDy);
                double cardRot = baseRot;
                double cardScale = baseScale;
                double cardOpacity = baseOpacity;

                if (isCurrentActive) {
                  final flyOffset = _flyAnimController.isAnimating ? _flyOffsetAnim.value : _dragOffset;
                  final flyRot = _flyAnimController.isAnimating
                      ? _rotationAnim.value
                      : (flyOffset.dx / 320) * 0.18;
                  cardOffset = Offset(baseDx + flyOffset.dx, baseDy + flyOffset.dy);
                  cardRot = baseRot + flyRot;
                  cardOpacity = 1.0;
                }

                // If not active, render as tapable peeking card face
                if (!isCurrentActive) {
                  final bool isLeftWing = d < 0;
                  return Transform.translate(
                    offset: cardOffset,
                    child: Transform.rotate(
                      angle: cardRot,
                      child: Transform.scale(
                        scale: cardScale,
                        child: Opacity(
                          opacity: cardOpacity,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onIndexChanged(i);
                            },
                            child: _buildPeekingCardFace(
                              subject: subject,
                              slot: slot,
                              width: centerCardWidth,
                              height: centerCardHeight,
                              isLeft: isLeftWing,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                // Active Card with pan gesture detector
                return Transform.translate(
                  offset: cardOffset,
                  child: Transform.rotate(
                    angle: cardRot,
                    child: Transform.scale(
                      scale: cardScale,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          if (widget.semesterEnded || isLocked) return;
                          _flyAnimController.stop();
                        },
                        onPanUpdate: (details) {
                          if (widget.semesterEnded || isLocked) return;
                          setState(() {
                            _dragOffset += details.delta;
                          });
                        },
                        onPanEnd: (details) {
                          if (widget.semesterEnded || isLocked) return;
                          final velocity = details.velocity.pixelsPerSecond;

                          // Swipe right (Attended): dx > 50 or fast flick velocity.dx > 220
                          if (_dragOffset.dx > 50 || (velocity.dx > 220 && _dragOffset.dx > 15)) {
                            _triggerAction(AttendanceStatus.attended);
                          }
                          // Swipe left (Missed): dx < -50 or fast flick velocity.dx < -220
                          else if (_dragOffset.dx < -50 || (velocity.dx < -220 && _dragOffset.dx < -15)) {
                            _triggerAction(AttendanceStatus.absent);
                          }
                          // Swipe up (Cancelled): dy < -45 or fast flick velocity.dy < -220
                          else if (_dragOffset.dy < -45 || (velocity.dy < -220 && _dragOffset.dy < -15)) {
                            _triggerAction(AttendanceStatus.cancelled);
                          } else {
                            _resetPosition();
                          }
                        },
                        child: _buildActiveCardFace(
                          subject: subject,
                          slot: slot,
                          attendance: attendance,
                          isLocked: isLocked,
                          dragOffset: cardOffset - Offset(baseDx, baseDy),
                          width: centerCardWidth,
                          height: centerCardHeight,
                          periodNumber: activeIndex + 1,
                          totalPeriods: count,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  // --- Peeking Background Card Face (Shows Subject Name & Time on Exposed Edge!) ---
  Widget _buildPeekingCardFace({
    required Subject subject,
    required TimeSlot slot,
    required double width,
    required double height,
    required bool isLeft,
  }) {
    final rs = widget.rs;
    final isDarkMode = widget.isDarkMode;

    final effectiveLocId = subject.getEffectiveLocationId(slot);
    final locConfig = effectiveLocId != null ? widget.locationById[effectiveLocId] : null;
    final room = subject.getEffectiveRoom(slot) ?? locConfig?.name;
    final hasRoom = room != null && room.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF141416).withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(rs.scale(26)),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.12),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: subject.color.withValues(alpha: isDarkMode ? 0.18 : 0.12),
                blurRadius: 22,
                spreadRadius: -4,
                offset: Offset(isLeft ? -4 : 4, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: isLeft ? rs.scale(14) : null,
                right: !isLeft ? rs.scale(14) : null,
                top: rs.scale(16),
                bottom: rs.scale(16),
                width: width * 0.46,
                child: Column(
                  crossAxisAlignment: isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                  children: [
                    // Acronym Node
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: subject.color.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(rs.scale(10)),
                      ),
                      child: Text(
                        subject.displayAcronym,
                        style: GoogleFonts.inter(
                          fontSize: rs.font(10.5),
                          fontWeight: FontWeight.w800,
                          color: subject.color,
                        ),
                      ),
                    ),
                    SizedBox(height: rs.height(8)),
                    // Time indicator
                    Text(
                      slot.formatTimeRange(widget.timeFormatProvider.timeFormat),
                      style: GoogleFonts.inter(
                        fontSize: rs.font(11),
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: isLeft ? TextAlign.left : TextAlign.right,
                    ),
                    SizedBox(height: rs.height(4)),
                    // Subject Name
                    Text(
                      subject.name,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(15),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: isDarkMode ? Colors.white : Colors.black87,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: isLeft ? TextAlign.left : TextAlign.right,
                    ),
                    if (hasRoom) ...[
                      SizedBox(height: rs.height(4)),
                      Text(
                        'Rm $room',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(10.5),
                          color: isDarkMode ? Colors.white54 : Colors.black45,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: isLeft ? TextAlign.left : TextAlign.right,
                      ),
                    ],
                    const Spacer(),
                    // Hint to tap
                    Container(
                      padding: rs.insetsSymmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(rs.scale(8)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLeft)
                            Icon(Icons.arrow_back_rounded, size: rs.scale(11), color: isDarkMode ? Colors.white54 : Colors.black54),
                          if (isLeft) SizedBox(width: rs.width(3)),
                          Text(
                            'Tap',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(10),
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          if (!isLeft) SizedBox(width: rs.width(3)),
                          if (!isLeft)
                            Icon(Icons.arrow_forward_rounded, size: rs.scale(11), color: isDarkMode ? Colors.white54 : Colors.black54),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Active Front Card Face ---
  Widget _buildActiveCardFace({
    required Subject subject,
    required TimeSlot slot,
    required Attendance? attendance,
    required bool isLocked,
    required Offset dragOffset,
    required double width,
    required double height,
    required int periodNumber,
    required int totalPeriods,
  }) {
    final rs = widget.rs;
    final isDarkMode = widget.isDarkMode;

    // Effective room / block
    final effectiveLocId = subject.getEffectiveLocationId(slot);
    final locConfig = effectiveLocId != null ? widget.locationById[effectiveLocId] : null;
    final room = subject.getEffectiveRoom(slot) ?? locConfig?.name;
    final block = subject.getEffectiveBlock(slot) ?? locConfig?.block;
    final hasRoom = room != null && room.isNotEmpty;

    // Real-time drag stamp opacity (scaled to 50px threshold)
    final double rightSwipeRatio = (dragOffset.dx / 50).clamp(0.0, 1.0);
    final double leftSwipeRatio = (-dragOffset.dx / 50).clamp(0.0, 1.0);
    final double upSwipeRatio = (-dragOffset.dy / 45).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF141416).withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(rs.scale(26)),
            border: Border.all(
              color: rightSwipeRatio > 0.25
                  ? const Color(0xFF10B981).withValues(alpha: 0.85)
                  : (leftSwipeRatio > 0.25
                      ? const Color(0xFFEF4444).withValues(alpha: 0.85)
                      : (upSwipeRatio > 0.25
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.85)
                          : (isDarkMode ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.10)))),
              width: (rightSwipeRatio > 0.25 || leftSwipeRatio > 0.25 || upSwipeRatio > 0.25) ? 1.5 : 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: subject.color.withValues(alpha: isDarkMode ? 0.22 : 0.14),
                blurRadius: 36,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Card Content
              Padding(
                padding: rs.insetsAll(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar: Acronym & Period Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: subject.color.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                subject.displayAcronym,
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.w800,
                                  color: subject.color,
                                ),
                              ),
                            ),
                            SizedBox(width: rs.width(8)),
                            Text(
                              slot.formatTimeRange(widget.timeFormatProvider.timeFormat),
                              style: GoogleFonts.inter(
                                fontSize: rs.font(12.5),
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: rs.insetsSymmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(rs.scale(12)),
                          ),
                          child: Text(
                            '$periodNumber of $totalPeriods',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(10.5),
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: rs.height(16)),

                    // Subject Full Name (Image 1 style)
                    Text(
                      subject.name,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(23),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: isDarkMode ? Colors.white : Colors.black87,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: rs.height(6)),

                    // Location / Room details
                    if (hasRoom)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: rs.scale(13),
                            color: isDarkMode ? Colors.white54 : Colors.black45,
                          ),
                          SizedBox(width: rs.width(4)),
                          Text(
                            'Room $room${block != null && block.isNotEmpty ? " • $block" : ""}',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(12),
                              color: isDarkMode ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),

                    if (isLocked)
                      Padding(
                        padding: EdgeInsets.only(top: rs.height(6)),
                        child: Text(
                          '🔒 Locked by manual count update',
                          style: GoogleFonts.inter(fontSize: rs.font(11), color: const Color(0xFFF59E0B)),
                        ),
                      ),

                    const Spacer(),

                    // Current Marked Status Pill (if already decided)
                    if (attendance != null)
                      Container(
                        margin: EdgeInsets.only(bottom: rs.height(12)),
                        padding: rs.insetsSymmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(rs.scale(10)),
                        ),
                        child: Text(
                          'Currently marked: ${attendance.status == AttendanceStatus.attended ? "Attended ✓" : (attendance.status == AttendanceStatus.absent || attendance.status == AttendanceStatus.plannedAbsent ? "Missed ✕" : "Cancelled ⊘")}',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(11),
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),

                    // Directional Swipe Guidance (Image 1 style)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.arrow_back_rounded, size: rs.scale(13), color: const Color(0xFFEF4444)),
                            SizedBox(width: rs.width(4)),
                            Text(
                              'Missed',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.keyboard_arrow_up_rounded, size: rs.scale(14), color: const Color(0xFFF59E0B)),
                            Text(
                              'Cancelled',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(10),
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              'Attended',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                            SizedBox(width: rs.width(4)),
                            Icon(Icons.arrow_forward_rounded, size: rs.scale(13), color: const Color(0xFF10B981)),
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: rs.height(12)),

                    // Bottom 3 Interactive Action Buttons (for 1-tap marking)
                    Row(
                      children: [
                        Expanded(
                          child: _buildCardActionBtn(
                            title: 'Missed',
                            icon: Icons.close_rounded,
                            color: const Color(0xFFEF4444),
                            onTap: () => _triggerAction(AttendanceStatus.absent),
                            rs: rs,
                            isDarkMode: isDarkMode,
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: _buildCardActionBtn(
                            title: 'Cancel',
                            icon: Icons.pause_rounded,
                            color: const Color(0xFFF59E0B),
                            onTap: () => _triggerAction(AttendanceStatus.cancelled),
                            rs: rs,
                            isDarkMode: isDarkMode,
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: _buildCardActionBtn(
                            title: 'Attend',
                            icon: Icons.check_rounded,
                            color: const Color(0xFF10B981),
                            onTap: () => _triggerAction(AttendanceStatus.attended),
                            rs: rs,
                            isDarkMode: isDarkMode,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Dynamic Swipe Feedback Stamps
              if (rightSwipeRatio > 0.05)
                Positioned(
                  top: rs.height(20),
                  right: rs.width(18),
                  child: Opacity(
                    opacity: rightSwipeRatio,
                    child: Container(
                      padding: rs.insetsSymmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(rs.scale(12)),
                      ),
                      child: Text(
                        'ATTENDED ✓',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(11.5),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),

              if (leftSwipeRatio > 0.05)
                Positioned(
                  top: rs.height(20),
                  left: rs.width(18),
                  child: Opacity(
                    opacity: leftSwipeRatio,
                    child: Container(
                      padding: rs.insetsSymmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(rs.scale(12)),
                      ),
                      child: Text(
                        'MISSED ✕',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(11.5),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),

              if (upSwipeRatio > 0.05 && dragOffset.dx.abs() < 50)
                Positioned(
                  top: rs.height(20),
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Opacity(
                      opacity: upSwipeRatio,
                      child: Container(
                        padding: rs.insetsSymmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(rs.scale(12)),
                        ),
                        child: Text(
                          'CANCELLED ⊘',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(11.5),
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardActionBtn({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required ResponsiveScale rs,
    required bool isDarkMode,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(rs.scale(14)),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: rs.height(9)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDarkMode ? 0.14 : 0.09),
            borderRadius: BorderRadius.circular(rs.scale(14)),
            border: Border.all(
              color: color.withValues(alpha: isDarkMode ? 0.35 : 0.25),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: rs.scale(13), color: color),
              SizedBox(width: rs.width(4)),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: rs.font(11),
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Accordion Peek Window (Peek through entire day & summon any card - Image 3)
// ---------------------------------------------------------------------------

class AccordionPeekWindow extends StatelessWidget {
  final List<Subject> displayClasses;
  final int activeCardIndex;
  final AttendanceProvider attendanceProvider;
  final TimeFormatProvider timeFormatProvider;
  final DateTime targetDate;
  final Map<String, LocationConfig> locationById;
  final bool isExpanded;
  final bool isDarkMode;
  final ResponsiveScale rs;
  final VoidCallback onToggleExpand;
  final ValueChanged<int> onSummonPeriod;

  const AccordionPeekWindow({
    super.key,
    required this.displayClasses,
    required this.activeCardIndex,
    required this.attendanceProvider,
    required this.timeFormatProvider,
    required this.targetDate,
    required this.locationById,
    required this.isExpanded,
    required this.isDarkMode,
    required this.rs,
    required this.onToggleExpand,
    required this.onSummonPeriod,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          margin: rs.insetsSymmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF141416).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(rs.scale(22)),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.10),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Tab / Peek Handle (Image 3 style)
              InkWell(
                onTap: onToggleExpand,
                borderRadius: BorderRadius.circular(rs.scale(22)),
                child: Padding(
                  padding: rs.insetsSymmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white12 : Colors.black12,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                          size: rs.scale(15),
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      SizedBox(width: rs.width(10)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isExpanded ? 'DAY TIMETABLE' : 'PEEK ALL PERIODS',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            if (!isExpanded)
                              Text(
                                '${displayClasses.length} classes scheduled today • Tap to summon',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(10.5),
                                  color: isDarkMode ? Colors.white54 : Colors.black54,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: rs.insetsSymmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(rs.scale(12)),
                        ),
                        child: Text(
                          '${activeCardIndex + 1}/${displayClasses.length}',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(10.5),
                            fontWeight: FontWeight.w700,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Expanded Accordion List
              if (isExpanded)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: rs.height(240)),
                  child: ListView.separated(
                    padding: rs.insetsSymmetric(horizontal: 14, vertical: 6),
                    shrinkWrap: true,
                    itemCount: displayClasses.length,
                    separatorBuilder: (context, index) => SizedBox(height: rs.height(6)),
                    itemBuilder: (context, idx) {
                      final subject = displayClasses[idx];
                      final slot = subject.schedule.first;
                      final slotKey = slot.slotKey;
                      final isCurrent = idx == activeCardIndex;

                      final attendance = attendanceProvider.getAttendanceForSubjectOnDate(
                        subject.id,
                        targetDate,
                        slotKey: slotKey,
                      );

                      final status = attendance?.status;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onSummonPeriod(idx),
                          borderRadius: BorderRadius.circular(rs.scale(14)),
                          child: Container(
                            padding: rs.insetsSymmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? (isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08))
                                  : (isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                              borderRadius: BorderRadius.circular(rs.scale(14)),
                              border: Border.all(
                                color: isCurrent
                                    ? (isDarkMode ? Colors.white38 : Colors.black38)
                                    : (isDarkMode ? Colors.white10 : Colors.black12),
                                width: isCurrent ? 1.2 : 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Acronym node
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: subject.color.withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    subject.displayAcronym,
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(9.5),
                                      fontWeight: FontWeight.w800,
                                      color: subject.color,
                                    ),
                                  ),
                                ),
                                SizedBox(width: rs.width(8)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        subject.name,
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(12.5),
                                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                                          color: isDarkMode ? Colors.white : Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        slot.formatTimeRange(timeFormatProvider.timeFormat),
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(10.5),
                                          color: isDarkMode ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: rs.width(6)),
                                // Status chip
                                if (status != null)
                                  Container(
                                    padding: rs.insetsSymmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: status == AttendanceStatus.attended
                                          ? const Color(0xFF10B981).withValues(alpha: 0.16)
                                          : (status == AttendanceStatus.absent || status == AttendanceStatus.plannedAbsent
                                              ? const Color(0xFFEF4444).withValues(alpha: 0.16)
                                              : const Color(0xFFF59E0B).withValues(alpha: 0.16)),
                                      borderRadius: BorderRadius.circular(rs.scale(10)),
                                    ),
                                    child: Text(
                                      status == AttendanceStatus.attended
                                          ? 'Attended'
                                          : (status == AttendanceStatus.absent || status == AttendanceStatus.plannedAbsent ? 'Missed' : 'Cancelled'),
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(10),
                                        fontWeight: FontWeight.w700,
                                        color: status == AttendanceStatus.attended
                                            ? const Color(0xFF10B981)
                                            : (status == AttendanceStatus.absent || status == AttendanceStatus.plannedAbsent
                                                ? const Color(0xFFEF4444)
                                                : const Color(0xFFF59E0B)),
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    'Summon >',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(10.5),
                                      fontWeight: FontWeight.w600,
                                      color: isDarkMode ? Colors.white54 : Colors.black45,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day Over / Completed Summary View ("Receipt" List & Circular Progress - Image 2)
// ---------------------------------------------------------------------------

class DayOverSummaryView extends StatelessWidget {
  final DateTime targetDate;
  final List<Subject> displayClasses;
  final AttendanceProvider attendanceProvider;
  final SubjectProvider subjectProvider;
  final TimeFormatProvider timeFormatProvider;
  final Map<String, LocationConfig> locationById;
  final double overallPercentage;
  final int bunkBuffer;
  final bool isSafe;
  final int markedCount;
  final int attendedCount;
  final int absentCount;
  final int cancelledCount;
  final bool isToday;
  final bool isDarkMode;
  final ResponsiveScale rs;
  final bool semesterEnded;
  final bool isFutureDate;
  final VoidCallback onRevisitDeck;
  final Function(Subject, TimeSlot, String?, Attendance?) onModifyItem;
  final VoidCallback onMarkDayHoliday;
  final VoidCallback onMarkDayAbsent;
  final VoidCallback onMarkDayPresent;

  const DayOverSummaryView({
    super.key,
    required this.targetDate,
    required this.displayClasses,
    required this.attendanceProvider,
    required this.subjectProvider,
    required this.timeFormatProvider,
    required this.locationById,
    required this.overallPercentage,
    required this.bunkBuffer,
    required this.isSafe,
    required this.markedCount,
    required this.attendedCount,
    required this.absentCount,
    required this.cancelledCount,
    required this.isToday,
    required this.isDarkMode,
    required this.rs,
    required this.semesterEnded,
    required this.isFutureDate,
    required this.onRevisitDeck,
    required this.onModifyItem,
    required this.onMarkDayHoliday,
    required this.onMarkDayAbsent,
    required this.onMarkDayPresent,
  });

  Widget _buildQuickDayActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(rs.scale(16)),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: rs.height(9)),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(rs.scale(16)),
          border: Border.all(
            color: isDarkMode ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: rs.scale(14), color: isDarkMode ? Colors.white : Colors.black87),
            SizedBox(width: rs.width(5)),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: rs.font(11.5),
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool allDone = markedCount == displayClasses.length;

    return ListView(
      padding: EdgeInsets.fromLTRB(rs.scale(16), rs.scale(8), rs.scale(16), rs.scale(120)),
      children: [
        // Victory Header (Image 2 style)
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allDone ? "Nice work,\nyou're done!" : "Day Summary",
                    style: GoogleFonts.inter(
                      fontSize: rs.font(24),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: rs.height(4)),
                  Text(
                    allDone ? "Today's log is complete" : "$markedCount of ${displayClasses.length} classes logged",
                    style: GoogleFonts.inter(
                      fontSize: rs.font(12.5),
                      color: isDarkMode ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: rs.scale(42),
              height: rs.scale(42),
              decoration: BoxDecoration(
                color: (allDone ? const Color(0xFF10B981) : Colors.white).withValues(alpha: isDarkMode ? 0.16 : 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: (allDone ? const Color(0xFF10B981) : Colors.white).withValues(alpha: 0.35),
                  width: 1.0,
                ),
              ),
              child: Icon(
                allDone ? Icons.check_circle_outline_rounded : Icons.pie_chart_outline_rounded,
                size: rs.scale(22),
                color: allDone ? const Color(0xFF10B981) : (isDarkMode ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),

        SizedBox(height: rs.height(16)),

        // Daily Summary & Victory Card (Image 2 style)
        ClipRRect(
          borderRadius: BorderRadius.circular(rs.scale(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: rs.insetsAll(18),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF141416).withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(rs.scale(24)),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  // Circular Progress Donut Ring (Image 2 style)
                  SizedBox(
                    width: rs.scale(82),
                    height: rs.scale(82),
                    child: CustomPaint(
                      painter: CircularAttendanceRingPainter(
                        percentage: overallPercentage / 100.0,
                        ringColor: isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        trackColor: isDarkMode ? Colors.white12 : Colors.black12,
                        strokeWidth: 8.0,
                      ),
                      child: Center(
                        child: Text(
                          '${overallPercentage.toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(18),
                            fontWeight: FontWeight.w800,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rs.width(16)),
                  // Metrics & Status Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall Attendance',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(12.5),
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        SizedBox(height: rs.height(4)),
                        Row(
                          children: [
                            Container(
                              padding: rs.insetsSymmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                                    .withValues(alpha: isDarkMode ? 0.20 : 0.12),
                                borderRadius: BorderRadius.circular(rs.scale(10)),
                              ),
                              child: Text(
                                isSafe ? 'Safe • On Track' : 'Attention Needed',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.w700,
                                  color: isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: rs.height(8)),
                        Row(
                          children: [
                            Text(
                              '● $markedCount/${displayClasses.length} Marked',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                color: isDarkMode ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            SizedBox(width: rs.width(10)),
                            Text(
                              isSafe ? 'Buffer: $bunkBuffer class${bunkBuffer == 1 ? "" : "es"}' : 'Below target',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                fontWeight: FontWeight.w600,
                                color: isSafe ? Colors.white70 : const Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Quick Day Actions
        if (!semesterEnded && !isFutureDate) ...[
          SizedBox(height: rs.height(12)),
          Row(
            children: [
              Expanded(
                child: _buildQuickDayActionBtn(
                  icon: Icons.pause_rounded,
                  label: 'Holiday',
                  onTap: onMarkDayHoliday,
                ),
              ),
              SizedBox(width: rs.width(8)),
              Expanded(
                child: _buildQuickDayActionBtn(
                  icon: Icons.remove_rounded,
                  label: 'Skip Day',
                  onTap: onMarkDayAbsent,
                ),
              ),
              SizedBox(width: rs.width(8)),
              Expanded(
                child: _buildQuickDayActionBtn(
                  icon: Icons.check_rounded,
                  label: 'Present',
                  onTap: onMarkDayPresent,
                ),
              ),
            ],
          ),
        ],

        SizedBox(height: rs.height(20)),

        // "Receipt" List Header (Image 2 style)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receipt List',
                  style: GoogleFonts.inter(
                    fontSize: rs.font(16),
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  "Today's Decisions • Tap to inspect or modify",
                  style: GoogleFonts.inter(
                    fontSize: rs.font(11.5),
                    color: isDarkMode ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.style_rounded),
              tooltip: 'Switch back to Card Deck',
              onPressed: onRevisitDeck,
            ),
          ],
        ),

        SizedBox(height: rs.height(10)),

        // "Receipt" Items List
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayClasses.length,
          separatorBuilder: (context, index) => SizedBox(height: rs.height(8)),
          itemBuilder: (context, idx) {
            final subject = displayClasses[idx];
            final slot = subject.schedule.first;
            final slotKey = slot.slotKey;

            final attendance = attendanceProvider.getAttendanceForSubjectOnDate(
              subject.id,
              targetDate,
              slotKey: slotKey,
            );

            final status = attendance?.status;

            // Room details
            final effectiveLocId = subject.getEffectiveLocationId(slot);
            final locConfig = effectiveLocId != null ? locationById[effectiveLocId] : null;
            final room = subject.getEffectiveRoom(slot) ?? locConfig?.name;
            final hasRoom = room != null && room.isNotEmpty;

            final Color statusColor;
            final String statusLabel;
            final IconData statusIcon;

            if (status == AttendanceStatus.attended) {
              statusColor = const Color(0xFF10B981);
              statusLabel = 'Attended';
              statusIcon = Icons.check_rounded;
            } else if (status == AttendanceStatus.absent || status == AttendanceStatus.plannedAbsent) {
              statusColor = const Color(0xFFEF4444);
              statusLabel = 'Missed';
              statusIcon = Icons.close_rounded;
            } else if (status == AttendanceStatus.cancelled) {
              statusColor = const Color(0xFFF59E0B);
              statusLabel = 'Cancelled';
              statusIcon = Icons.pause_rounded;
            } else {
              statusColor = isDarkMode ? Colors.white54 : Colors.black45;
              statusLabel = 'Awaiting';
              statusIcon = Icons.radio_button_unchecked_rounded;
            }

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onModifyItem(subject, slot, slotKey, attendance),
                borderRadius: BorderRadius.circular(rs.scale(18)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(rs.scale(18)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: rs.insetsSymmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF141416).withValues(alpha: 0.75)
                            : Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(rs.scale(18)),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Acronym Node
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: subject.color.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              subject.displayAcronym,
                              style: GoogleFonts.inter(
                                fontSize: rs.font(10.5),
                                fontWeight: FontWeight.w800,
                                color: subject.color,
                              ),
                            ),
                          ),
                          SizedBox(width: rs.width(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subject.name,
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(14),
                                    fontWeight: FontWeight.w700,
                                    color: isDarkMode ? Colors.white : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: rs.height(2)),
                                Text(
                                  '${slot.formatTimeRange(timeFormatProvider.timeFormat)}${hasRoom ? " • Room $room" : ""}',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(11.5),
                                    color: isDarkMode ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: rs.width(8)),
                          // Status Badge
                          Container(
                            padding: rs.insetsSymmetric(horizontal: 9, vertical: 4.5),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: isDarkMode ? 0.18 : 0.12),
                              borderRadius: BorderRadius.circular(rs.scale(12)),
                              border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: rs.scale(12), color: statusColor),
                                SizedBox(width: rs.width(4)),
                                Text(
                                  statusLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(11),
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: rs.width(6)),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: rs.scale(16),
                            color: isDarkMode ? Colors.white38 : Colors.black26,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        SizedBox(height: rs.height(20)),

        // Revisit Stacked Cards Button
        OutlinedButton.icon(
          onPressed: onRevisitDeck,
          icon: const Icon(Icons.style_rounded, size: 16),
          label: const Text('Reopen Cards Deck'),
          style: OutlinedButton.styleFrom(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rs.scale(18))),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Circular Attendance Ring Painter
// ---------------------------------------------------------------------------

class CircularAttendanceRingPainter extends CustomPainter {
  final double percentage; // 0.0 to 1.0
  final Color ringColor;
  final Color trackColor;
  final double strokeWidth;

  CircularAttendanceRingPainter({
    required this.percentage,
    required this.ringColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    // Active Arc
    final arcPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * percentage.clamp(0.0, 1.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CircularAttendanceRingPainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.trackColor != trackColor;
  }
}
