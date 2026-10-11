import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/database_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/day_cycle_background.dart';
import 'location_map_picker.dart';
import 'location_model.dart';

class LocationManagerScreen extends StatefulWidget {
  const LocationManagerScreen({super.key});

  @override
  State<LocationManagerScreen> createState() => _LocationManagerScreenState();
}

class _LocationManagerScreenState extends State<LocationManagerScreen> {
  List<LocationConfig> _locations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLocations(showLoading: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleLocationPermission();
    });
  }

  Future<void> _loadLocations({bool showLoading = false}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final locs = await DatabaseService().loadLocations();
      if (mounted) {
        setState(() {
          _locations = locs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        SnackbarUtils.showErrorSnackBar(context, 'Failed to load locations: $e');
      }
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Location services are disabled. Please enable them.');
      }
      return false;
    }

    // ── Step 1: Foreground permission ─────────────────────────────────────
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'Location permissions are denied.');
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permissions are permanently denied.'),
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ),
        );
      }
      return false;
    }

    // ── Step 2: Precise location (Android 12+) ────────────────────────────
    try {
      final accuracy = await Geolocator.getLocationAccuracy();
      if (accuracy == LocationAccuracyStatus.reduced && mounted) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        await showDialog(
          context: context,
          barrierColor: isDarkMode ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.3),
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Precise Location Required'),
            content: const Text(
              'AttendMate needs "Precise" location to distinguish between classrooms within 25 metres. Please enable Precise location in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Geolocator.openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}

    // ── Step 3: Background location (needed for auto-attendance) ──────────
    if (permission == LocationPermission.whileInUse && mounted) {
      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
      final wantsBackground = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: isDarkMode ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.3),
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.sensors, size: 36),
          title: const Text('Background Location'),
          content: const Text(
            'Auto-attendance checks your location 5 minutes after a class starts — even when the app is closed.\n\n'
            'For this to work, please change the location permission to "Allow all the time" on the next screen.\n\n'
            'We never track you outside of class windows.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Go to Settings'),
            ),
          ],
        ),
      );

      if (wantsBackground == true) {
        final bgPermission = await Geolocator.requestPermission();
        if (bgPermission != LocationPermission.always && mounted) {
          await Geolocator.openAppSettings();
        }
      }
    }

    return true;
  }

  Future<void> _showMapPickerDialog(
    Function(double lat, double lng) onSelect, {
    double? initialLat,
    double? initialLng,
  }) async {
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (ctx) => InteractiveMapPickerDialog(
        initialLatitude: initialLat,
        initialLongitude: initialLng,
      ),
    );

    if (result != null && result.containsKey('latitude') && result.containsKey('longitude')) {
      onSelect(result['latitude']!, result['longitude']!);
    }
  }

  void _showAddEditLocationSheet([LocationConfig? location]) {
    final nameController = TextEditingController(text: location?.name);
    final blockController = TextEditingController(text: location?.block);
    double? latitude = location?.latitude;
    double? longitude = location?.longitude;
    bool isFetchingGps = false;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: isDarkMode ? Colors.black.withValues(alpha: 0.65) : Colors.black.withValues(alpha: 0.35),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final colorScheme = Theme.of(context).colorScheme;
          final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: viewInsets),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF0D0D14).withValues(alpha: 0.88)
                        : Colors.white.withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.08),
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Pill
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 18),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Title & Subtitle Row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Icon(
                                location == null ? Icons.add_location_alt_rounded : Icons.edit_location_alt_rounded,
                                color: colorScheme.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    location == null ? 'Add Campus Location' : 'Edit Location',
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Configure coordinates for 25m auto-attendance',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        // Room / Location Name Input
                        TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Room / Lecture Hall',
                            hintText: 'e.g., Room 402, Lab A, Audi 1',
                            filled: true,
                            fillColor: isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Block / Building Input
                        TextFormField(
                          controller: blockController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'Block / Building (Optional)',
                            hintText: 'e.g., Block C, CSE Dept, Science Wing',
                            filled: true,
                            fillColor: isDarkMode
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            prefixIcon: const Icon(Icons.business_outlined, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Coordinate Status Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'GEOFENCE COORDINATES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (latitude != null && longitude != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Locked',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Coordinate Display Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: latitude != null && longitude != null
                                ? Colors.green.withValues(alpha: 0.08)
                                : (isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: latitude != null && longitude != null
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : (isDarkMode ? Colors.white12 : Colors.grey.shade300),
                            ),
                          ),
                          child: latitude != null && longitude != null
                              ? Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.gps_fixed, color: Colors.green, size: 18),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${latitude!.toStringAsFixed(6)}°, ${longitude!.toStringAsFixed(6)}°',
                                            style: GoogleFonts.robotoMono(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            '25m radius geofence active',
                                            style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      tooltip: 'Clear coordinates',
                                      color: colorScheme.error,
                                      onPressed: () {
                                        setSheetState(() {
                                          latitude = null;
                                          longitude = null;
                                        });
                                      },
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Icon(
                                      Icons.location_off_outlined,
                                      size: 20,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'No coordinates assigned yet. Use GPS or Map Picker below.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        const SizedBox(height: 14),

                        // Action Buttons: Use GPS & Pick on Map
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: isFetchingGps
                                    ? null
                                    : () async {
                                        final hasPermission = await _handleLocationPermission();
                                        if (!hasPermission) return;

                                        setSheetState(() => isFetchingGps = true);
                                        try {
                                          Position? pos;
                                          try {
                                            pos = await Geolocator.getCurrentPosition(
                                              locationSettings: const LocationSettings(
                                                accuracy: LocationAccuracy.high,
                                                timeLimit: Duration(seconds: 15),
                                              ),
                                            );
                                          } catch (_) {
                                            pos = await Geolocator.getLastKnownPosition();
                                          }

                                          final currentPos = pos;
                                          if (currentPos != null) {
                                            setSheetState(() {
                                              latitude = currentPos.latitude;
                                              longitude = currentPos.longitude;
                                              isFetchingGps = false;
                                            });
                                          } else {
                                            setSheetState(() => isFetchingGps = false);
                                            if (mounted) {
                                              SnackbarUtils.showErrorSnackBar(
                                                context,
                                                'Could not obtain GPS location. Please try Map Picker.',
                                              );
                                            }
                                          }
                                        } catch (e) {
                                          setSheetState(() => isFetchingGps = false);
                                          if (mounted) {
                                            SnackbarUtils.showErrorSnackBar(context, 'Error getting coordinates: $e');
                                          }
                                        }
                                      },
                                icon: isFetchingGps
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location, size: 16),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(isFetchingGps ? 'Locating...' : 'Use Current GPS'),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _showMapPickerDialog(
                                    (lat, lng) {
                                      setSheetState(() {
                                        latitude = lat;
                                        longitude = lng;
                                      });
                                    },
                                    initialLat: latitude,
                                    initialLng: longitude,
                                  );
                                },
                                icon: const Icon(Icons.map_outlined, size: 16),
                                label: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('Select on Map'),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Action Row: Cancel & Save
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton(
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    SnackbarUtils.showErrorSnackBar(context, 'Room / Location Name is required');
                                    return;
                                  }

                                  if (latitude != null && (latitude! < -90.0 || latitude! > 90.0)) {
                                    SnackbarUtils.showErrorSnackBar(
                                      context,
                                      'Invalid Latitude: Must be between -90.0° and +90.0°',
                                    );
                                    return;
                                  }

                                  if (longitude != null && (longitude! < -180.0 || longitude! > 180.0)) {
                                    SnackbarUtils.showErrorSnackBar(
                                      context,
                                      'Invalid Longitude: Must be between -180.0° and +180.0°',
                                    );
                                    return;
                                  }

                                  final newLoc = LocationConfig(
                                    id: location?.id ?? const Uuid().v4(),
                                    name: name,
                                    block: blockController.text.trim().isEmpty ? null : blockController.text.trim(),
                                    latitude: latitude,
                                    longitude: longitude,
                                  );

                                  Navigator.pop(sheetContext);
                                  await DatabaseService().saveLocation(newLoc);
                                  _loadLocations(showLoading: false);
                                  if (mounted) {
                                    SnackbarUtils.showSuccessSnackBar(
                                      context,
                                      location == null ? 'Location added successfully.' : 'Location updated.',
                                    );
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  location == null ? 'Save Location' : 'Update Location',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
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
          );
        },
      ),
    );
  }

  Future<void> _deleteLocation(LocationConfig loc) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: isDarkMode ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Location?'),
        content: Text(
          'Are you sure you want to delete "${loc.name}"? Subjects linked to this room will revert to text-only location mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService().deleteLocation(loc.id);
      _loadLocations(showLoading: false);
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Location deleted.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    final mappedCount = _locations.where((l) => l.latitude != null && l.longitude != null).length;

    return DayCycleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Locations & Geofencing'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // ── Hero Glass Header Banner ─────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF0F0F16).withValues(alpha: 0.60)
                              : Colors.white.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.radar_rounded,
                                    color: colorScheme.primary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Campus Geofencing',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Automated Attendance Verification',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Text(
                                    '25m Radius',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'When enabled, AttendMate monitors background proximity during class timeslots to verify your presence in configured lecture halls.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 14),

                            // Quick Stats Strip
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatItem(
                                    title: 'CONFIGURED',
                                    value: '${_locations.length}',
                                    icon: Icons.meeting_room_outlined,
                                    colorScheme: colorScheme,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 32,
                                  color: isDarkMode ? Colors.white12 : Colors.black12,
                                ),
                                Expanded(
                                  child: _buildStatItem(
                                    title: 'GPS MAPPED',
                                    value: '$mappedCount',
                                    icon: Icons.gps_fixed,
                                    colorScheme: colorScheme,
                                    color: Colors.green,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 32,
                                  color: isDarkMode ? Colors.white12 : Colors.black12,
                                ),
                                Expanded(
                                  child: _buildStatItem(
                                    title: 'UNMAPPED',
                                    value: '${_locations.length - mappedCount}',
                                    icon: Icons.location_off_outlined,
                                    colorScheme: colorScheme,
                                    color: (_locations.length - mappedCount) > 0 ? Colors.orange : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Section Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CONFIGURED ROOMS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${_locations.length} room${_locations.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ── Locations List or Empty State ────────────────────────
                  if (_locations.isEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF14141E).withValues(alpha: 0.50)
                                : Colors.white.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.pin_drop_outlined,
                                  size: 40,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Campus Locations Yet',
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add your lecture halls, laboratories, or seminar halls to enable automated geofenced attendance.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 22),
                              FilledButton.icon(
                                onPressed: () => _showAddEditLocationSheet(),
                                icon: const Icon(Icons.add_location_alt_rounded),
                                label: const Text('Add First Location'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ..._locations.map((loc) => _buildLocationCard(loc, colorScheme, isDarkMode)),

                  const SizedBox(height: 80),
                ],
              ),
        floatingActionButton: _locations.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showAddEditLocationSheet(),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Add Location'),
              ),
      ),
    );
  }

  Widget _buildStatItem({
    required String title,
    required String value,
    required IconData icon,
    required ColorScheme colorScheme,
    Color? color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color ?? colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color ?? colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(LocationConfig loc, ColorScheme colorScheme, bool isDarkMode) {
    final hasGps = loc.latitude != null && loc.longitude != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF13131B).withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.11)
                    : Colors.black.withValues(alpha: 0.07),
                width: 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location Icon Avatar
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: hasGps
                            ? Colors.green.withValues(alpha: 0.14)
                            : colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hasGps
                              ? Colors.green.withValues(alpha: 0.3)
                              : (isDarkMode ? Colors.white12 : Colors.black12),
                        ),
                      ),
                      child: Icon(
                        hasGps ? Icons.gps_fixed : Icons.location_off_outlined,
                        size: 20,
                        color: hasGps ? Colors.green : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Title & Building
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.name,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            loc.block != null && loc.block!.isNotEmpty
                                ? 'Building / Block: ${loc.block}'
                                : 'No building specified',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Geofence status pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasGps
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: hasGps
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: hasGps ? Colors.green : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            hasGps ? 'Geofence Active' : 'No GPS',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: hasGps ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Coordinate Chip or Warning Strip
                if (hasGps)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pin_drop, size: 14, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${loc.latitude!.toStringAsFixed(6)}°,  ${loc.longitude!.toStringAsFixed(6)}°',
                            style: GoogleFonts.robotoMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                    ),
                    child: const Text(
                      'No coordinates set. Auto-attendance will skip geofencing for this location.',
                      style: TextStyle(fontSize: 11.5, color: Colors.orange, height: 1.3),
                    ),
                  ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Action Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (hasGps) ...[
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          _showMapPickerDialog(
                            (lat, lng) async {
                              final updated = LocationConfig(
                                id: loc.id,
                                name: loc.name,
                                block: loc.block,
                                latitude: lat,
                                longitude: lng,
                              );
                              await DatabaseService().saveLocation(updated);
                              _loadLocations(showLoading: false);
                            },
                            initialLat: loc.latitude,
                            initialLng: loc.longitude,
                          );
                        },
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label: const Text('View on Map', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 6),
                    ],
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _showAddEditLocationSheet(loc),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _deleteLocation(loc),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Delete', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
