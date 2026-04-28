import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../../../theme.dart';
import '../../../services/firebase_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/matching_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// VolunteerProfileView — full profile with skills, languages, availability,
/// preferred causes, past experience, location, and live stats.
/// Requirements 4.1, 4.2, 4.3, 4.4, 4.5, 9.4
class VolunteerProfileView extends StatefulWidget {
  const VolunteerProfileView({super.key});
  @override
  State<VolunteerProfileView> createState() => _VolunteerProfileViewState();
}

class _VolunteerProfileViewState extends State<VolunteerProfileView> {
  // ── Skill taxonomy ─────────────────────────────────────────────────────────
  static const _allSkills = [
    'React', 'Flutter', 'Python', 'Node.js', 'Teaching', 'Medical',
    'Legal', 'Logistics', 'Figma', 'Photography', 'Writing', 'ESL',
    'Food Safety', 'Counseling', 'Data Entry', 'Social Media', 'Leadership',
    'TypeScript', 'Java', 'Kotlin', 'Swift', 'DevOps', 'Machine Learning',
  ];

  static const _allLanguages = [
    'English', 'Hindi', 'Spanish', 'French', 'Arabic', 'Mandarin',
    'Portuguese', 'Bengali', 'Urdu', 'Swahili', 'German', 'Japanese',
  ];

  static const _allCauses = [
    'Education', 'Healthcare', 'Environment', 'Poverty Alleviation',
    'Women Empowerment', 'Child Welfare', 'Disaster Relief',
    'Animal Welfare', 'Mental Health', 'Elderly Care',
  ];

  static const _availabilityOptions = [
    'Weekdays', 'Weekends', 'Evenings', 'Full-time', 'Flexible'
  ];

  // ── State ──────────────────────────────────────────────────────────────────
  List<String> _selectedSkills = [];
  List<String> _selectedLanguages = [];
  List<String> _selectedCauses = [];
  String _availability = 'Weekends';
  String _pastExperience = '';
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isLocating = false;

  // Live stats from Firestore (Requirement 9.4)
  double _averageRating = 0.0;
  int _completedTaskCount = 0;

  final _locationController = TextEditingController();
  final _pastExperienceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _pastExperienceController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile = await FirebaseService.getUserProfile(uid);
    if (profile != null && mounted) {
      setState(() {
        _selectedSkills = List<String>.from(profile['skills'] ?? []);
        _selectedLanguages = List<String>.from(profile['languages'] ?? []);
        _selectedCauses = List<String>.from(profile['preferredCauses'] ?? []);
        _availability = profile['availability'] as String? ?? 'Weekends';
        _pastExperience = profile['pastExperience'] as String? ?? '';
        _locationController.text = profile['location'] as String? ?? '';
        _pastExperienceController.text = _pastExperience;
        _averageRating = (profile['averageRating'] as num?)?.toDouble() ?? 0.0;
        _completedTaskCount = (profile['completedTaskCount'] as num?)?.toInt() ?? 0;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      html.window.navigator.geolocation.getCurrentPosition().then((pos) async {
        final lat = pos.coords!.latitude!.toDouble();
        final lng = pos.coords!.longitude!.toDouble();
        await _onLocationObtained(lat, lng);
      }).catchError((e) {
        if (mounted) {
          setState(() => _isLocating = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Location denied: $e'),
            backgroundColor: AppTheme.warningOrange,
          ));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLocating = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Geolocation not supported in this browser.'),
          backgroundColor: AppTheme.warningOrange,
        ));
      }
    }
  }

