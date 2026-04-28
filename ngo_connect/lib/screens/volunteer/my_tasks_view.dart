import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../utils/validators.dart';
import '../ngo/views/chat_view.dart';

/// MyTasksView — volunteer Kanban board with status update controls.
/// Requirements 7.1, 7.2, 7.3
class MyTasksView extends StatelessWidget {
  const MyTasksView({super.key});

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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Not logged in'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 24),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.getAssignmentsStream(volunteerId: uid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Text('Error: ${snap.error}',
                  style: const TextStyle(color: AppTheme.errorRed));
            }

            final docs = snap.data?.docs ?? [];
            final activeDocs = docs.where((doc) {
              final status =
                  (doc.data() as Map<String, dynamic>)['status'] as String? ?? '';
              return status != 'declined';
            }).toList();

            final grouped = <String, List<QueryDocumentSnapshot>>{};
            for (final col in _columns) {
              grouped[col] = [];
            }
            for (final doc in activeDocs) {
              final status =
                  (doc.data() as Map<String, dynamic>)['status'] as String? ??
                      'invited';
              grouped[status]?.add(doc);
            }

            if (activeDocs.isEmpty) return _buildEmptyState(context);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _columns
                    .map((col) => _buildColumn(context, col, grouped[col] ?? []))
                    .toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Tasks', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 4),
        const Text('Track your volunteer task progress.',
            style: TextStyle(color: AppTheme.textGrey)),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(_columnLabel(status),
                    style:
                        TextStyle(fontWeight: FontWeight.bold, color: color)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          if (docs.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGrey)),
              child: const Text('No tasks',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
            )
          else
            ...docs.map((doc) => _taskCard(context, doc, status)),
        ],
      ),
    );
  }

  Widget _taskCard(BuildContext context, QueryDocumentSnapshot doc,
      String currentStatus) {
    final d = doc.data() as Map<String, dynamic>;
    final needId = d['needId'] as String? ?? '';
    final invitedAt = d['invitedAt'];
    String dateStr = '—';
    if (invitedAt is Timestamp) {
      final dt = invitedAt.toDate();
      dateStr = '${dt.day}/${dt.month}/${dt.year}';
    }

    final nextStatus = _nextStatus(currentStatus);
    final canAdvance = nextStatus != null && currentStatus != 'closed';
    final showChat = ['accepted', 'in-progress', 'reported', 'verified']
        .contains(currentStatus);

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('needs').doc(needId).get(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final title = data?['title'] as String? ?? '';
        final category = data?['category'] as String? ?? '';
        final location = data?['location'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderGrey),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.assignment_outlined,
                        size: 14, color: AppTheme.primaryPurple),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: snap.connectionState == ConnectionState.waiting
                        ? Container(
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppTheme.borderGrey,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          )
                        : Text(
                            title.isNotEmpty ? title : 'Unnamed Need',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
              if (category.isNotEmpty || location.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (category.isNotEmpty) ...[
                      const Icon(Icons.category_outlined, size: 11, color: AppTheme.textGrey),
                      const SizedBox(width: 3),
                      Text(category,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                      const SizedBox(width: 10),
                    ],
                    if (location.isNotEmpty) ...[
                      const Icon(Icons.location_on_outlined, size: 11, color: AppTheme.textGrey),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(location,
                            style: const TextStyle(fontSize: 11, color: AppTheme.textGrey),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Text('Invited: $dateStr',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),

              // Volunteer view is read-only — no status advance buttons
              // Only show current status badge
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: AppTheme.primaryPurple.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.assignment_outlined,
                    size: 14, color: AppTheme.primaryPurple),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildNeedTitle(needId),
              ),

              if (currentStatus == 'closed') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.successGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('✓ Completed',
                      style: TextStyle(
                          color: AppTheme.successGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text('Invited: $dateStr',
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
          if (canAdvance) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    _advanceStatus(context, doc.id, currentStatus),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(fontSize: 12)),
                child: Text('→ ${_columnLabel(nextStatus!)}'),
              ),
            ),
          ],
          if (showChat) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openChat(context, needId),
                icon: const Icon(Icons.chat_bubble_outline, size: 14),
                label: const Text('Group Chat',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8)),
              ),
            ),
          ],
          if (currentStatus == 'closed') ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.successGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('Completed',
                  style: TextStyle(
                      color: AppTheme.successGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNeedTitle(String needId) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('needs').doc(needId).get(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final title = data?['title'] as String? ?? needId;
        return Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis);
      },
    );
  }

  void _openChat(BuildContext context, String needId) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 600,
          height: 500,
          child: ChatView(taskId: needId, taskTitle: 'Group Chat'),
        ),
      ),
    );
  }

  Future<void> _advanceStatus(
      BuildContext context, String assignmentId, String currentStatus) async {
    final next = _nextStatus(currentStatus);
    if (next == null) return;

    final error = isValidTransition(currentStatus, next);
    if (error != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: AppTheme.errorRed));
      }
      return;
    }

    try {
      await FirebaseService.updateAssignmentStatus(assignmentId, next);

      final doc = await FirebaseFirestore.instance
          .collection('task_assignments')
          .doc(assignmentId)
          .get();
      final data = doc.data() ?? {};
      final ngoId = data['ngoId'] as String?;

      if (ngoId != null) {
        await FirebaseService.createNotification(ngoId, {
          'type': 'status_change',
          'title': next == 'reported'
              ? 'Task reported for verification'
              : 'Task status updated to ${_columnLabel(next)}',
          'body': next == 'reported'
              ? 'A volunteer has marked a task as reported. Please verify.'
              : 'A volunteer updated their task to ${_columnLabel(next)}.',
          'relatedId': assignmentId,
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Status updated to ${_columnLabel(next)}'),
            backgroundColor: AppTheme.successGreen));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorRed));
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

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGrey)),
      child: Column(
        children: [
          const Icon(Icons.assignment_outlined,
              size: 48, color: AppTheme.textGrey),
          const SizedBox(height: 16),
          Text('No tasks yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.textDark)),
          const SizedBox(height: 8),
          const Text('Accept needs from Explore to see them here.',
              style: TextStyle(color: AppTheme.textGrey)),
        ],
      ),
    );
  }
}
