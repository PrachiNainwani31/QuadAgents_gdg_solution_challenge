import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../theme.dart';
import '../../models/need_card.dart';
import '../../services/firebase_service.dart';
import '../../services/geocoding_service.dart';

/// TaskDetailView — shows full need details, embedded coordinator map,
/// and accept/decline flow.
/// Requirements 6.1, 6.2, 6.3, 6.5, 10.3
class TaskDetailView extends StatefulWidget {
  final NeedCard need;
  const TaskDetailView({super.key, required this.need});

  @override
  State<TaskDetailView> createState() => _TaskDetailViewState();
}

class _TaskDetailViewState extends State<TaskDetailView> {
  bool _isLoading = false;
  String? _ngoName;
  String? _coordinatorAddress;
  double? _coordinatorLat;
  double? _coordinatorLng;

  @override
  void initState() {
    super.initState();
    _loadNgoDetails();
  }

  Future<void> _loadNgoDetails() async {
    final ngo = await FirebaseService.getNgoProfile(widget.need.ngoId);
    if (ngo != null && mounted) {
      double? lat = (ngo['coordinatorLat'] as num?)?.toDouble();
      double? lng = (ngo['coordinatorLng'] as num?)?.toDouble();

      // If no stored coords, geocode the coordinator address
      if ((lat == null || lng == null) && ngo['coordinatorAddress'] != null) {
        final geo = await GeocodingService.geocodeAddress(ngo['coordinatorAddress'] as String);
        if (geo != null) { lat = geo.lat; lng = geo.lng; }
      }

      // Final fallback: use the need's own lat/lng
      if (lat == null || lng == null) {
        if (widget.need.lat != 0.0 || widget.need.lng != 0.0) {
          lat = widget.need.lat;
          lng = widget.need.lng;
        } else {
          // Geocode the need's location string
          final geo = await GeocodingService.geocodeAddress(widget.need.location);
          if (geo != null) { lat = geo.lat; lng = geo.lng; }
        }
      }

      if (mounted) {
        setState(() {
          _ngoName = ngo['name'] as String?;
          _coordinatorAddress = ngo['coordinatorAddress'] as String? ?? widget.need.location;
          _coordinatorLat = lat;
          _coordinatorLng = lng;
        });
      }
    } else if (mounted) {
      // No NGO profile — fall back to need location
      double? lat, lng;
      if (widget.need.lat != 0.0 || widget.need.lng != 0.0) {
        lat = widget.need.lat;
        lng = widget.need.lng;
      } else {
        final geo = await GeocodingService.geocodeAddress(widget.need.location);
        if (geo != null) { lat = geo.lat; lng = geo.lng; }
      }
      if (mounted) {
        setState(() {
          _coordinatorAddress = widget.need.location;
          _coordinatorLat = lat;
          _coordinatorLng = lng;
        });
      }
    }
  }

  bool get _isExpired => widget.need.deadline.isBefore(DateTime.now());

  Color _urgencyColor(int urgency) {
    if (urgency <= 2) return AppTheme.successGreen;
    if (urgency == 3) return AppTheme.warningOrange;
    return AppTheme.errorRed;
  }

  String _urgencyLabel(int urgency) {
    if (urgency <= 2) return 'Low';
    if (urgency == 3) return 'Medium';
    if (urgency == 4) return 'High';
    return 'Critical';
  }

