import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../theme.dart';
import '../../../services/firebase_service.dart';
import '../../../utils/validators.dart';

/// KanbanBoardView — real-time assignment status board for NGO.
/// Requirements 7.1, 7.2, 7.4, 7.5: stream task_assignments filtered by ngoId;
/// group by status column; enforce transition order.
class KanbanBoardView extends StatelessWidget {
  final String ngoId;
  const KanbanBoardView({super.key, required this.ngoId});

  static const _columns = [
    'invited',
    'accepted',
    'in-progress',
    'reported',
    'verified',
    'closed',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 24),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.getAssignmentsStream(ngoId: ngoId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Text('Error: ${snap.error}',
                  style: const TextStyle(color: AppTheme.errorRed));
            }

            final docs = snap.data?.docs ?? [];

            // Group assignments by status
            final grouped = <String, List<QueryDocumentSnapshot>>{};
            for (final col in _columns) {
              grouped[col] = [];
            }
            for (final doc in docs) {
              final status =
                  (doc.data() as Map<String, dynamic>)['status']
                          as String? ??
                      'invited';
              grouped[status]?.add(doc);
            }

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _columns.map((col) {
                  return _buildColumn(
                      context, col, grouped[col] ?? []);
                }).toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Task Board',
                style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 4),
            const Text(
                'Real-time view of all volunteer assignments.',
                style: TextStyle(color: AppTheme.textGrey)),
          ],
        ),
      ],
    );
  }

  Widget _buildColumn(BuildContext context, String status,
      List<QueryDocumentSnapshot> docs) {
    final color = _columnColor(status);
    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Column header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(_columnLabel(status),
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${docs.length}',
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Cards
          if (docs.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGrey)),
              child: const Text('No tasks',
                  style: TextStyle(
                      color: AppTheme.textGrey, fontSize: 13)),
            )
          else
            ...docs.map((doc) =>
                _assignmentCard(context, doc, status)),
        ],
      ),
    );
  }

  Widget _assignmentCard(BuildContext context,
      QueryDocumentSnapshot doc, String currentStatus) {
    final d = doc.data() as Map<String, dynamic>;
    final volunteerId = d['volunteerId'] as String? ?? '';
    final needId = d['needId'] as String? ?? '';
    final invitedAt = d['invitedAt'];
    String dateStr = '—';
    if (invitedAt is Timestamp) {
      final dt = invitedAt.toDate();
      dateStr = '${dt.day}/${dt.month}/${dt.year}';
    }

    final nextStatus = _nextStatus(currentStatus);

    return _AssignmentCard(
      assignmentId: doc.id,
      volunteerId: volunteerId,
      needId: needId,
      dateStr: dateStr,
      currentStatus: currentStatus,
      nextStatus: nextStatus,
      onAdvance: () => _advanceStatus(context, doc.id, currentStatus),
      columnLabel: _columnLabel,
    );
  }

  Future<void> _advanceStatus(
      BuildContext context, String assignmentId, String currentStatus) async {
    final next = _nextStatus(currentStatus);
    if (next == null) return;
    try {
      await FirebaseService.updateAssignmentStatus(assignmentId, next);

      // Requirement 11.3: notify all parties on status change.
      final doc = await FirebaseFirestore.instance
          .collection('task_assignments')
          .doc(assignmentId)
          .get();
      final data = doc.data() ?? {};
      final volunteerId = data['volunteerId'] as String?;
      final needId = data['needId'] as String?;

      // Notify volunteer of the status change.
      if (volunteerId != null) {
        await FirebaseService.createNotification(volunteerId, {
          'type': 'status_change',
          'title': 'Task status updated to ${_columnLabel(next)}',
          'body': 'Your task assignment has been moved to ${_columnLabel(next)} by the NGO.',
          'relatedId': assignmentId,
        });
      }

      // Requirement 7.5 / 11.3: when verified, send rating prompt to NGO.
      if (next == 'verified') {
        await FirebaseService.createNotification(ngoId, {
          'type': 'rating_prompt',
          'title': 'Rate your volunteer',
          'body': 'Task verified! Please submit a rating for the volunteer.',
          'relatedId': assignmentId,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Task verified! Please submit a rating for the volunteer.'),
                backgroundColor: AppTheme.successGreen),
          );
        }
      }

      // Requirement 11.3: notify volunteer when task is closed.
      if (next == 'closed' && volunteerId != null) {
        await FirebaseService.createNotification(volunteerId, {
          'type': 'status_change',
          'title': 'Task completed',
          'body': 'Your task has been closed. Thank you for your contribution!',
          'relatedId': needId ?? assignmentId,
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Transition error: $e'),
              backgroundColor: AppTheme.errorRed),
        );
      }
    }
  }

  String? _nextStatus(String current) {
    final idx = kKanbanOrder.indexOf(current);
    if (idx == -1 || idx >= kKanbanOrder.length - 1) return null;
    return kKanbanOrder[idx + 1];
  }

  Color _columnColor(String status) {
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

  String _columnLabel(String status) {
    switch (status) {
      case 'in-progress':
        return 'In Progress';
      default:
        return status[0].toUpperCase() + status.substring(1);
    }
  }
}

/// A card that resolves volunteer name and need title from Firestore.
class _AssignmentCard extends StatefulWidget {
  final String assignmentId;
  final String volunteerId;
  final String needId;
  final String dateStr;
  final String currentStatus;
  final String? nextStatus;
  final VoidCallback onAdvance;
  final String Function(String) columnLabel;

  const _AssignmentCard({
    required this.assignmentId,
    required this.volunteerId,
    required this.needId,
    required this.dateStr,
    required this.currentStatus,
    required this.nextStatus,
    required this.onAdvance,
    required this.columnLabel,
  });

  @override
  State<_AssignmentCard> createState() => _AssignmentCardState();
}

class _AssignmentCardState extends State<_AssignmentCard> {
  String _volunteerName = '';
  String _needTitle = '';

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    final results = await Future.wait([
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.volunteerId)
          .get(),
      FirebaseFirestore.instance
          .collection('needs')
          .doc(widget.needId)
          .get(),
    ]);
    if (mounted) {
      setState(() {
        _volunteerName =
            (results[0].data() as Map<String, dynamic>?)?['name']
                    as String? ??
                widget.volunteerId;
        _needTitle =
            (results[1].data() as Map<String, dynamic>?)?['title']
                    as String? ??
                widget.needId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        _volunteerName.isEmpty ? widget.volunteerId : _volunteerName;
    final displayTitle =
        _needTitle.isEmpty ? widget.needId : _needTitle;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGrey),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03), blurRadius: 4)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor:
                    AppTheme.primaryPurple.withOpacity(0.1),
                child: const Icon(Icons.person,
                    size: 14, color: AppTheme.primaryPurple),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayTitle,
            style: const TextStyle(fontSize: 12, color: AppTheme.textDark),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 4),
          Text('Invited: ${widget.dateStr}',
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textGrey)),
          if (widget.currentStatus == 'reported') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onAdvance,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12)),
                child: const Text('Mark Verified'),
              ),
            ),
          ] else if (widget.nextStatus != null &&
              widget.currentStatus != 'closed') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onAdvance,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12)),
                child: Text('→ ${widget.columnLabel(widget.nextStatus!)}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
