import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:workmanager/workmanager.dart';

import '../../main.dart';
import '../../models/app_update_model.dart';
import '../../services/app_file_intent_listener.dart';
import '../../services/backup_service.dart';
import '../../services/database_service.dart';
import '../../services/live_timetable_sync_service.dart';
import '../../services/update_service.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../bunk_meter/bunk_meter_screen.dart';
import '../bunk_meter/what_if_calculator_sheet.dart';
import '../calendar/calendar_screen.dart';
import '../import/unified_import_screen.dart';
import '../planner/leave_planner_screen.dart';
import '../settings/more_screen.dart';
import '../semester/semester_provider.dart';
import '../semester/semester_screen.dart';
import '../subject/add_subject_screen.dart';
import '../subject/import_timetable_screen.dart';
import '../subject/subject_provider.dart';
import '../subject/subject_screen.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';
import '../../models/github_discussion_model.dart';
import '../../services/github_discussions_service.dart';
import '../settings/discussion_detail_screen.dart';
import '../../widgets/day_cycle_background.dart';
import 'todays_schedule.dart';
import 'update_dialog.dart';
import 'floating_dock_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  final int initialPageIndex;
  const HomeScreen({super.key, this.initialPageIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late int _selectedIndex;
  String _scheduleTitle = "Today";
  bool _canGoPrevious = true;
  bool _canGoNext = true;
  final GlobalKey<TodayScheduleState> _todayScheduleKey = GlobalKey<TodayScheduleState>();
  final UpdateService _updateService = UpdateService();
  AppUpdate? _pendingUpdate;
  bool _isDownloading = false;

  final GlobalKey _todayTabKey = GlobalKey();
  final GlobalKey _subjectTabKey = GlobalKey();
  final GlobalKey _semesterTabKey = GlobalKey();
  final GlobalKey _bunkTabKey = GlobalKey();
  final GlobalKey _moreTabKey = GlobalKey();
  final GlobalKey _calendarKey = GlobalKey();
  final GlobalKey _importKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPageIndex;
    if (!kDebugMode) {
      _checkForUpdates();
    }
    _checkForAnnouncements();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppFileIntentListener().init(context);

      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.registerTabSwitcher((index) {
        if (mounted) {
          setState(() {
            _selectedIndex = index;
          });
        }
      });
      tutorialController.registerRouteHandler((action) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          switch (action) {
            case TutorialRouteAction.addSubject:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddSubjectScreen()),
              );
              break;
            case TutorialRouteAction.importTimetable:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ImportTimetableScreen()),
              );
              break;
            case TutorialRouteAction.calendar:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CalendarScreen()),
              );
              break;
            case TutorialRouteAction.bunkCalculator:
              final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
              final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
              final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

              if (semesterProvider.semester != null) {
                final Map<String, List<Attendance>> recordsBySubject = {};
                for (final record in attendanceProvider.attendanceRecords) {
                  recordsBySubject.putIfAbsent(record.subjectId, () => []).add(record);
                }

                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  barrierColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black54
                      : Colors.black26,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (ctx) => WhatIfCalculatorSheet(
                    subjects: subjectProvider.subjects,
                    recordsBySubject: recordsBySubject,
                    semester: semesterProvider.semester!,
                  ),
                );
              }
              break;
            case TutorialRouteAction.leavePlanner:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LeavePlannerScreen()),
              );
              break;
            case TutorialRouteAction.none:
              break;
          }
        });
      });
      tutorialController.registerKey('nav_tab_today', _todayTabKey);
      tutorialController.registerKey('nav_tab_subjects', _subjectTabKey);
      tutorialController.registerKey('nav_tab_semester', _semesterTabKey);
      tutorialController.registerKey('nav_tab_bunk_meter', _bunkTabKey);
      tutorialController.registerKey('nav_tab_more', _moreTabKey);
      tutorialController.registerKey('appbar_calendar', _calendarKey);
      tutorialController.registerKey('appbar_import_timetable', _importKey);
      tutorialController.registerKey('fab_add_subject', _fabKey);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        final backupService = BackupService();
        backupService.getScheduledBackupTargetTime().then((scheduledTarget) {
          if (scheduledTarget != null) {
            final now = DateTime.now();
            if (scheduledTarget.isAfter(now)) {
              final remainingSec = scheduledTarget.difference(now).inSeconds;
              final remainingStr = '${remainingSec ~/ 60}m ${(remainingSec % 60).toString().padLeft(2, '0')}s';
              final formattedTarget = DateFormat('hh:mm:ss a').format(scheduledTarget);
              DatabaseService().logAppEvent(
                tag: 'BackupService',
                message: 'App resumed. Active 5-minute backup timer running (Target: $formattedTarget, $remainingStr remaining). If changes are made, timer will reset on exit.',
                level: 'INFO',
              );
            } else {
              backupService.clearScheduledBackupTargetTime();
            }
          }
        });
      } catch (e) {
        debugPrint('Failed to check scheduled backup status on resume: $e');
      }

      try {
        final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
        attendanceProvider.reloadAttendance(showLoading: false);
      } catch (e) {
        debugPrint('Failed to reload database on app resume: $e');
      }
      try {
        LiveTimetableSyncService().checkOnAppResume(context);
      } catch (e) {
        debugPrint('Failed to check live timetable on resume: $e');
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      try {
        final backupService = BackupService();
        backupService.cancelDebouncedAutoBackup();

        // Check prerequisites
        Future.wait([
          backupService.isBackupEnabled(),
          backupService.hasUserSetBackupDirectory(),
          DatabaseService().loadSemester(),
        ]).then((results) async {
          final isEnabled = results[0] as bool;
          final hasPath = results[1] as bool;
          final hasSemester = results[2] != null;

          if (!isEnabled || !hasPath || !hasSemester) {
            if (backupService.hasChangesInCurrentSession) {
              final reason = !isEnabled
                  ? 'Backups disabled in settings'
                  : !hasPath
                      ? 'No backup folder selected'
                      : 'No active semester exists';
              await DatabaseService().logAppEvent(
                tag: 'BackupService',
                message: '5-minute exit backup not scheduled: $reason.',
                level: 'WARNING',
              );
              backupService.resetSessionChangeFlag();
            }
            return;
          }

          if (backupService.hasChangesInCurrentSession) {
            final oldTarget = await backupService.getScheduledBackupTargetTime();
            final now = DateTime.now();
            final isReset = oldTarget != null && oldTarget.isAfter(now);

            final newTarget = now.add(const Duration(minutes: 5));

            if (isReset) {
              final remainingSec = oldTarget.difference(now).inSeconds;
              final remainingStr = '${remainingSec ~/ 60}m ${(remainingSec % 60).toString().padLeft(2, '0')}s';
              await DatabaseService().logAppEvent(
                tag: 'BackupService',
                message: '5-minute backup timer RESET: New data changes detected in session. Previous timer (target: ${DateFormat('hh:mm:ss a').format(oldTarget)}, $remainingStr remaining) replaced.',
                level: 'INFO',
              );
            } else {
              await DatabaseService().logAppEvent(
                tag: 'BackupService',
                message: 'Event triggered: Data changed in session. Scheduling 5-minute background backup.',
                level: 'INFO',
              );
            }

            await backupService.setScheduledBackupTargetTime(
              newTarget,
              reason: isReset ? 'Session changes reset' : 'Session changes',
            );

            await Workmanager().registerOneOffTask(
              'app_close_5min_backup',
              'appCloseBackupTask',
              initialDelay: const Duration(minutes: 5),
              existingWorkPolicy: ExistingWorkPolicy.replace,
              constraints: Constraints(
                requiresBatteryNotLow: false,
                requiresCharging: false,
                requiresDeviceIdle: false,
                requiresStorageNotLow: false,
                networkType: NetworkType.notRequired,
              ),
            );

            backupService.resetSessionChangeFlag();
          } else {
            // No changes in this session. Check if an existing timer is running.
            final existingTarget = await backupService.getScheduledBackupTargetTime();
            if (existingTarget != null && existingTarget.isAfter(DateTime.now())) {
              final remainingSec = existingTarget.difference(DateTime.now()).inSeconds;
              final remainingStr = '${remainingSec ~/ 60}m ${(remainingSec % 60).toString().padLeft(2, '0')}s';
              final formattedTarget = DateFormat('hh:mm:ss a').format(existingTarget);
              await DatabaseService().logAppEvent(
                tag: 'BackupService',
                message: 'App exited without new changes. Keeping existing 5-minute backup timer intact without reset (Target: $formattedTarget, $remainingStr remaining).',
                level: 'INFO',
              );
            }
          }
        });
      } catch (e) {
        debugPrint('Failed to handle 5-minute exit backup task: $e');
        DatabaseService().logAppEvent(
          tag: 'BackupService',
          message: 'Error handling 5-minute exit backup: $e',
          level: 'ERROR',
        );
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      // Check for updates on every app launch (regardless of last check time)
      final update = await _updateService.checkForUpdate();
      if (update != null && mounted) {
        setState(() {
          _pendingUpdate = update;
        });
        _showUpdateScreen(update);
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  Future<void> _checkForAnnouncements() async {
    try {
      final announcement = await GitHubDiscussionsService().checkForNewAnnouncement();
      if (announcement != null && mounted) {
        _showAnnouncementDialog(announcement);
      }
    } catch (e) {
      debugPrint('Error checking for announcements: $e');
    }
  }

  void _showAnnouncementDialog(GitHubDiscussion announcement) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: Colors.deepPurple),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'New Announcement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              announcement.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Text(
              announcement.markdownContent.length > 200
                  ? '${announcement.markdownContent.substring(0, 200).replaceAll('\n', ' ')}...'
                  : announcement.markdownContent,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              GitHubDiscussionsService().markAnnouncementAsSeen(announcement.id);
              Navigator.pop(dialogCtx);
            },
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              GitHubDiscussionsService().markAnnouncementAsSeen(announcement.id);
              Navigator.pop(dialogCtx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiscussionDetailScreen(discussion: announcement),
                ),
              );
            },
            child: const Text('Read Full Post'),
          ),
        ],
      ),
    );
  }

  void _showUpdateScreen(AppUpdate update) {
    var downloadProgress = 0.0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, routeSetState) => FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (routeContext, snapshot) {
              final currentVersion = snapshot.data?.version ?? '1.0.1';
              return UpdateFullScreen(
                update: update,
                currentVersion: currentVersion,
                isDownloading: _isDownloading,
                downloadProgress: downloadProgress,
                onInstallNow: () async {
                  routeSetState(() {
                    _isDownloading = true;
                    downloadProgress = 0.0;
                  });

                  if (!mounted) return;
                  final navigator = Navigator.of(routeContext);
                  final messenger = ScaffoldMessenger.of(routeContext);

                  try {
                    // Download APK with progress callback
                    final apkFile = await _updateService.downloadAPK(
                      _pendingUpdate!.version,
                      onProgress: (progress) {
                        if (mounted) {
                          routeSetState(() {
                            downloadProgress = progress;
                          });
                        }
                      },
                    );
                    if (apkFile != null && mounted) {
                      // Trigger installation
                      final installResult = await _updateService.installAPK(apkFile);
                      if (mounted) {
                        switch (installResult) {
                          case InstallResult.installerStarted:
                            navigator.pop();
                            messenger.showReplacingSnackBar(
                              const SnackBar(content: Text('Installer opened. Complete the update to continue.')),
                            );
                            break;
                          case InstallResult.permissionRequired:
                            messenger.showReplacingSnackBar(
                              const SnackBar(
                                content: Text('Allow installs from this source, then tap Install Now again.'),
                              ),
                            );
                            break;
                          case InstallResult.installerUnavailable:
                            messenger.showReplacingSnackBar(
                              const SnackBar(
                                content: Text('No installer found to open the APK on this device.'),
                              ),
                            );
                            break;
                          case InstallResult.failed:
                            messenger.showReplacingSnackBar(
                              const SnackBar(
                                content: Text('Failed to launch installer. APK saved for retry.'),
                              ),
                            );
                            break;
                        }
                      }
                    } else if (mounted) {
                      messenger.showReplacingSnackBar(
                        const SnackBar(content: Text('Failed to download update')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showReplacingSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  } finally {
                    if (mounted) {
                      routeSetState(() {
                        _isDownloading = false;
                      });
                    }
                  }
                },
                onRemindLater: () async {
                  if (!mounted) return;
                  final navigator = Navigator.of(routeContext);

                  try {
                    await _updateService.deferUpdate();
                    if (mounted) {
                      navigator.pop();
                    }
                  } catch (e) {
                    debugPrint('Error deferring update: $e');
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      _todayScheduleKey.currentState?.jumpToToday();
    }
    setState(() {
      _selectedIndex = index;
    });

    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    if (tutorialController.isActive && tutorialController.currentStep?.targetTabIndex == index) {
      if (tutorialController.currentStep?.isActionRequired == true) {
        final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
        if (semesterProvider.semester == null) return;
      }
      tutorialController.nextStep();
    }
  }

  Widget _buildSemesterRequiredWidget() {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: rs.insetsAll(24),
        child: Container(
          padding: rs.insetsAll(28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141416) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.9,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: rs.scale(58),
                height: rs.scale(58),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.school_rounded,
                  size: rs.scale(28),
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              SizedBox(height: rs.height(20)),
              Text(
                'Please Create a Semester',
                style: TextStyle(fontSize: rs.font(20), fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'You need to set up a semester before you can add subjects or track attendance.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: rs.font(13.5),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.black.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: rs.height(24)),
              ElevatedButton.icon(
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Go to Semester Setup'),
                onPressed: () {
                  setState(() {
                    _selectedIndex = 2; // Navigate to the Semester screen
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterYetToBeginWidget() {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    final startDate = semesterProvider.semester!.startDate;
    final formattedDate = '${startDate.day}/${startDate.month}/${startDate.year}';
    
    return Center(
      child: SingleChildScrollView(
        padding: rs.insetsAll(24),
        child: Container(
          padding: rs.insetsAll(28),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141416) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.9,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: rs.scale(58),
                height: rs.scale(58),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.pending_actions_rounded,
                  size: rs.scale(28),
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              SizedBox(height: rs.height(20)),
              Text(
                'Semester Yet to Begin',
                style: TextStyle(fontSize: rs.font(20), fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'Your semester will start on $formattedDate. Attendance tracking will begin from that date.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: rs.font(13.5),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.black.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: rs.height(24)),
              Wrap(
                spacing: rs.width(12),
                runSpacing: rs.height(12),
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('View Calendar'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CalendarScreen()),
                      );
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    label: const Text('Edit Semester'),
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 2; // Navigate to the Semester screen
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppFileIntentListener().updateContext(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final tutorialController = Provider.of<TutorialController>(context, listen: false);

    final bool isSemesterSet = semesterProvider.semester != null;
    final bool hasSemesterStarted = semesterProvider.hasSemesterStarted;
    final bool hasSemesterEnded = semesterProvider.hasSemesterEnded;

    final List<Widget> widgetOptions = <Widget>[
      isSemesterSet
          ? (hasSemesterStarted
              ? TodaySchedule(
                  key: _todayScheduleKey,
                  onDayChanged: (title, canGoPrev, canGoNext) {
                    if (mounted) {
                      setState(() {
                        _scheduleTitle = title;
                        _canGoPrevious = canGoPrev;
                        _canGoNext = canGoNext;
                      });
                    }
                  },
                )
              : _buildSemesterYetToBeginWidget())
          : _buildSemesterRequiredWidget(),
      isSemesterSet ? const SubjectScreen() : _buildSemesterRequiredWidget(),
      const SemesterScreen(),
      isSemesterSet
          ? (hasSemesterStarted ? const BunkMeterScreen() : _buildSemesterYetToBeginWidget())
          : _buildSemesterRequiredWidget(),
      const MoreScreen(),
    ];

    const List<String> appBarTitles = <String>[
      'Today',
      'Subjects',
      'Semester Details',
      'Bunk Meter',
      'More',
    ];

    return TutorialOverlay(
      child: DayCycleBackground(
        showGradient: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(_selectedIndex == 0 ? _scheduleTitle : appBarTitles[_selectedIndex]),
            actions: [
              if (_selectedIndex == 0 && isSemesterSet && hasSemesterStarted)
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: _canGoPrevious ? 'Previous Day' : null,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  onPressed: _canGoPrevious
                      ? () {
                          HapticFeedback.selectionClick();
                          _todayScheduleKey.currentState?.goToPreviousDay();
                        }
                      : null,
                ),
              if (isSemesterSet)
                IconButton(
                  icon: KeyedSubtree(key: _calendarKey, child: const Icon(Icons.calendar_month)),
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  onPressed: () {
                    if (tutorialController.isActive && tutorialController.currentStepIndex == 15) {
                      tutorialController.nextStep();
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CalendarScreen()),
                    );
                  },
                  tooltip: 'Attendance Calendar',
                ),
              if (_selectedIndex == 0 && isSemesterSet && hasSemesterStarted)
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: _canGoNext ? 'Next Day' : null,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  onPressed: _canGoNext
                      ? () {
                          HapticFeedback.selectionClick();
                          _todayScheduleKey.currentState?.goToNextDay();
                        }
                      : null,
                ),
              if (_selectedIndex == 1 && isSemesterSet && !hasSemesterEnded)
                IconButton(
                  icon: KeyedSubtree(key: _importKey, child: const Icon(Icons.download_for_offline)),
                  onPressed: () {
                    if (tutorialController.isActive && tutorialController.currentStepIndex == 10) {
                      tutorialController.nextStep();
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UnifiedImportScreen(initialTabIndex: 0),
                      ),
                    );
                  },
                  tooltip: 'Import Data',
                ),
              if ((_selectedIndex == 2 && isSemesterSet) || (_selectedIndex == 3 && isSemesterSet && hasSemesterStarted))
                IconButton(
                  icon: const Icon(Icons.download_for_offline),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UnifiedImportScreen(initialTabIndex: 1),
                      ),
                    );
                  },
                  tooltip: 'Import Data',
                ),
              PopupMenuButton<ThemeMode>(
                tooltip: 'Theme',
                icon: Icon(
                  switch (themeProvider.themeMode) {
                    ThemeMode.light => Icons.light_mode,
                    ThemeMode.dark => Icons.dark_mode,
                    ThemeMode.system => Icons.phone_android,
                  },
                ),
                onSelected: (mode) => themeProvider.setThemeMode(mode),
                itemBuilder: (context) => [
                  const PopupMenuItem<ThemeMode>(
                    value: ThemeMode.light,
                    child: Row(
                      children: [
                        Icon(Icons.light_mode),
                        SizedBox(width: 12),
                        Text('Light'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<ThemeMode>(
                    value: ThemeMode.dark,
                    child: Row(
                      children: [
                        Icon(Icons.dark_mode),
                        SizedBox(width: 12),
                        Text('Dark'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<ThemeMode>(
                    value: ThemeMode.system,
                    child: Row(
                      children: [
                        Icon(Icons.phone_android),
                        SizedBox(width: 12),
                        Text('System'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: widgetOptions,
          ),
        bottomNavigationBar: AttendMateDock(
          selectedIndex: _selectedIndex,
          onItemTapped: _onItemTapped,
          todayKey: _todayTabKey,
          subjectsKey: _subjectTabKey,
          semesterKey: _semesterTabKey,
          bunkKey: _bunkTabKey,
          moreKey: _moreTabKey,
        ),
        floatingActionButton: _selectedIndex == 1 && isSemesterSet && !hasSemesterEnded
            ? FloatingActionButton(
                key: _fabKey,
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  if (tutorialController.isActive && tutorialController.currentStepIndex == 4) {
                    tutorialController.nextStep();
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddSubjectScreen()),
                  );
                },
                child: const Icon(Icons.add),
              )
            : null,
        ),
      ),
    );
  }
}
