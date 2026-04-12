import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../theme.dart';

/// NgoOverviewView — live Firestore stats dashboard.
/// Requirements 12.1, 12.2: all metrics sourced from live Firestore queries.
/// All orderBy clauses removed from compound queries to avoid composite index
/// requirements — sorting is done client-side instead.
class NgoOverviewView extends StatelessWidget {
  final String ngoId;
  const NgoOverviewView({super.key, required this.ngoId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 24),
        _buildStatsRow(),
        const SizedBox(height: 24),
        _buildRecentNeedsCard(context),
        const SizedBox(height: 24),
        _buildRecentAssignmentsCard(context),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('ngos').doc(ngoId).get(),
      builder: (context, snap) {
        final name =
            (snap.data?.data() as Map<String, dynamic>?)?['name'] as String? ??
                'Your Organization';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back, $name',
                style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 4),
            Text("Here's a live overview of your organization's activity.",
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
      },
    );
  }

  Widget _buildStatsRow() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('needs')
          .where('ngoId', isEqualTo: ngoId)
          .snapshots(),
      builder: (context, needsSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('task_assignments')
              .where('ngoId', isEqualTo: ngoId)
              .snapshots(),
          builder: (context, assignSnap) {
            final needsDocs = needsSnap.data?.docs ?? [];
            final assignDocs = assignSnap.data?.docs ?? [];

            final totalNeeds = needsDocs.length;
            final openNeeds =
                needsDocs.where((d) => d['status'] == 'open').length;
            final fulfilledNeeds =
                needsDocs.where((d) => d['status'] == 'closed').length;
            final activeVolunteers =
                assignDocs.map((d) => d['volunteerId']).toSet().length;

            return Row(
              children: [
                Expanded(
                    child: _statCard('Total Needs Posted', '$totalNeeds',
                        Icons.assignment_outlined, AppTheme.primaryPurple)),
                const SizedBox(width: 16),
                Expanded(
                    child: _statCard('Open Needs', '$openNeeds',
                        Icons.pending_actions_outlined, AppTheme.infoBlue)),
                const SizedBox(width: 16),
                Expanded(
                    child: _statCard('Fulfilled Needs', '$fulfilledNeeds',
                        Icons.check_circle_outline, AppTheme.successGreen)),
                const SizedBox(width: 16),
                Expanded(
                    child: _statCard('Active Volunteers', '$activeVolunteers',
                        Icons.people_outline, AppTheme.warningOrange)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGrey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 16),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textGrey,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark)),
        ],
      ),
    );
  }

  Widget _buildRecentNeedsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGrey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Needs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            // No orderBy — sort client-side to avoid composite index requirement.
            stream: FirebaseFirestore.instance
                .collection('needs')
                .where('ngoId', isEqualTo: ngoId)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = List.of(snap.data!.docs)
                ..sort((a, b) {
                  final aT = (a.data() as Map)['createdAt'];
                  final bT = (b.data() as Map)['createdAt'];
                  if (aT == null && bT == null) return 0;
                  if (aT == null) return 1;
                  if (bT == null) return -1;
                  return (bT as Timestamp).compareTo(aT as Timestamp);
                });
              final recent = docs.take(5).toList();
              if (recent.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No needs posted yet.',
                      style: TextStyle(color: AppTheme.textGrey)),
                );
              }
              return Column(
                children: recent.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return _needRow(
                    d['title'] as String? ?? '(untitled)',
                    d['status'] as String? ?? 'open',
                    d['urgency']?.toString() ?? '—',
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _needRow(String title, String status, String urgency) {
    final statusColor = status == 'open'
        ? AppTheme.infoBlue
        : status == 'closed'
            ? AppTheme.successGreen
            : AppTheme.warningOrange;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Text(status,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Text('Urgency: $urgency',
              style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
        ],
      ),
    );
  }

  Widget _buildRecentAssignmentsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGrey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Assignments',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            // No orderBy — sort client-side to avoid composite index requirement.
            stream: FirebaseFirestore.instance
                .collection('task_assignments')
                .where('ngoId', isEqualTo: ngoId)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = List.of(snap.data!.docs)
                ..sort((a, b) {
                  final aT = (a.data() as Map)['invitedAt'];
                  final bT = (b.data() as Map)['invitedAt'];
                  if (aT == null && bT == null) return 0;
                  if (aT == null) return 1;
                  if (bT == null) return -1;
                  return (bT as Timestamp).compareTo(aT as Timestamp);
                });
              final recent = docs.take(5).toList();
              if (recent.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No assignments yet.',
                      style: TextStyle(color: AppTheme.textGrey)),
                );
              }
              return Column(
                children: recent.map((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final volunteerId = d['volunteerId'] as String? ?? '';
                  final needId = d['needId'] as String? ?? '';
                  final status = d['status'] as String? ?? 'invited';
                  return _AssignmentRowResolved(
                    volunteerId: volunteerId,
                    needId: needId,
                    status: status,
                    statusColor: _statusColor(status),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _assignmentRow(String volunteerId, String needId, String status) {
    final statusColor = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primaryPurple.withOpacity(0.1),
            child:
                const Icon(Icons.person, size: 16, color: AppTheme.primaryPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    volunteerId.length > 12
                        ? '${volunteerId.substring(0, 12)}…'
                        : volunteerId,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13)),
                Text('Need: $needId',
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Text(status,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'invited':
        return AppTheme.textGrey;
      case 'accepted':
        return AppTheme.infoBlue;
      case 'in-progress':
        return AppTheme.warningOrange;
      case 'reported':
        return AppTheme.primaryPurple;
      case 'verified':
        return AppTheme.successGreen;
      case 'closed':
        return AppTheme.textDark;
      default:
        return AppTheme.textGrey;
    }
  }
}

/// Resolves volunteer name and need title from Firestore for the overview row.
class _AssignmentRowResolved extends StatefulWidget {
  final String volunteerId;
  final String needId;
  final String status;
  final Color statusColor;

  const _AssignmentRowResolved({
    required this.volunteerId,
    required this.needId,
    required this.status,
    required this.statusColor,
  });

  @override
  State<_AssignmentRowResolved> createState() => _AssignmentRowResolvedState();
}

class _AssignmentRowResolvedState extends State<_AssignmentRowResolved> {
  String _name = '';
  String _needTitle = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(widget.volunteerId).get(),
      FirebaseFirestore.instance.collection('needs').doc(widget.needId).get(),
    ]);
    if (mounted) {
      setState(() {
        _name = (results[0].data() as Map<String, dynamic>?)?['name'] as String? ?? widget.volunteerId;
        _needTitle = (results[1].data() as Map<String, dynamic>?)?['title'] as String? ?? widget.needId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _name.isEmpty ? widget.volunteerId : _name;
    final displayTitle = _needTitle.isEmpty ? widget.needId : _needTitle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primaryPurple.withOpacity(0.1),
            child: const Icon(Icons.person, size: 16, color: AppTheme.primaryPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                Text(displayTitle,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textGrey),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: widget.statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Text(widget.status,
                style: TextStyle(
                    color: widget.statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
