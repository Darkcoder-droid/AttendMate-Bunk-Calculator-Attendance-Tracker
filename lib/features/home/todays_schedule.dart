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
          // Current Week Day Badges (Matching Screenshot)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: rs.width(10)),
            child: Row(
              children: List.generate(_dates.length, (index) {
                final date = _dates[index];
                final isSelected = index == _currentIndex;
                final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
                final hasClasses = subjectProvider.getClassesForDate(date).isNotEmpty;
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
                      borderRadius: BorderRadius.circular(rs.scale(22)),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(vertical: rs.height(6)),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDarkMode ? Colors.white : Colors.black)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(rs.scale(22)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              weekdayLetter,
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11),
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? (isDarkMode ? Colors.black : Colors.white)
                                    : (isDarkMode
                                        ? Colors.white.withValues(alpha: 0.50)
                                        : Colors.black45),
                              ),
                            ),
                            SizedBox(height: rs.height(3)),
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
                            SizedBox(height: rs.height(3)),
                            // Subtle class dot indicator (screenshot style)
                            Container(
                              width: 3.5,
                              height: 3.5,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isDarkMode ? Colors.black : Colors.white)
                                    : (hasClasses ? (isDarkMode ? Colors.white38 : Colors.black26) : Colors.transparent),
                                shape: BoxShape.circle,
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
            // 1. Unified Top Header Bar (Metrics + Perfectly Symmetrical Period Stepper)
            _buildUnifiedTopBar(
              markedCount: markedCount,
              totalClasses: displayClasses.length,
              overallPercentage: overallPercentage,
              isSafe: isSafe,
              isDarkMode: isDarkMode,
              rs: rs,
              allMarked: allMarked,
              activeIndex: _activeCardIndex,
            ),

            // 2. Main Stage: 3D Stacked Deck or Completed Summary with Smooth Animated Switcher
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 520),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final isSummary = child.key == const ValueKey('summary_view');
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: isSummary ? 0.95 : 1.02, end: 1.0).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                      ),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0.0, isSummary ? 0.04 : -0.04),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    ),
                  );
                },
                child: (_viewMode == ScheduleViewMode.receipt)
                    ? DayOverSummaryView(
                        key: const ValueKey('summary_view'),
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
                            _activeCardIndex = 0;
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
                        key: const ValueKey('deck_view'),
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
                          if (mounted) {
                            setState(() {});
                          }

                          // Only show automatic summary after the person has swiped through the LAST card!
                          final isLastCardInDeck = index >= displayClasses.length - 1;
                          if (isLastCardInDeck) {
                            Future.delayed(const Duration(milliseconds: 320), () {
                              if (mounted) {
                                setState(() {
                                  _viewMode = ScheduleViewMode.receipt;
                                });
                              }
                            });
                          } else {
                            if (mounted) {
                              setState(() {
                                _activeCardIndex = index + 1;
                              });
                            }
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
            ),
          ],
        ),

        // Dimming Backdrop when Peek Drawer is Expanded
        if (_viewMode == ScheduleViewMode.deck)
          IgnorePointer(
            ignoring: !_isAccordionExpanded,
            child: AnimatedOpacity(
              opacity: _isAccordionExpanded ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _isAccordionExpanded = false;
                  });
                },
                child: Container(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
                ),
              ),
            ),
          ),

        // Floating Structured Peek Drawer (Positioned in Stack above bottom dock)
        if (_viewMode == ScheduleViewMode.deck)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: _isAccordionExpanded ? rs.width(8) : rs.width(14),
            right: _isAccordionExpanded ? rs.width(8) : rs.width(14),
            top: _isAccordionExpanded ? rs.scale(12) : null,
            bottom: _isAccordionExpanded ? rs.scale(80) : rs.scale(88),
            height: _isAccordionExpanded ? null : null,
            child: AccordionPeekWindow(
              displayClasses: displayClasses,
              activeCardIndex: _activeCardIndex,
              attendanceProvider: attendanceProvider,
              subjectProvider: subjectProvider,
              timeFormatProvider: timeFormatProvider,
              targetDate: widget.targetDate,
              locationById: widget.locationById,
              isExpanded: _isAccordionExpanded,
              isDarkMode: isDarkMode,
              rs: rs,
              semesterEnded: semesterEnded,
              isFutureDate: isFutureDate,
              onToggleExpand: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isAccordionExpanded = !_isAccordionExpanded;
                });
              },
              onSummonPeriod: (idx) {
                _summonCard(idx);
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
            ),
          ),
      ],
    );
  }

  // --- Unified Top Header Bar (Metrics + Symmetrical Stepper Navigation) ---
  Widget _buildUnifiedTopBar({
    required int markedCount,
    required int totalClasses,
    required double overallPercentage,
    required bool isSafe,
    required bool isDarkMode,
    required ResponsiveScale rs,
    required bool allMarked,
    required int activeIndex,
  }) {
    return Container(
      margin: rs.insetsSymmetric(horizontal: 16, vertical: 4),
      padding: rs.insetsSymmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(rs.scale(18)),
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
          // Row 1: Metrics & Overall Attendance Pill & View Switchers (matching Concept 3 header)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: "Active Day" Hero Title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active\nDay',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(18),
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.5,
                      color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),

              // Right: Overall Attendance & View Switcher
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${overallPercentage.toStringAsFixed(1)}%',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(18),
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: isSafe
                              ? (isDarkMode ? Colors.white : const Color(0xFF0F172A))
                              : const Color(0xFFEF4444),
                        ),
                      ),
                      Text(
                        'Overall',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(11),
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: rs.width(8)),
                  // Peek Accordion Drawer Toggle
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _isAccordionExpanded = !_isAccordionExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(rs.scale(10)),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _isAccordionExpanded
                            ? (isDarkMode ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.12))
                            : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
                        borderRadius: BorderRadius.circular(rs.scale(10)),
                      ),
                      child: Icon(
                        Icons.view_agenda_rounded,
                        size: rs.scale(15),
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  SizedBox(width: rs.width(4)),
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
                    borderRadius: BorderRadius.circular(rs.scale(10)),
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

          // Row 2: Perfectly Centered & Symmetrical Period Navigation (in Deck mode)
          if (_viewMode == ScheduleViewMode.deck) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: rs.height(6)),
              child: Divider(
                height: 1,
                thickness: 0.6,
                color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Perfectly Symmetrical 30x30 Prev Button
                InkWell(
                  onTap: activeIndex > 0
                      ? () {
                          HapticFeedback.selectionClick();
                          _summonCard(activeIndex - 1);
                        }
                      : null,
                  borderRadius: BorderRadius.circular(rs.scale(8)),
                  child: Container(
                    width: rs.scale(30),
                    height: rs.scale(30),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: activeIndex > 0
                          ? (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(rs.scale(8)),
                      border: Border.all(
                        color: activeIndex > 0
                            ? (isDarkMode ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.10))
                            : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: rs.scale(18),
                      color: activeIndex > 0
                          ? (isDarkMode ? Colors.white : Colors.black87)
                          : (isDarkMode ? Colors.white24 : Colors.black26),
                    ),
                  ),
                ),

                // Mathematically Centered Period Title & Interactive Dots
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Period ${activeIndex + 1} of $totalClasses',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(11.5),
                          fontWeight: FontWeight.w700,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      SizedBox(height: rs.height(4)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(totalClasses, (dotIdx) {
                          final isCurrent = dotIdx == activeIndex;
                          return InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _summonCard(dotIdx);
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 2),
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
                ),

                // Perfectly Symmetrical 30x30 Next Button
                InkWell(
                  onTap: activeIndex < totalClasses - 1
                      ? () {
                          HapticFeedback.selectionClick();
                          _summonCard(activeIndex + 1);
                        }
                      : null,
                  borderRadius: BorderRadius.circular(rs.scale(8)),
                  child: Container(
                    width: rs.scale(30),
                    height: rs.scale(30),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: activeIndex < totalClasses - 1
                          ? (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(rs.scale(8)),
                      border: Border.all(
                        color: activeIndex < totalClasses - 1
                            ? (isDarkMode ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.10))
                            : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: rs.scale(18),
                      color: activeIndex < totalClasses - 1
                          ? (isDarkMode ? Colors.white : Colors.black87)
                          : (isDarkMode ? Colors.white24 : Colors.black26),
                    ),
                  ),
                ),
              ],
            ),
          ],
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

  // Dedicated Dismissal Animation (Card flies off smoothly without ever teleporting back)
  late AnimationController _dismissAnimController;
  late Animation<Offset> _dismissOffsetAnim;
  late Animation<double> _dismissRotAnim;
  late Animation<double> _dismissOpacityAnim;
  Subject? _dismissingSubject;
  TimeSlot? _dismissingSlot;
  int? _dismissingIndex;
  AttendanceStatus? _dismissingStatus;

  // Spring Snap-back Animation when drag is released below threshold
  late AnimationController _snapAnimController;
  late Animation<Offset> _snapOffsetAnim;
  late Animation<double> _snapRotAnim;

  // Carousel deck transition controller for smooth index navigation
  late AnimationController _indexAnimController;
  late Animation<double> _indexAnimation;
  double _fromIndex = 0.0;
  double _toIndex = 0.0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.activeIndex.toDouble();
    _toIndex = widget.activeIndex.toDouble();

    // Dismissal animation
    _dismissAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 270),
    );
    _dismissOffsetAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _dismissAnimController, curve: Curves.easeOutCubic),
    );
    _dismissRotAnim = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _dismissAnimController, curve: Curves.easeOutCubic),
    );
    _dismissOpacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _dismissAnimController, curve: Curves.easeInCubic),
    );

    // Snap-back animation
    _snapAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _snapOffsetAnim = Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _snapAnimController, curve: Curves.easeOutCubic),
    );
    _snapRotAnim = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _snapAnimController, curve: Curves.easeOutCubic),
    );

    // Deck index transition
    _indexAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
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
    _dismissAnimController.dispose();
    _snapAnimController.dispose();
    _indexAnimController.dispose();
    super.dispose();
  }

  double get _currentAnimatedIndex {
    if (!_indexAnimController.isAnimating) return _toIndex;
    return lerpDouble(_fromIndex, _toIndex, _indexAnimation.value) ?? _toIndex;
  }

  void _triggerAction(AttendanceStatus status, {Offset? initialVelocity}) {
    if (widget.semesterEnded) return;
    if (_dismissAnimController.isAnimating) return;

    final dismissIdx = widget.activeIndex;
    if (dismissIdx < 0 || dismissIdx >= widget.displayClasses.length) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final currentSub = widget.displayClasses[dismissIdx];
    final currentSlot = currentSub.schedule.first;

    _dismissingSubject = currentSub;
    _dismissingSlot = currentSlot;
    _dismissingIndex = dismissIdx;
    _dismissingStatus = status;

    Offset targetFly;
    double targetRot = 0;

    switch (status) {
      case AttendanceStatus.attended:
        targetFly = Offset(screenWidth * 1.55, _dragOffset.dy * 0.4);
        targetRot = 0.28;
        break;
      case AttendanceStatus.absent:
      case AttendanceStatus.plannedAbsent:
        targetFly = Offset(-screenWidth * 1.55, _dragOffset.dy * 0.4);
        targetRot = -0.28;
        break;
      case AttendanceStatus.cancelled:
        final bool flyUp = _dragOffset.dy < -15;
        targetFly = Offset(_dragOffset.dx * 0.3, flyUp ? -screenHeight * 1.30 : screenHeight * 1.30);
        targetRot = 0.0;
        break;
    }

    HapticFeedback.mediumImpact();

    final startOffset = _dragOffset;
    final startRot = (_dragOffset.dx / (screenWidth * 0.75)) * 0.28;

    _dismissOffsetAnim = Tween<Offset>(begin: startOffset, end: targetFly).animate(
      CurvedAnimation(parent: _dismissAnimController, curve: Curves.easeOutCubic),
    );
    _dismissRotAnim = Tween<double>(begin: startRot, end: targetRot).animate(
      CurvedAnimation(parent: _dismissAnimController, curve: Curves.easeOutCubic),
    );
    _dismissOpacityAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _dismissAnimController, curve: const Interval(0.2, 1.0, curve: Curves.easeInCubic)),
    );

    setState(() {
      _dragOffset = Offset.zero;
    });

    // Notify parent immediately so deck smoothly promotes the next card underneath
    widget.onCardSwiped(dismissIdx, status);

    _dismissAnimController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _dismissingSubject = null;
          _dismissingSlot = null;
          _dismissingIndex = null;
          _dismissingStatus = null;
        });
        _dismissAnimController.reset();
      }
    });
  }

  void _resetPosition() {
    if (_dragOffset == Offset.zero) return;
    final screenWidth = MediaQuery.of(context).size.width;

    HapticFeedback.selectionClick();

    _snapOffsetAnim = Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _snapAnimController, curve: Curves.easeOutCubic),
    );
    _snapRotAnim = Tween<double>(
      begin: (_dragOffset.dx / (screenWidth * 0.75)) * 0.28,
      end: 0.0,
    ).animate(
      CurvedAnimation(parent: _snapAnimController, curve: Curves.easeOutCubic),
    );

    _snapAnimController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = Offset.zero;
        });
        _snapAnimController.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.displayClasses.length;
    if (count == 0) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final activeIndex = widget.activeIndex.clamp(0, count - 1);
    final swipeProvider = Provider.of<SwipeActionProvider>(context);

    // Modern glass card proportions
    final centerCardWidth = (screenWidth * 0.76).clamp(265.0, 310.0);
    final centerCardHeight = (widget.rs.height(375)).clamp(345.0, 415.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final bottomOcclusion = widget.rs.scale(136);
        final visibleHeight = (totalHeight - bottomOcclusion).clamp(0.0, totalHeight);
        final cardBoxHeight = centerCardHeight + widget.rs.height(28);
        final topOffset = ((visibleHeight - cardBoxHeight) / 2).clamp(0.0, totalHeight - cardBoxHeight);

        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: topOffset,
              width: screenWidth,
              height: cardBoxHeight,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _dismissAnimController,
                  _snapAnimController,
                  _indexAnimController,
                ]),
                builder: (context, _) {
                  final currentAnimatedIndex = _currentAnimatedIndex;

                  // Active drag offset (either live finger drag or smooth snap-back)
                  final currentDrag = _snapAnimController.isAnimating
                      ? _snapOffsetAnim.value
                      : _dragOffset;
                  final dragDistance = currentDrag.distance;
                  final dragProgress = (dragDistance / 100.0).clamp(0.0, 1.0);

                  // Collect visible card indices in the deck (active card + upcoming cards underneath)
                  final visibleIndices = <int>[];
                  for (int i = 0; i < count; i++) {
                    if (i == _dismissingIndex) continue;
                    final d = i - currentAnimatedIndex;
                    // Only active card and up to 2 upcoming cards directly underneath in stack
                    if (d >= -0.2 && d <= 2.4) {
                      visibleIndices.add(i);
                    }
                  }

                  // Sort back-to-front: deepest upcoming card paints first, active card on top
                  visibleIndices.sort((a, b) {
                    final distA = (a - currentAnimatedIndex);
                    final distB = (b - currentAnimatedIndex);
                    return distB.compareTo(distA);
                  });

                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // Subordinate deck cards and active card
                      ...visibleIndices.map((i) {
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

                        // True vertical deck stack: NO side wings, pure centered depth stack
                        final double baseDx = 0.0;
                        final double baseDy = (d * 14.0).clamp(0.0, 36.0);
                        final double baseRot = 0.0;
                        final double baseScale = (1.0 - (d * 0.06)).clamp(0.84, 1.0);
                        final double baseOpacity = (1.0 - (d * 0.22)).clamp(0.35, 1.0);

                        Offset cardOffset = Offset(baseDx, baseDy);
                        double cardRot = baseRot;
                        double cardScale = baseScale;
                        double cardOpacity = baseOpacity;

                        if (isCurrentActive) {
                          final double liveRot = _snapAnimController.isAnimating
                              ? _snapRotAnim.value
                              : (currentDrag.dx / (screenWidth * 0.75)) * 0.28;
                          cardOffset = Offset(baseDx + currentDrag.dx, baseDy + currentDrag.dy);
                          cardRot = baseRot + liveRot;
                          cardOpacity = 1.0;
                        } else {
                          // Tactile dynamic card rise: next card in deck elevates as top card is pulled away
                          if (d > 0 && d <= 1.2) {
                            cardScale = lerpDouble(baseScale, 1.0, dragProgress * 0.65) ?? baseScale;
                            cardOffset = Offset(
                              0.0,
                              lerpDouble(baseDy, 0.0, dragProgress * 0.65) ?? baseDy,
                            );
                            cardOpacity = lerpDouble(baseOpacity, 1.0, dragProgress * 0.50) ?? baseOpacity;
                          } else if (d > 1.2 && d <= 2.2) {
                            cardScale = lerpDouble(baseScale, 0.94, dragProgress * 0.50) ?? baseScale;
                            cardOffset = Offset(
                              0.0,
                              lerpDouble(baseDy, 14.0, dragProgress * 0.50) ?? baseDy,
                            );
                            cardOpacity = lerpDouble(baseOpacity, 0.88, dragProgress * 0.40) ?? baseOpacity;
                          }
                        }

                        // Upcoming stacked deck cards resting directly beneath the active card
                        if (!isCurrentActive) {
                          return RepaintBoundary(
                            child: Transform.translate(
                              offset: cardOffset,
                              child: Transform.scale(
                                scale: cardScale,
                                child: Opacity(
                                  opacity: cardOpacity.clamp(0.0, 1.0),
                                  child: _buildStackedDeckCardFace(
                                    subject: subject,
                                    slot: slot,
                                    width: centerCardWidth,
                                    height: centerCardHeight,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        // Active interactive front card
                        return RepaintBoundary(
                          child: Transform.translate(
                            offset: cardOffset,
                            child: Transform.rotate(
                              angle: cardRot,
                              child: Transform.scale(
                                scale: cardScale,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (details) {
                                    if (widget.semesterEnded || isLocked) return;
                                    _snapAnimController.stop();
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
                                    final dx = _dragOffset.dx;
                                    final dy = _dragOffset.dy;
                                    final vx = velocity.dx;
                                    final vy = velocity.dy;

                                    final rightStatus = swipeProvider.rightAction == SwipeAction.present
                                        ? AttendanceStatus.attended
                                        : AttendanceStatus.absent;
                                    final leftStatus = swipeProvider.leftAction == SwipeAction.present
                                        ? AttendanceStatus.attended
                                        : AttendanceStatus.absent;

                                    // Horizontal swipe right (Present or Absent per setting)
                                    if (dx > 60 || (vx > 280 && dx > 15)) {
                                      _triggerAction(rightStatus, initialVelocity: velocity);
                                    }
                                    // Horizontal swipe left (Opposite per setting)
                                    else if (dx < -60 || (vx < -280 && dx < -15)) {
                                      _triggerAction(leftStatus, initialVelocity: velocity);
                                    }
                                    // Vertical swipe down or up (Cancelled / Holiday)
                                    else if (dy.abs() > 48 || (vy.abs() > 280 && dy.abs() > 15)) {
                                      _triggerAction(AttendanceStatus.cancelled, initialVelocity: velocity);
                                    }
                                    // Smooth spring reset
                                    else {
                                      _resetPosition();
                                    }
                                  },
                                  child: _buildActiveCardFace(
                                    subject: subject,
                                    slot: slot,
                                    attendance: attendance,
                                    isLocked: isLocked,
                                    dragOffset: currentDrag,
                                    width: centerCardWidth,
                                    height: centerCardHeight,
                                    periodNumber: activeIndex + 1,
                                    totalPeriods: count,
                                    swipeProvider: swipeProvider,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),

                      // Dismissing card overlay flying smoothly away
                      if (_dismissingSubject != null && _dismissAnimController.isAnimating)
                        RepaintBoundary(
                          child: Transform.translate(
                            offset: _dismissOffsetAnim.value,
                            child: Transform.rotate(
                              angle: _dismissRotAnim.value,
                              child: Opacity(
                                opacity: _dismissOpacityAnim.value,
                                child: _buildDismissingCardFace(
                                  subject: _dismissingSubject!,
                                  slot: _dismissingSlot!,
                                  width: centerCardWidth,
                                  height: centerCardHeight,
                                  status: _dismissingStatus!,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Dismissing Card Snapshot (Renders fluidly while flying out) ---
  Widget _buildDismissingCardFace({
    required Subject subject,
    required TimeSlot slot,
    required double width,
    required double height,
    required AttendanceStatus status,
  }) {
    final rs = widget.rs;
    final isDarkMode = widget.isDarkMode;

    final Color glowColor = status == AttendanceStatus.attended
        ? const Color(0xFF10B981)
        : (status == AttendanceStatus.cancelled ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(28)),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? [
                    const Color(0xFF222430).withValues(alpha: 0.95),
                    const Color(0xFF141620).withValues(alpha: 0.98),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.96),
                    const Color(0xFFF8FAFC).withValues(alpha: 0.98),
                  ],
          ),
          borderRadius: BorderRadius.circular(rs.scale(28)),
          border: Border.all(color: glowColor.withValues(alpha: 0.8), width: 1.6),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.25),
              blurRadius: 28,
              spreadRadius: -2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: rs.insetsSymmetric(horizontal: 22, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: rs.width(7)),
                      Text(
                        slot.startTime.format(context),
                        style: GoogleFonts.inter(
                          fontSize: rs.font(13.5),
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: rs.insetsSymmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: glowColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(rs.scale(12)),
                      border: Border.all(color: glowColor.withValues(alpha: 0.45), width: 0.8),
                    ),
                    child: Text(
                      status == AttendanceStatus.attended
                          ? '✓ ATTENDED'
                          : (status == AttendanceStatus.cancelled ? '⏸ CANCELLED' : '✕ MISSED'),
                      style: GoogleFonts.inter(
                        fontSize: rs.font(10.5),
                        fontWeight: FontWeight.w800,
                        color: glowColor,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: rs.height(14)),
              Text(
                subject.name,
                style: GoogleFonts.inter(
                  fontSize: rs.font(24),
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // --- Stacked Background Card Face (Deck Stack Depth Layer) ---
  Widget _buildStackedDeckCardFace({
    required Subject subject,
    required TimeSlot slot,
    required double width,
    required double height,
  }) {
    final rs = widget.rs;
    final isDarkMode = widget.isDarkMode;

    final effectiveLocId = subject.getEffectiveLocationId(slot);
    final locConfig = effectiveLocId != null ? widget.locationById[effectiveLocId] : null;
    final room = subject.getEffectiveRoom(slot) ?? locConfig?.name;
    final block = subject.getEffectiveBlock(slot) ?? locConfig?.block;
    final hasRoom = room != null && room.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(28)),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? [
                    const Color(0xFF222432).withValues(alpha: 0.94),
                    const Color(0xFF141622).withValues(alpha: 0.96),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.96),
                    const Color(0xFFF6F8FA).withValues(alpha: 0.98),
                  ],
          ),
          borderRadius: BorderRadius.circular(rs.scale(28)),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.08),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.06),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Top specular sheen line
            Positioned(
              top: 0,
              left: 20,
              right: 20,
              height: 1.2,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      isDarkMode ? Colors.white.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: rs.insetsSymmetric(horizontal: 22, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.name,
                    style: GoogleFonts.inter(
                      fontSize: rs.font(24),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: rs.height(7)),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: rs.width(7)),
                      Text(
                        slot.startTime.format(context),
                        style: GoogleFonts.inter(
                          fontSize: rs.font(14),
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      if (hasRoom) ...[
                        SizedBox(width: rs.width(6)),
                        Flexible(
                          child: Text(
                            '• Rm $room${block != null && block.isNotEmpty ? " • $block" : ""}',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(13),
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? Colors.white54 : Colors.black45,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Active Front Card Face (Rich Glassmorphic Design) ---
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
    required SwipeActionProvider swipeProvider,
  }) {
    final rs = widget.rs;
    final isDarkMode = widget.isDarkMode;

    final effectiveLocId = subject.getEffectiveLocationId(slot);
    final locConfig = effectiveLocId != null ? widget.locationById[effectiveLocId] : null;
    final room = subject.getEffectiveRoom(slot) ?? locConfig?.name;
    final block = subject.getEffectiveBlock(slot) ?? locConfig?.block;
    final hasRoom = room != null && room.isNotEmpty;

    // Real-time drag stamp opacity
    final double rightSwipeRatio = (dragOffset.dx / 60.0).clamp(0.0, 1.0);
    final double leftSwipeRatio = (-dragOffset.dx / 60.0).clamp(0.0, 1.0);
    final double downSwipeRatio = (dragOffset.dy / 50.0).clamp(0.0, 1.0);
    final double verticalSwipeRatio = (dragOffset.dy.abs() / 50.0).clamp(0.0, 1.0);

    // Dynamic Reactive Border Color
    final Color borderColor;
    if (rightSwipeRatio > 0.18) {
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.90);
    } else if (leftSwipeRatio > 0.18) {
      borderColor = const Color(0xFFEF4444).withValues(alpha: 0.90);
    } else if (verticalSwipeRatio > 0.18) {
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.90);
    } else {
      borderColor = isDarkMode ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.10);
    }

    final borderWidth = (rightSwipeRatio > 0.18 || leftSwipeRatio > 0.18 || verticalSwipeRatio > 0.18) ? 1.6 : 1.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(28)),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? [
                    const Color(0xFF222430).withValues(alpha: 0.94),
                    const Color(0xFF141620).withValues(alpha: 0.96),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.95),
                    const Color(0xFFF8FAFC).withValues(alpha: 0.97),
                  ],
          ),
          borderRadius: BorderRadius.circular(rs.scale(28)),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.38 : 0.08),
              blurRadius: 28,
              spreadRadius: -2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
          child: Stack(
            children: [
              // Specular top highlight sheen
              Positioned(
                top: 0,
                left: 20,
                right: 20,
                height: 1.2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        isDarkMode ? Colors.white.withValues(alpha: 0.32) : Colors.white.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Card Content
              Padding(
                padding: rs.insetsSymmetric(horizontal: 22, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject Name Hero
                    Text(
                      subject.name,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(24),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: isDarkMode ? Colors.white : const Color(0xFF0F172A),
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    SizedBox(height: rs.height(7)),

                    // Bullet Dot + Time + Room
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: rs.width(7)),
                        Text(
                          slot.startTime.format(context),
                          style: GoogleFonts.inter(
                            fontSize: rs.font(14),
                            fontWeight: FontWeight.w600,
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        if (hasRoom) ...[
                          SizedBox(width: rs.width(6)),
                          Flexible(
                            child: Text(
                              '• Rm $room${block != null && block.isNotEmpty ? " • $block" : ""}',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(13),
                                fontWeight: FontWeight.w500,
                                color: isDarkMode ? Colors.white54 : Colors.black45,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (isLocked)
                      Padding(
                        padding: EdgeInsets.only(top: rs.height(5)),
                        child: Text(
                          '🔒 Locked by manual count override',
                          style: GoogleFonts.inter(fontSize: rs.font(11), color: const Color(0xFFF59E0B)),
                        ),
                      ),

                    const Spacer(),

                    // Current Marked Status Pill (if recorded)
                    if (attendance != null)
                      Center(
                        child: Container(
                          margin: EdgeInsets.only(bottom: rs.height(14)),
                          padding: rs.insetsSymmetric(horizontal: 10, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: (attendance.status == AttendanceStatus.attended
                                    ? const Color(0xFF10B981)
                                    : (attendance.status == AttendanceStatus.cancelled
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFFEF4444)))
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(rs.scale(12)),
                            border: Border.all(
                              color: (attendance.status == AttendanceStatus.attended
                                      ? const Color(0xFF10B981)
                                      : (attendance.status == AttendanceStatus.cancelled
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFFEF4444)))
                                  .withValues(alpha: 0.40),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                attendance.status == AttendanceStatus.attended
                                    ? Icons.check_circle_rounded
                                    : (attendance.status == AttendanceStatus.cancelled
                                        ? Icons.pause_circle_rounded
                                        : Icons.cancel_rounded),
                                size: rs.scale(12),
                                color: attendance.status == AttendanceStatus.attended
                                    ? const Color(0xFF10B981)
                                    : (attendance.status == AttendanceStatus.cancelled
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFFEF4444)),
                              ),
                              SizedBox(width: rs.width(5)),
                              Text(
                                'Marked: ${attendance.status == AttendanceStatus.attended ? "Attended" : (attendance.status == AttendanceStatus.cancelled ? "Holiday" : "Missed")}',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.w700,
                                  color: attendance.status == AttendanceStatus.attended
                                      ? const Color(0xFF10B981)
                                      : (attendance.status == AttendanceStatus.cancelled
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFFEF4444)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Concept 3 Action Cues: Left [← Missed], Center [︽ Cancelled], Right [→ Attended]
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Missed Cue
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _triggerAction(AttendanceStatus.absent);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: rs.width(6), vertical: rs.height(6)),
                            decoration: BoxDecoration(
                              color: leftSwipeRatio > 0.08
                                  ? const Color(0xFFE26153).withValues(alpha: 0.20)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(rs.scale(12)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_back_rounded,
                                  size: rs.scale(19),
                                  color: const Color(0xFFE26153),
                                ),
                                SizedBox(height: rs.height(10)),
                                RotatedBox(
                                  quarterTurns: 1,
                                  child: Text(
                                    'Missed',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(13),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: const Color(0xFFE26153),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Center: Cancelled Cue
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _triggerAction(AttendanceStatus.cancelled);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: rs.width(14), vertical: rs.height(6)),
                            decoration: BoxDecoration(
                              color: verticalSwipeRatio > 0.08
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.20)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(rs.scale(12)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.keyboard_double_arrow_up_rounded,
                                  size: rs.scale(23),
                                  color: isDarkMode ? Colors.white70 : Colors.black54,
                                ),
                                SizedBox(height: rs.height(4)),
                                Text(
                                  'Cancelled',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(12),
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Right: Attended Cue
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _triggerAction(AttendanceStatus.attended);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: rs.width(6), vertical: rs.height(6)),
                            decoration: BoxDecoration(
                              color: rightSwipeRatio > 0.08
                                  ? const Color(0xFF34D399).withValues(alpha: 0.20)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(rs.scale(12)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: rs.scale(19),
                                  color: const Color(0xFF34D399),
                                ),
                                SizedBox(height: rs.height(10)),
                                RotatedBox(
                                  quarterTurns: 3,
                                  child: Text(
                                    'Attended',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(13),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: const Color(0xFF34D399),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Dynamic Glowing Swipe Feedback Stamps
              if (rightSwipeRatio > 0.05)
                Positioned(
                  top: rs.height(20),
                  right: rs.width(18),
                  child: Opacity(
                    opacity: rightSwipeRatio,
                    child: Transform.rotate(
                      angle: 0.12,
                      child: Container(
                        padding: rs.insetsSymmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(rs.scale(14)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.5),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: rs.scale(14), color: Colors.white),
                            SizedBox(width: rs.width(5)),
                            Text(
                              'ATTENDED',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(12),
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
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
                    child: Transform.rotate(
                      angle: -0.12,
                      child: Container(
                        padding: rs.insetsSymmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(rs.scale(14)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close_rounded, size: rs.scale(14), color: Colors.white),
                            SizedBox(width: rs.width(5)),
                            Text(
                              'MISSED',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(12),
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              if (verticalSwipeRatio > 0.05 && dragOffset.dx.abs() < 50)
                Positioned(
                  top: downSwipeRatio > 0.05 ? null : rs.height(20),
                  bottom: downSwipeRatio > 0.05 ? rs.height(20) : null,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Opacity(
                    opacity: verticalSwipeRatio,
                    child: Container(
                      padding: rs.insetsSymmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_rounded, size: rs.scale(14), color: Colors.white),
                          SizedBox(width: rs.width(5)),
                          Text(
                            'CANCELLED',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

// --- Schedule Item Swipe Helpers (Left/Right swipe to mark Present/Absent) ---
Widget _buildScheduleSwipeBackground({
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

  final isPresent = !isUnmarking && action == SwipeAction.present;

  return Container(
    decoration: BoxDecoration(
      color: isUnmarking
          ? const Color(0xFF27272A)
          : (isPresent
              ? const Color(0xFF10B981).withValues(alpha: 0.25)
              : const Color(0xFFEF4444).withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(rs.scale(18)),
      border: Border.all(
        color: isUnmarking
            ? Colors.white12
            : (isPresent
                ? const Color(0xFF10B981).withValues(alpha: 0.45)
                : const Color(0xFFEF4444).withValues(alpha: 0.45)),
        width: 0.8,
      ),
    ),
    padding: EdgeInsets.symmetric(horizontal: rs.width(20)),
    alignment: alignment,
    child: Icon(
      icon,
      color: isUnmarking
          ? Colors.white
          : (isPresent ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
      size: rs.scale(20),
    ),
  );
}

Future<void> _handleScheduleSwipeAction({
  required BuildContext context,
  required SwipeAction action,
  required bool isUnmarking,
  required Subject subject,
  required String? slotKey,
  required DateTime targetDate,
  required SubjectProvider subjectProvider,
  required bool isLocked,
  required bool semesterEnded,
  required bool isFutureDate,
}) async {
  if (isLocked || semesterEnded || isFutureDate) {
    return;
  }
  HapticFeedback.mediumImpact();
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
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
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
  final SubjectProvider subjectProvider;
  final TimeFormatProvider timeFormatProvider;
  final DateTime targetDate;
  final Map<String, LocationConfig> locationById;
  final bool isExpanded;
  final bool isDarkMode;
  final ResponsiveScale rs;
  final bool semesterEnded;
  final bool isFutureDate;
  final VoidCallback onToggleExpand;
  final ValueChanged<int> onSummonPeriod;
  final VoidCallback onMarkDayHoliday;
  final VoidCallback onMarkDayAbsent;
  final VoidCallback onMarkDayPresent;

  const AccordionPeekWindow({
    super.key,
    required this.displayClasses,
    required this.activeCardIndex,
    required this.attendanceProvider,
    required this.subjectProvider,
    required this.timeFormatProvider,
    required this.targetDate,
    required this.locationById,
    required this.isExpanded,
    required this.isDarkMode,
    required this.rs,
    required this.semesterEnded,
    required this.isFutureDate,
    required this.onToggleExpand,
    required this.onSummonPeriod,
    required this.onMarkDayHoliday,
    required this.onMarkDayAbsent,
    required this.onMarkDayPresent,
  });

  Widget _buildDayActionCapsule({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required ResponsiveScale rs,
    required bool isDarkMode,
    Color? activeColor,
  }) {
    final Color tint = activeColor ?? (isDarkMode ? Colors.white : Colors.black);
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(rs.scale(16)),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: rs.height(7), horizontal: rs.width(4)),
        decoration: BoxDecoration(
          color: isActive
              ? tint.withValues(alpha: isDarkMode ? 0.20 : 0.12)
              : (isDarkMode ? const Color(0xFF1C1E26) : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(rs.scale(16)),
          border: Border.all(
            color: isActive
                ? tint.withValues(alpha: isDarkMode ? 0.60 : 0.45)
                : (isDarkMode ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.08)),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: rs.scale(13),
              color: isActive ? tint : (isDarkMode ? Colors.white70 : Colors.black87),
            ),
            SizedBox(width: rs.width(4)),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: rs.font(10.5),
                  fontWeight: FontWeight.w700,
                  color: isActive ? tint : (isDarkMode ? Colors.white : Colors.black87),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final swipeProvider = Provider.of<SwipeActionProvider>(context);
    int attendedCount = 0;
    int absentCount = 0;
    int cancelledCount = 0;

    for (final s in displayClasses) {
      final slotKey = s.schedule.first.slotKey;
      final rec = attendanceProvider.getAttendanceForSubjectOnDate(s.id, targetDate, slotKey: slotKey);
      if (rec != null) {
        if (rec.status == AttendanceStatus.attended) {
          attendedCount++;
        } else if (rec.status == AttendanceStatus.absent || rec.status == AttendanceStatus.plannedAbsent) {
          absentCount++;
        } else if (rec.status == AttendanceStatus.cancelled) {
          cancelledCount++;
        }
      }
    }

    final int totalClasses = displayClasses.length;
    final int remainingCount = totalClasses - attendedCount - absentCount - cancelledCount;
    final bool allAttended = totalClasses > 0 && attendedCount == totalClasses;
    final bool allAbsent = totalClasses > 0 && absentCount == totalClasses;
    final bool allCancelled = totalClasses > 0 && cancelledCount == totalClasses;

    // --- Collapsed State: Sleek Frosted Glass Dock Pill ---
    if (!isExpanded) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(rs.scale(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF141620).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(rs.scale(22)),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.10),
                width: 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: onToggleExpand,
              borderRadius: BorderRadius.circular(rs.scale(22)),
              child: Padding(
                padding: rs.insetsSymmetric(horizontal: 14, vertical: 7),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4.5),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white12 : Colors.black12,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: rs.scale(14),
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    SizedBox(width: rs.width(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'DAY TIMETABLE',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$totalClasses classes scheduled • Tap to peek timeline',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(10),
                              color: isDarkMode ? Colors.white54 : Colors.black54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: rs.insetsSymmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(rs.scale(12)),
                        border: Border.all(
                          color: isDarkMode ? Colors.white12 : Colors.black12,
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        'P${activeCardIndex + 1}/$totalClasses',
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
          ),
        ),
      );
    }

    // --- Expanded State: Structured App-Type Timeline Rail Sheet ---
    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDarkMode
                  ? [
                      const Color(0xFF161822).withValues(alpha: 0.96),
                      const Color(0xFF10121A).withValues(alpha: 0.98),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.97),
                      const Color(0xFFF8FAFC).withValues(alpha: 0.98),
                    ],
            ),
            borderRadius: BorderRadius.circular(rs.scale(24)),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.10),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.60 : 0.18),
                blurRadius: 36,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header Tab & Drag Handle
              InkWell(
                onTap: onToggleExpand,
                borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(24))),
                child: Padding(
                  padding: rs.insetsSymmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white24 : Colors.black26,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(height: rs.height(8)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: rs.scale(14),
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                                SizedBox(width: rs.width(8)),
                                Flexible(
                                  child: Text(
                                    'DAY TIMETABLE',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(12),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                SizedBox(width: rs.width(6)),
                                Container(
                                  padding: rs.insetsSymmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(rs.scale(10)),
                                  ),
                                  child: Text(
                                    '$totalClasses Periods',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(10),
                                      fontWeight: FontWeight.w600,
                                      color: isDarkMode ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: rs.width(6)),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.white12 : Colors.black12,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: rs.scale(16),
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Day Progress Rail Bar (Visual segmented breakdown)
              if (totalClasses > 0)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: rs.width(16), vertical: rs.height(2)),
                  child: Column(
                    children: [
                      // Segmented Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(rs.scale(6)),
                        child: Container(
                          height: rs.scale(5),
                          color: isDarkMode ? Colors.white12 : Colors.black12,
                          child: Row(
                            children: [
                              if (attendedCount > 0)
                                Expanded(
                                  flex: attendedCount,
                                  child: Container(color: const Color(0xFF10B981)),
                                ),
                              if (absentCount > 0)
                                Expanded(
                                  flex: absentCount,
                                  child: Container(color: const Color(0xFFEF4444)),
                                ),
                              if (cancelledCount > 0)
                                Expanded(
                                  flex: cancelledCount,
                                  child: Container(color: const Color(0xFFF59E0B)),
                                ),
                              if (remainingCount > 0)
                                Expanded(
                                  flex: remainingCount,
                                  child: Container(
                                    color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: rs.height(6)),
                      // Progress Metrics Summary
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (attendedCount > 0) ...[
                                    Text(
                                      '✓ $attendedCount Attended',
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(10.5),
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF10B981),
                                      ),
                                    ),
                                    SizedBox(width: rs.width(8)),
                                  ],
                                  if (absentCount > 0) ...[
                                    Text(
                                      '✕ $absentCount Missed',
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(10.5),
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFEF4444),
                                      ),
                                    ),
                                    SizedBox(width: rs.width(8)),
                                  ],
                                  if (cancelledCount > 0) ...[
                                    Text(
                                      '⏸ $cancelledCount Holiday',
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(10.5),
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: rs.width(6)),
                          Text(
                            remainingCount > 0 ? '$remainingCount left' : 'All marked',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(10.5),
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              SizedBox(height: rs.height(6)),

              // Batch Day Action Capsules
              Padding(
                padding: EdgeInsets.symmetric(horizontal: rs.width(14)),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDayActionCapsule(
                        icon: Icons.pause_rounded,
                        label: 'Holiday',
                        isActive: allCancelled,
                        activeColor: const Color(0xFFF59E0B),
                        onTap: onMarkDayHoliday,
                        rs: rs,
                        isDarkMode: isDarkMode,
                      ),
                    ),
                    SizedBox(width: rs.width(8)),
                    Expanded(
                      child: _buildDayActionCapsule(
                        icon: Icons.remove_rounded,
                        label: 'Skip Day',
                        isActive: allAbsent,
                        activeColor: const Color(0xFFEF4444),
                        onTap: onMarkDayAbsent,
                        rs: rs,
                        isDarkMode: isDarkMode,
                      ),
                    ),
                    SizedBox(width: rs.width(8)),
                    Expanded(
                      child: _buildDayActionCapsule(
                        icon: Icons.check_rounded,
                        label: 'All Present',
                        isActive: allAttended,
                        activeColor: const Color(0xFF10B981),
                        onTap: onMarkDayPresent,
                        rs: rs,
                        isDarkMode: isDarkMode,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: rs.height(8)),

              Divider(
                height: 1,
                thickness: 0.6,
                color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),

              // Scrollable Timeline Rail List
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(rs.width(12), rs.height(8), rs.width(12), rs.height(14)),
                  physics: const BouncingScrollPhysics(),
                  itemCount: totalClasses,
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

                    final isAttended = attendance?.status == AttendanceStatus.attended;
                    final isAbsent = attendance?.status == AttendanceStatus.absent || attendance?.status == AttendanceStatus.plannedAbsent;
                    final isHoliday = attendance?.status == AttendanceStatus.cancelled;

                    final rightSwipeAction = swipeProvider.rightAction;
                    final leftSwipeAction = swipeProvider.leftAction;
                    final isLocked = CalendarUtils.isLockedByManualOverride(subject, targetDate);

                    final isUnmarkingRight = (isAttended && rightSwipeAction == SwipeAction.present) ||
                        (isAbsent && rightSwipeAction == SwipeAction.absent);
                    final isUnmarkingLeft = (isAttended && leftSwipeAction == SwipeAction.present) ||
                        (isAbsent && leftSwipeAction == SwipeAction.absent);

                    final startMin = slot.startTime.hour * 60 + slot.startTime.minute;
                    final endMin = slot.endTime.hour * 60 + slot.endTime.minute;
                    final diff = endMin - startMin;
                    String durationStr = '';
                    if (diff > 0) {
                      if (diff % 60 == 0) {
                        durationStr = '${diff ~/ 60}h';
                      } else if (diff > 60) {
                        durationStr = '${diff ~/ 60}h ${diff % 60}m';
                      } else {
                        durationStr = '${diff}m';
                      }
                    }

                    final effectiveLocId = subject.getEffectiveLocationId(slot);
                    final locConfig = effectiveLocId != null ? locationById[effectiveLocId] : null;
                    final room = subject.getEffectiveRoom(slot) ?? locConfig?.name;

                    // Node Theme Colors
                    final Color nodeColor = isAttended
                        ? const Color(0xFF10B981)
                        : (isAbsent ? const Color(0xFFEF4444) : (isHoliday ? const Color(0xFFF59E0B) : (isDarkMode ? const Color(0xFF272935) : const Color(0xFFE2E8F0))));

                    final IconData? nodeIcon = isAttended
                        ? Icons.check_rounded
                        : (isAbsent ? Icons.close_rounded : (isHoliday ? Icons.pause_rounded : null));

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Left: Time Column (Structured Time Rail)
                          SizedBox(
                            width: rs.scale(50),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: rs.height(10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Text(
                                    slot.startTime.format(context),
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(11.5),
                                      fontWeight: FontWeight.w700,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                    maxLines: 1,
                                  ),
                                  Text(
                                    slot.endTime.format(context),
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(10),
                                      fontWeight: FontWeight.w500,
                                      color: isDarkMode ? Colors.white54 : Colors.black45,
                                    ),
                                    maxLines: 1,
                                  ),
                                  if (durationStr.isNotEmpty) ...[
                                    SizedBox(height: rs.height(4)),
                                    Container(
                                      padding: rs.insetsSymmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(rs.scale(6)),
                                      ),
                                      child: Text(
                                        durationStr,
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(9.5),
                                          fontWeight: FontWeight.w600,
                                          color: isDarkMode ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          SizedBox(width: rs.width(8)),

                          // 2. Central Continuous Timeline Rail with Period Node
                          SizedBox(
                            width: rs.scale(32),
                            child: Column(
                              children: [
                                // Top connecting line
                                Container(
                                  width: 1.6,
                                  height: rs.height(10),
                                  color: idx == 0
                                      ? Colors.transparent
                                      : (isDarkMode ? Colors.white12 : Colors.black12),
                                ),
                                // Glowing Circular Period Node
                                Container(
                                  width: rs.scale(30),
                                  height: rs.scale(30),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: nodeColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isCurrent
                                          ? subject.color
                                          : (isDarkMode ? Colors.white24 : Colors.black12),
                                      width: isCurrent ? 2.0 : 1.0,
                                    ),
                                    boxShadow: isCurrent
                                        ? [
                                            BoxShadow(
                                              color: subject.color.withValues(alpha: 0.5),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: nodeIcon != null
                                      ? Icon(nodeIcon, size: rs.scale(15), color: Colors.white)
                                      : Text(
                                          'P${idx + 1}',
                                          style: GoogleFonts.inter(
                                            fontSize: rs.font(10.5),
                                            fontWeight: FontWeight.w800,
                                            color: isDarkMode ? Colors.white70 : Colors.black87,
                                          ),
                                        ),
                                ),
                                // Bottom connecting line
                                Expanded(
                                  child: Container(
                                    width: 1.6,
                                    color: idx == totalClasses - 1
                                        ? Colors.transparent
                                        : (isDarkMode ? Colors.white12 : Colors.black12),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(width: rs.width(8)),

                          // 3. Right: Structured Period Glass Card
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: rs.height(5)),
                              child: SwipeableCard(
                                key: ValueKey('peek_timeline_${subject.id}_${slotKey}_$idx'),
                                rs: rs,
                                borderRadius: BorderRadius.circular(rs.scale(18)),
                                swipeRightBackground: _buildScheduleSwipeBackground(
                                  action: rightSwipeAction,
                                  alignment: Alignment.centerLeft,
                                  rs: rs,
                                  isUnmarking: isUnmarkingRight,
                                ),
                                swipeLeftBackground: _buildScheduleSwipeBackground(
                                  action: leftSwipeAction,
                                  alignment: Alignment.centerRight,
                                  rs: rs,
                                  isUnmarking: isUnmarkingLeft,
                                ),
                                onSwipeRight: () => _handleScheduleSwipeAction(
                                  context: context,
                                  action: rightSwipeAction,
                                  isUnmarking: isUnmarkingRight,
                                  subject: subject,
                                  slotKey: slotKey,
                                  targetDate: targetDate,
                                  subjectProvider: subjectProvider,
                                  isLocked: isLocked,
                                  semesterEnded: semesterEnded,
                                  isFutureDate: isFutureDate,
                                ),
                                onSwipeLeft: () => _handleScheduleSwipeAction(
                                  context: context,
                                  action: leftSwipeAction,
                                  isUnmarking: isUnmarkingLeft,
                                  subject: subject,
                                  slotKey: slotKey,
                                  targetDate: targetDate,
                                  subjectProvider: subjectProvider,
                                  isLocked: isLocked,
                                  semesterEnded: semesterEnded,
                                  isFutureDate: isFutureDate,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => onSummonPeriod(idx),
                                    borderRadius: BorderRadius.circular(rs.scale(18)),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: rs.width(13),
                                        vertical: rs.height(10),
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDarkMode
                                            ? const Color(0xFF1B1D27).withValues(alpha: 0.95)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(rs.scale(18)),
                                        border: Border.all(
                                          color: isCurrent
                                              ? subject.color.withValues(alpha: 0.55)
                                              : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
                                          width: isCurrent ? 1.4 : 0.8,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.04),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Header row: Acronym + Room + Active badge
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: subject.color.withValues(alpha: 0.20),
                                                  borderRadius: BorderRadius.circular(rs.scale(8)),
                                                  border: Border.all(
                                                    color: subject.color.withValues(alpha: 0.45),
                                                    width: 0.7,
                                                  ),
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
                                              if (room != null && room.isNotEmpty) ...[
                                                SizedBox(width: rs.width(6)),
                                                Flexible(
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.location_on_rounded, size: rs.scale(11), color: isDarkMode ? Colors.white54 : Colors.black45),
                                                      SizedBox(width: rs.width(2)),
                                                      Flexible(
                                                        child: Text(
                                                          'Rm $room',
                                                          style: GoogleFonts.inter(
                                                            fontSize: rs.font(10.5),
                                                            fontWeight: FontWeight.w500,
                                                            color: isDarkMode ? Colors.white60 : Colors.black54,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              const Spacer(),
                                              if (isCurrent)
                                                Container(
                                                  padding: rs.insetsSymmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: subject.color.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(rs.scale(8)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width: 5,
                                                        height: 5,
                                                        decoration: BoxDecoration(
                                                          color: subject.color,
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                      SizedBox(width: rs.width(4)),
                                                      Text(
                                                        'Active in Deck',
                                                        style: GoogleFonts.inter(
                                                          fontSize: rs.font(9.5),
                                                          fontWeight: FontWeight.w700,
                                                          color: subject.color,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),

                                          SizedBox(height: rs.height(6)),

                                          // Subject Full Name
                                          Text(
                                            subject.name,
                                            style: GoogleFonts.inter(
                                              fontSize: rs.font(14.5),
                                              fontWeight: FontWeight.w700,
                                              color: isDarkMode ? Colors.white : Colors.black87,
                                              height: 1.2,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),

                                          SizedBox(height: rs.height(8)),

                                          // Interactive Quick Attendance Action Row
                                          Row(
                                            children: [
                                              // Present Button
                                              Expanded(
                                                child: InkWell(
                                                  onTap: () {
                                                    HapticFeedback.selectionClick();
                                                    if (isAttended) {
                                                      subjectProvider.unmarkAttendance(subject.id, targetDate, slotKey: slotKey);
                                                    } else {
                                                      subjectProvider.markAttendance(subject.id, targetDate, AttendanceStatus.attended, slotKey: slotKey);
                                                    }
                                                  },
                                                  borderRadius: BorderRadius.circular(rs.scale(10)),
                                                  child: Container(
                                                    padding: EdgeInsets.symmetric(vertical: rs.height(6)),
                                                    decoration: BoxDecoration(
                                                      color: isAttended
                                                          ? const Color(0xFF10B981).withValues(alpha: 0.20)
                                                          : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                                                      borderRadius: BorderRadius.circular(rs.scale(10)),
                                                      border: Border.all(
                                                        color: isAttended
                                                            ? const Color(0xFF10B981).withValues(alpha: 0.6)
                                                            : (isDarkMode ? Colors.white12 : Colors.black12),
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(
                                                          Icons.check_rounded,
                                                          size: rs.scale(12),
                                                          color: isAttended ? const Color(0xFF10B981) : (isDarkMode ? Colors.white60 : Colors.black54),
                                                        ),
                                                        SizedBox(width: rs.width(4)),
                                                        Flexible(
                                                          child: Text(
                                                            'Present',
                                                            style: GoogleFonts.inter(
                                                              fontSize: rs.font(11),
                                                              fontWeight: FontWeight.w700,
                                                              color: isAttended ? const Color(0xFF10B981) : (isDarkMode ? Colors.white70 : Colors.black87),
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              SizedBox(width: rs.width(6)),

                                              // Absent Button
                                              Expanded(
                                                child: InkWell(
                                                  onTap: () {
                                                    HapticFeedback.selectionClick();
                                                    if (isAbsent) {
                                                      subjectProvider.unmarkAttendance(subject.id, targetDate, slotKey: slotKey);
                                                    } else {
                                                      subjectProvider.markAttendance(subject.id, targetDate, AttendanceStatus.absent, slotKey: slotKey);
                                                    }
                                                  },
                                                  borderRadius: BorderRadius.circular(rs.scale(10)),
                                                  child: Container(
                                                    padding: EdgeInsets.symmetric(vertical: rs.height(6)),
                                                    decoration: BoxDecoration(
                                                      color: isAbsent
                                                          ? const Color(0xFFEF4444).withValues(alpha: 0.20)
                                                          : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                                                      borderRadius: BorderRadius.circular(rs.scale(10)),
                                                      border: Border.all(
                                                        color: isAbsent
                                                            ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                                                            : (isDarkMode ? Colors.white12 : Colors.black12),
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(
                                                          Icons.close_rounded,
                                                          size: rs.scale(12),
                                                          color: isAbsent ? const Color(0xFFEF4444) : (isDarkMode ? Colors.white60 : Colors.black54),
                                                        ),
                                                        SizedBox(width: rs.width(4)),
                                                        Flexible(
                                                          child: Text(
                                                            'Absent',
                                                            style: GoogleFonts.inter(
                                                              fontSize: rs.font(11),
                                                              fontWeight: FontWeight.w700,
                                                              color: isAbsent ? const Color(0xFFEF4444) : (isDarkMode ? Colors.white70 : Colors.black87),
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              SizedBox(width: rs.width(6)),

                                              // Holiday/Pause Button
                                              InkWell(
                                                onTap: () {
                                                  HapticFeedback.selectionClick();
                                                  if (isHoliday) {
                                                    subjectProvider.unmarkAttendance(subject.id, targetDate, slotKey: slotKey);
                                                  } else {
                                                    subjectProvider.markAttendance(subject.id, targetDate, AttendanceStatus.cancelled, slotKey: slotKey);
                                                  }
                                                },
                                                borderRadius: BorderRadius.circular(rs.scale(10)),
                                                child: Container(
                                                  padding: EdgeInsets.all(rs.scale(5.5)),
                                                  decoration: BoxDecoration(
                                                    color: isHoliday
                                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.20)
                                                        : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                                                    borderRadius: BorderRadius.circular(rs.scale(10)),
                                                    border: Border.all(
                                                      color: isHoliday ? const Color(0xFFF59E0B) : (isDarkMode ? Colors.white12 : Colors.black12),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    Icons.pause_rounded,
                                                    size: rs.scale(13),
                                                    color: isHoliday ? const Color(0xFFF59E0B) : (isDarkMode ? Colors.white54 : Colors.black45),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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
    final swipeProvider = Provider.of<SwipeActionProvider>(context);
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
                  // Circular Progress Donut Ring with Dynamic Rising Percentage
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: overallPercentage),
                    duration: const Duration(milliseconds: 950),
                    curve: Curves.easeOutCubic,
                    builder: (context, animatedPercentage, _) {
                      return SizedBox(
                        width: rs.scale(82),
                        height: rs.scale(82),
                        child: CustomPaint(
                          painter: CircularAttendanceRingPainter(
                            percentage: (animatedPercentage / 100.0).clamp(0.0, 1.0),
                            ringColor: isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            trackColor: isDarkMode ? Colors.white12 : Colors.black12,
                            strokeWidth: 8.0,
                          ),
                          child: Center(
                            child: Text(
                              '${animatedPercentage.toStringAsFixed(0)}%',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(18),
                                fontWeight: FontWeight.w800,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
                                color: isSafe ? (isDarkMode ? Colors.white70 : Colors.black87) : const Color(0xFFEF4444),
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

        // Structured Timeline Header (Aligned with Peek Window)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Schedule Timeline',
                  style: GoogleFonts.inter(
                    fontSize: rs.font(16),
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  "Today's Decisions • Tap or swipe to update",
                  style: GoogleFonts.inter(
                    fontSize: rs.font(11.5),
                    color: isDarkMode ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.style_rounded),
              tooltip: 'Reopen Cards Deck',
              onPressed: onRevisitDeck,
            ),
          ],
        ),

        SizedBox(height: rs.height(10)),

        // Structured App Timeline List matching Peek Window
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayClasses.length,
          itemBuilder: (context, idx) {
            final subject = displayClasses[idx];
            final slot = subject.schedule.first;
            final slotKey = slot.slotKey;

            final attendance = attendanceProvider.getAttendanceForSubjectOnDate(
              subject.id,
              targetDate,
              slotKey: slotKey,
            );

            final isAttended = attendance?.status == AttendanceStatus.attended;
            final isAbsent = attendance?.status == AttendanceStatus.absent || attendance?.status == AttendanceStatus.plannedAbsent;
            final isHoliday = attendance?.status == AttendanceStatus.cancelled;

            final startMin = slot.startTime.hour * 60 + slot.startTime.minute;
            final endMin = slot.endTime.hour * 60 + slot.endTime.minute;
            final diff = endMin - startMin;
            String durationStr = '';
            if (diff > 0) {
              if (diff % 60 == 0) {
                durationStr = '${diff ~/ 60}h';
              } else if (diff > 60) {
                durationStr = '${diff ~/ 60}h ${diff % 60}m';
              } else {
                durationStr = '${diff}m';
              }
            }

            final effectiveLocId = subject.getEffectiveLocationId(slot);
            final locConfig = effectiveLocId != null ? locationById[effectiveLocId] : null;
            final room = subject.getEffectiveRoom(slot) ?? locConfig?.name;
            final hasRoom = room != null && room.isNotEmpty;

            final rightSwipeAction = swipeProvider.rightAction;
            final leftSwipeAction = swipeProvider.leftAction;
            final isLocked = CalendarUtils.isLockedByManualOverride(subject, targetDate);

            final isUnmarkingRight = (isAttended && rightSwipeAction == SwipeAction.present) ||
                (isAbsent && rightSwipeAction == SwipeAction.absent);
            final isUnmarkingLeft = (isAttended && leftSwipeAction == SwipeAction.present) ||
                (isAbsent && leftSwipeAction == SwipeAction.absent);

            // Node Theme Colors
            final Color nodeColor = isAttended
                ? const Color(0xFF10B981)
                : (isAbsent
                    ? const Color(0xFFEF4444)
                    : (isHoliday
                        ? const Color(0xFFF59E0B)
                        : (isDarkMode ? const Color(0xFF272935) : const Color(0xFFE2E8F0))));

            final IconData? nodeIcon = isAttended
                ? Icons.check_rounded
                : (isAbsent ? Icons.close_rounded : (isHoliday ? Icons.pause_rounded : null));

            final Color statusPillColor = isAttended
                ? const Color(0xFF10B981)
                : (isAbsent
                    ? const Color(0xFFEF4444)
                    : (isHoliday ? const Color(0xFFF59E0B) : (isDarkMode ? Colors.white60 : Colors.black54)));

            final String statusLabel = isAttended
                ? 'Present'
                : (isAbsent ? 'Absent' : (isHoliday ? 'Holiday' : 'Awaiting'));

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Left: Time Column (Structured Time Rail)
                  SizedBox(
                    width: rs.scale(50),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: rs.height(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            slot.startTime.format(context),
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11.5),
                              fontWeight: FontWeight.w700,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                          ),
                          Text(
                            slot.endTime.format(context),
                            style: GoogleFonts.inter(
                              fontSize: rs.font(10),
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? Colors.white54 : Colors.black45,
                            ),
                            maxLines: 1,
                          ),
                          if (durationStr.isNotEmpty) ...[
                            SizedBox(height: rs.height(4)),
                            Container(
                              padding: rs.insetsSymmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(rs.scale(6)),
                              ),
                              child: Text(
                                durationStr,
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(9.5),
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  SizedBox(width: rs.width(8)),

                  // 2. Central Continuous Timeline Rail with Period Node
                  SizedBox(
                    width: rs.scale(32),
                    child: Column(
                      children: [
                        // Top connecting line
                        Container(
                          width: 1.6,
                          height: rs.height(10),
                          color: idx == 0
                              ? Colors.transparent
                              : (isDarkMode ? Colors.white12 : Colors.black12),
                        ),
                        // Glowing Circular Period Node
                        Container(
                          width: rs.scale(30),
                          height: rs.scale(30),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: nodeColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDarkMode ? Colors.white24 : Colors.black12,
                              width: 1.0,
                            ),
                          ),
                          child: nodeIcon != null
                              ? Icon(nodeIcon, size: rs.scale(15), color: Colors.white)
                              : Text(
                                  'P${idx + 1}',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(10.5),
                                    fontWeight: FontWeight.w800,
                                    color: isDarkMode ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                        ),
                        // Bottom connecting line
                        Expanded(
                          child: Container(
                            width: 1.6,
                            color: idx == displayClasses.length - 1
                                ? Colors.transparent
                                : (isDarkMode ? Colors.white12 : Colors.black12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(width: rs.width(8)),

                  // 3. Right: Structured Period Glass Card
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: rs.height(5)),
                      child: SwipeableCard(
                        key: ValueKey('summary_timeline_${subject.id}_${slotKey}_$idx'),
                        rs: rs,
                        borderRadius: BorderRadius.circular(rs.scale(18)),
                        swipeRightBackground: _buildScheduleSwipeBackground(
                          action: rightSwipeAction,
                          alignment: Alignment.centerLeft,
                          rs: rs,
                          isUnmarking: isUnmarkingRight,
                        ),
                        swipeLeftBackground: _buildScheduleSwipeBackground(
                          action: leftSwipeAction,
                          alignment: Alignment.centerRight,
                          rs: rs,
                          isUnmarking: isUnmarkingLeft,
                        ),
                        onSwipeRight: () => _handleScheduleSwipeAction(
                          context: context,
                          action: rightSwipeAction,
                          isUnmarking: isUnmarkingRight,
                          subject: subject,
                          slotKey: slotKey,
                          targetDate: targetDate,
                          subjectProvider: subjectProvider,
                          isLocked: isLocked,
                          semesterEnded: semesterEnded,
                          isFutureDate: isFutureDate,
                        ),
                        onSwipeLeft: () => _handleScheduleSwipeAction(
                          context: context,
                          action: leftSwipeAction,
                          isUnmarking: isUnmarkingLeft,
                          subject: subject,
                          slotKey: slotKey,
                          targetDate: targetDate,
                          subjectProvider: subjectProvider,
                          isLocked: isLocked,
                          semesterEnded: semesterEnded,
                          isFutureDate: isFutureDate,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(rs.scale(18)),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => onModifyItem(subject, slot, slotKey, attendance),
                                borderRadius: BorderRadius.circular(rs.scale(18)),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: rs.width(13),
                                    vertical: rs.height(10),
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? const Color(0xFF1B1D27).withValues(alpha: 0.92)
                                        : Colors.white.withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(rs.scale(18)),
                                    border: Border.all(
                                      color: isDarkMode
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : Colors.black.withValues(alpha: 0.08),
                                      width: 0.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDarkMode ? 0.22 : 0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Header row: Acronym + Room + Status pill
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: subject.color.withValues(alpha: 0.20),
                                              borderRadius: BorderRadius.circular(rs.scale(8)),
                                              border: Border.all(
                                                color: subject.color.withValues(alpha: 0.45),
                                                width: 0.7,
                                              ),
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
                                          if (hasRoom) ...[
                                            SizedBox(width: rs.width(6)),
                                            Flexible(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.location_on_rounded, size: rs.scale(11), color: isDarkMode ? Colors.white54 : Colors.black45),
                                                  SizedBox(width: rs.width(2)),
                                                  Flexible(
                                                    child: Text(
                                                      'Rm $room',
                                                      style: GoogleFonts.inter(
                                                        fontSize: rs.font(10.5),
                                                        fontWeight: FontWeight.w500,
                                                        color: isDarkMode ? Colors.white60 : Colors.black54,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          const Spacer(),
                                          // Status Pill
                                          Container(
                                            padding: rs.insetsSymmetric(horizontal: 7, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: statusPillColor.withValues(alpha: 0.16),
                                              borderRadius: BorderRadius.circular(rs.scale(8)),
                                              border: Border.all(
                                                color: statusPillColor.withValues(alpha: 0.45),
                                                width: 0.7,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (nodeIcon != null) ...[
                                                  Icon(nodeIcon, size: rs.scale(10.5), color: statusPillColor),
                                                  SizedBox(width: rs.width(3)),
                                                ],
                                                Text(
                                                  statusLabel,
                                                  style: GoogleFonts.inter(
                                                    fontSize: rs.font(10),
                                                    fontWeight: FontWeight.w700,
                                                    color: statusPillColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),

                                      SizedBox(height: rs.height(6)),

                                      // Subject Full Name
                                      Text(
                                        subject.name,
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(14.5),
                                          fontWeight: FontWeight.w700,
                                          color: isDarkMode ? Colors.white : Colors.black87,
                                          height: 1.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),

                                      SizedBox(height: rs.height(8)),

                                      // Interactive Quick Attendance Action Row
                                      Row(
                                        children: [
                                          // Present Button
                                          Expanded(
                                            child: InkWell(
                                              onTap: () {
                                                HapticFeedback.selectionClick();
                                                if (isAttended) {
                                                  subjectProvider.unmarkAttendance(subject.id, targetDate, slotKey: slotKey);
                                                } else {
                                                  subjectProvider.markAttendance(subject.id, targetDate, AttendanceStatus.attended, slotKey: slotKey);
                                                }
                                              },
                                              borderRadius: BorderRadius.circular(rs.scale(10)),
                                              child: Container(
                                                padding: EdgeInsets.symmetric(vertical: rs.height(6)),
                                                decoration: BoxDecoration(
                                                  color: isAttended
                                                      ? const Color(0xFF10B981).withValues(alpha: 0.20)
                                                      : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                                                  borderRadius: BorderRadius.circular(rs.scale(10)),
                                                  border: Border.all(
                                                    color: isAttended
                                                        ? const Color(0xFF10B981).withValues(alpha: 0.6)
                                                        : (isDarkMode ? Colors.white12 : Colors.black12),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.check_rounded,
                                                      size: rs.scale(12),
                                                      color: isAttended ? const Color(0xFF10B981) : (isDarkMode ? Colors.white60 : Colors.black54),
                                                    ),
                                                    SizedBox(width: rs.width(4)),
                                                    Flexible(
                                                      child: Text(
                                                        'Present',
                                                        style: GoogleFonts.inter(
                                                          fontSize: rs.font(11),
                                                          fontWeight: FontWeight.w700,
                                                          color: isAttended ? const Color(0xFF10B981) : (isDarkMode ? Colors.white70 : Colors.black87),
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),

                                          SizedBox(width: rs.width(6)),

                                          // Absent Button
                                          Expanded(
                                            child: InkWell(
                                              onTap: () {
                                                HapticFeedback.selectionClick();
                                                if (isAbsent) {
                                                  subjectProvider.unmarkAttendance(subject.id, targetDate, slotKey: slotKey);
                                                } else {
                                                  subjectProvider.markAttendance(subject.id, targetDate, AttendanceStatus.absent, slotKey: slotKey);
                                                }
                                              },
                                              borderRadius: BorderRadius.circular(rs.scale(10)),
                                              child: Container(
                                                padding: EdgeInsets.symmetric(vertical: rs.height(6)),
                                                decoration: BoxDecoration(
                                                  color: isAbsent
                                                      ? const Color(0xFFEF4444).withValues(alpha: 0.20)
                                                      : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                                                  borderRadius: BorderRadius.circular(rs.scale(10)),
                                                  border: Border.all(
                                                    color: isAbsent
                                                        ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                                                        : (isDarkMode ? Colors.white12 : Colors.black12),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.close_rounded,
                                                      size: rs.scale(12),
                                                      color: isAbsent ? const Color(0xFFEF4444) : (isDarkMode ? Colors.white60 : Colors.black54),
                                                    ),
                                                    SizedBox(width: rs.width(4)),
                                                    Flexible(
                                                      child: Text(
                                                        'Absent',
                                                        style: GoogleFonts.inter(
                                                          fontSize: rs.font(11),
                                                          fontWeight: FontWeight.w700,
                                                          color: isAbsent ? const Color(0xFFEF4444) : (isDarkMode ? Colors.white70 : Colors.black87),
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),

                                          SizedBox(width: rs.width(6)),

                                          // Holiday/Pause Button
                                          InkWell(
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              if (isHoliday) {
                                                subjectProvider.unmarkAttendance(subject.id, targetDate, slotKey: slotKey);
                                              } else {
                                                subjectProvider.markAttendance(subject.id, targetDate, AttendanceStatus.cancelled, slotKey: slotKey);
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(rs.scale(10)),
                                            child: Container(
                                              padding: EdgeInsets.all(rs.scale(5.5)),
                                              decoration: BoxDecoration(
                                                color: isHoliday
                                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.20)
                                                    : (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                                                borderRadius: BorderRadius.circular(rs.scale(10)),
                                                border: Border.all(
                                                  color: isHoliday ? const Color(0xFFF59E0B) : (isDarkMode ? Colors.white12 : Colors.black12),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.pause_rounded,
                                                size: rs.scale(13),
                                                color: isHoliday ? const Color(0xFFF59E0B) : (isDarkMode ? Colors.white54 : Colors.black45),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