  Future<void> _accept() async {
    // Requirement 6.5: check deadline before accepting
    if (_isExpired) {
      _showSnack('This task deadline has passed. You cannot accept it.', isError: true);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      // Requirement 6.2: create assignment with status 'invited', then accept
      final assignmentId = await FirebaseService.createAssignment({
        'needId': widget.need.id,
        'volunteerId': uid,
        'ngoId': widget.need.ngoId,
      });

      // Advance to accepted
      await FirebaseService.updateAssignmentStatus(assignmentId, 'accepted');

      // Requirement 8.1: auto-create chat room when 2+ volunteers are assigned.
      // Fetch all accepted/in-progress assignments for this need.
      final assignmentsSnap = await FirebaseService
          .getAssignmentsStream(needId: widget.need.id)
          .first;
      final acceptedVolunteers = assignmentsSnap.docs
          .where((d) {
            final s = (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
            return ['accepted', 'in-progress', 'reported', 'verified'].contains(s);
          })
          .map((d) => (d.data() as Map<String, dynamic>)['volunteerId'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      // Always include current volunteer and NGO coordinator in the room.
      final participants = {...acceptedVolunteers, uid, widget.need.ngoId}.toList();

      if (participants.length >= 2) {
        // Use needId as the chat room id so all volunteers share the same room.
        await FirebaseService.ensureChatRoom(widget.need.id, participants);
      }

      // Notify NGO admin (Requirement 6.2)
      await FirebaseService.createNotification(widget.need.ngoId, {
        'type': 'assignment',
        'title': 'Volunteer accepted: ${widget.need.title}',
        'body': 'A volunteer has accepted your task.',
        'relatedId': assignmentId,
      });

      if (mounted) {
        _showSnack('Task accepted! Check My Tasks for updates.', isError: false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _decline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      // Requirement 6.3: create assignment then immediately decline
      final assignmentId = await FirebaseService.createAssignment({
        'needId': widget.need.id,
        'volunteerId': uid,
        'ngoId': widget.need.ngoId,
      });

      // Mark as declined by updating to a terminal note in Firestore directly
      // (declined is not in the Kanban order — we store it as a separate field)
      await FirebaseService.declineAssignment(assignmentId);

      // Notify NGO to offer to next ranked volunteer (Requirement 6.3)
      await FirebaseService.createNotification(widget.need.ngoId, {
        'type': 'assignment',
        'title': 'Volunteer declined: ${widget.need.title}',
        'body': 'A volunteer declined. Consider inviting the next ranked match.',
        'relatedId': assignmentId,
      });

      if (mounted) {
        _showSnack('Task declined.', isError: false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.errorRed : AppTheme.successGreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final need = widget.need;
    final urgencyColor = _urgencyColor(need.urgency);
    final deadlineStr = '${need.deadline.day}/${need.deadline.month}/${need.deadline.year}';

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Task Details', style: Theme.of(context).textTheme.titleMedium),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.borderGrey),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: main details
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusBadge(urgencyColor, need.urgency),
                  const SizedBox(height: 16),
                  Text(need.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textGrey),
                      const SizedBox(width: 4),
                      Text(need.location,
                          style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionCard(
                    title: 'Description',
                    icon: Icons.description_outlined,
                    child: Text(need.description,
                        style: const TextStyle(fontSize: 14, height: 1.6, color: AppTheme.textDark)),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: 'Required Skills',
                    icon: Icons.psychology_outlined,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: need.skills
                          .map((s) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: AppTheme.primaryPurple.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppTheme.primaryPurple.withOpacity(0.2))),
                                child: Text(s,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.primaryPurple)),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: 'Task Details',
                    icon: Icons.info_outline,
                    child: Column(
                      children: [
                        _detailRow(Icons.category_outlined, 'Category', need.category),
                        _detailRow(Icons.calendar_today_outlined, 'Deadline', deadlineStr),
                        _detailRow(
                          Icons.warning_amber_outlined,
                          'Urgency',
                          _urgencyLabel(need.urgency),
                          valueColor: urgencyColor,
                        ),
                        if (_ngoName != null)
                          _detailRow(Icons.business_outlined, 'NGO', _ngoName!),
                        if (_coordinatorAddress != null)
                          _detailRow(
                              Icons.place_outlined, 'Coordinator Point', _coordinatorAddress!),
                      ],
                    ),
                  ),
                  if (_isExpired) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: AppTheme.errorRed.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.errorRed.withOpacity(0.3))),
                      child: const Row(
                        children: [
                          Icon(Icons.error_outline, color: AppTheme.errorRed),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This task deadline has passed. Acceptance is no longer available.',
                              style: TextStyle(color: AppTheme.errorRed, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildActionButtons(),
                ],
              ),
            ),
            const SizedBox(width: 32),
            // Right: coordinator map
            Expanded(
              flex: 2,
              child: _buildCoordinatorMap(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(Color color, int urgency) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3))),
          child: Row(
            children: [
              Icon(Icons.schedule, size: 14, color: color),
              const SizedBox(width: 6),
              Text(_urgencyLabel(urgency),
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: AppTheme.successGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20)),
          child: const Text('Open',
              style: TextStyle(
                  color: AppTheme.successGreen, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGrey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryPurple),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textGrey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(fontSize: 13, color: AppTheme.textGrey)),
          Flexible(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppTheme.textDark),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_isExpired) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          child: const Text('Deadline Expired'),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _accept,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Accept Task'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : _decline,
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                foregroundColor: AppTheme.errorRed,
                side: const BorderSide(color: AppTheme.errorRed)),
            child: const Text('Decline'),
          ),
        ),
      ],
    );
  }

  // Requirement 10.3: embedded OSM map showing coordinator/need location
  Widget _buildCoordinatorMap() {
    final hasCoords = _coordinatorLat != null && _coordinatorLng != null;
    final center = hasCoords
        ? LatLng(_coordinatorLat!, _coordinatorLng!)
        : const LatLng(20.0, 0.0);

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGrey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.place, color: AppTheme.primaryPurple, size: 18),
                const SizedBox(width: 8),
                const Text('Coordinator Location',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.borderGrey),
          ClipRRect(
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            child: SizedBox(
              height: 280,
              child: hasCoords
                  ? FlutterMap(
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 13.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.ngoconnect.app',
                        ),
                        MarkerLayer(markers: [
                          Marker(
                            point: center,
                            width: 40,
                            height: 40,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: AppTheme.primaryPurple,
                                      borderRadius: BorderRadius.circular(4)),
                                  child: const Text('Here',
                                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                                const Icon(Icons.location_on, color: AppTheme.primaryPurple, size: 24),
                              ],
                            ),
                          ),
                        ]),
                      ],
                    )
                  : const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 8),
                          Text('Loading location...',
                              style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
                        ],
                      ),
                    ),
            ),
          ),
          if (_coordinatorAddress != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: AppTheme.textGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(_coordinatorAddress!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