  Future<void> _onLocationObtained(double lat, double lng) async {
    // Reverse geocode lat/lng → address via backend
    try {
      final result = await GeocodingService.reverseGeocode(lat, lng);
      if (mounted) {
        setState(() {
          _locationController.text = result ?? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
          _isLocating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Location set: ${_locationController.text}'),
          backgroundColor: AppTheme.successGreen,
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationController.text = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    // Requirement 4.4: warn if no skills selected
    if (_selectedSkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one skill before saving.'),
          backgroundColor: AppTheme.warningOrange,
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isSaving = true);

    final locationText = _locationController.text.trim();
    double lat = 0.0;
    double lng = 0.0;

    // Requirement 4.2: resolve address → lat/lng
    if (locationText.isNotEmpty) {
      final geo = await GeocodingService.geocodeAddress(locationText);
      if (geo != null) {
        lat = geo.lat;
        lng = geo.lng;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Address not found — coordinates not updated.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    await FirebaseService.updateVolunteerProfile(uid, {
      'skills': _selectedSkills,
      'languages': _selectedLanguages,
      'availability': _availability,
      'location': locationText,
      'lat': lat,
      'lng': lng,
      'preferredCauses': _selectedCauses,
      'pastExperience': _pastExperienceController.text.trim(),
    });

    // Requirement 4.5: re-run matching for all open needs
    try {
      await MatchingService.matchVolunteerToNeeds(uid);
    } catch (_) {
      // Non-fatal — matching failure should not block profile save
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved and matches updated!'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Profile', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 4),
          const Text('Keep your profile updated for better AI matches',
              style: TextStyle(color: AppTheme.textGrey)),
          const SizedBox(height: 24),

          // Stats row (Requirement 9.4)
          _buildStatsRow(),
          const SizedBox(height: 24),

          // Skills
          _buildSection(
            title: 'Your Skills',
            icon: Icons.psychology,
            subtitle: 'Select all skills that apply — used for AI matching',
            child: _buildChipSelector(
              items: _allSkills,
              selected: _selectedSkills,
              onToggle: (s) => setState(() =>
                  _selectedSkills.contains(s)
                      ? _selectedSkills.remove(s)
                      : _selectedSkills.add(s)),
            ),
          ),
          const SizedBox(height: 20),

          // Languages
          _buildSection(
            title: 'Languages',
            icon: Icons.translate,
            subtitle: 'Languages you can communicate in',
            child: _buildChipSelector(
              items: _allLanguages,
              selected: _selectedLanguages,
              onToggle: (l) => setState(() =>
                  _selectedLanguages.contains(l)
                      ? _selectedLanguages.remove(l)
                      : _selectedLanguages.add(l)),
            ),
          ),
          const SizedBox(height: 20),

          // Preferred Causes
          _buildSection(
            title: 'Preferred Causes',
            icon: Icons.favorite_border,
            subtitle: 'Causes you are passionate about',
            child: _buildChipSelector(
              items: _allCauses,
              selected: _selectedCauses,
              onToggle: (c) => setState(() =>
                  _selectedCauses.contains(c)
                      ? _selectedCauses.remove(c)
                      : _selectedCauses.add(c)),
            ),
          ),
          const SizedBox(height: 20),

          // Availability + Location
          _buildSection(
            title: 'Availability & Location',
            icon: Icons.schedule,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Availability',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: _availabilityOptions.map((a) {
                    final selected = _availability == a;
                    return GestureDetector(
                      onTap: () => setState(() => _availability = a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primaryPurple.withOpacity(0.1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: selected
                                  ? AppTheme.primaryPurple
                                  : AppTheme.borderGrey),
                        ),
                        child: Text(a,
                            style: TextStyle(
                              color: selected
                                  ? AppTheme.primaryPurple
                                  : AppTheme.textDark,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            )),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text('Location',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _locationController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Mumbai, Remote',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isLocating ? null : _useCurrentLocation,
                      icon: _isLocating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.my_location, size: 16),
                      label: const Text('Use Current', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Past Experience
          _buildSection(
            title: 'Past Experience',
            icon: Icons.work_history_outlined,
            subtitle: 'Briefly describe your volunteer or work experience',
            child: TextFormField(
              controller: _pastExperienceController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText:
                    'e.g. Volunteered at local food bank for 2 years, taught coding to underprivileged youth...',
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save Profile & Update Matches',
                      style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Row(
      children: [
        _statCard(
          icon: Icons.star,
          iconColor: AppTheme.warningOrange,
          label: 'Average Rating',
          value: _averageRating > 0
              ? _averageRating.toStringAsFixed(1)
              : '—',
          subtitle: 'out of 5.0',
        ),
        const SizedBox(width: 16),
        _statCard(
          icon: Icons.check_circle_outline,
          iconColor: AppTheme.successGreen,
          label: 'Tasks Completed',
          value: '$_completedTaskCount',
          subtitle: 'total',
        ),
        const SizedBox(width: 16),
        _statCard(
          icon: Icons.psychology,
          iconColor: AppTheme.primaryPurple,
          label: 'Skills',
          value: '${_selectedSkills.length}',
          subtitle: 'selected',
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGrey),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textGrey)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textGrey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryPurple),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildChipSelector({
    required List<String> items,
    required List<String> selected,
    required void Function(String) onToggle,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        final isSelected = selected.contains(item);
        return GestureDetector(
          onTap: () => onToggle(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryPurple : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isSelected
                      ? AppTheme.primaryPurple
                      : AppTheme.borderGrey),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(Icons.check, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Text(item,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textDark,
                      fontWeight: FontWeight.w500,
                    )),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
