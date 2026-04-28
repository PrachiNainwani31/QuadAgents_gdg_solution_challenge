import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../screens/landing_page.dart';
import 'views/ngo_overview_view.dart';
import 'create_need_view.dart';
import 'views/needs_management_view.dart';
import 'views/kanban_board_view.dart';
import 'views/analytics_view.dart';
import 'views/notifications_view.dart';
import 'views/chat_view.dart';

class NgoDashboard extends StatefulWidget {
  const NgoDashboard({super.key});

  @override
  State<NgoDashboard> createState() => _NgoDashboardState();
}

class _NgoDashboardState extends State<NgoDashboard> {
  int _selectedIndex = 0;
  String _ngoName = '';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ngo = await FirebaseService.getNgoProfile(uid);
    if (mounted) {
      setState(() => _ngoName = ngo?['name'] as String? ?? '');
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingPage()),
        (route) => false,
      );
    }
  }

  final _navItems = const [
    _NavItem(Icons.dashboard_outlined, 'Overview', 0),
    _NavItem(Icons.upload_file_outlined, 'Documents', 1),
    _NavItem(Icons.add_circle_outline, 'Create Need', 2),
    _NavItem(Icons.list_alt_outlined, 'Manage Needs', 3),
    _NavItem(Icons.view_kanban_outlined, 'Task Board', 4),
    _NavItem(Icons.chat_bubble_outline, 'Chat', 5),
    _NavItem(Icons.bar_chart_outlined, 'Analytics', 6),
    _NavItem(Icons.notifications_outlined, 'Notifications', 7),
  ];

  Widget _buildCurrentView() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    switch (_selectedIndex) {
      case 0:
        return NgoOverviewView(ngoId: uid);
      case 1:
        return CreateNeedView(ngoId: uid);
      case 2:
        return NeedsManagementView(ngoId: uid);
      case 3:
        return KanbanBoardView(ngoId: uid);
      case 5:
        return _NgoChatRoomsView(ngoId: uid);
      case 6:
        return AnalyticsView(ngoId: uid);
      case 7:
        return NotificationsView(uid: uid);
      default:
        return NgoOverviewView(ngoId: uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Container(
                    color: AppTheme.backgroundLight,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: _buildCurrentView(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppTheme.backgroundLight,
        border: Border(right: BorderSide(color: AppTheme.borderGrey)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: AppTheme.primaryPurple, shape: BoxShape.circle),
                  child: const Icon(Icons.show_chart, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Text('NGO Connect',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.primaryPurple, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ..._navItems.map((item) => _sidebarItem(item)),
          const Spacer(),
          InkWell(
            onTap: _logout,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  Icon(Icons.logout, color: AppTheme.errorRed, size: 20),
                  SizedBox(width: 12),
                  Text('Logout',
                      style: TextStyle(
                          fontWeight: FontWeight.w500, color: AppTheme.errorRed)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sidebarItem(_NavItem item) {
    final selected = _selectedIndex == item.index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = item.index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected ? Border.all(color: AppTheme.borderGrey) : null,
          boxShadow: selected
              ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
              : [],
        ),
        child: Row(
          children: [
            Icon(item.icon,
                color: selected ? AppTheme.primaryPurple : AppTheme.textDark,
                size: 20),
            const SizedBox(width: 12),
            Text(item.label,
                style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: AppTheme.textDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final displayName = _ngoName.isNotEmpty ? _ngoName : 'NGO';
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.borderGrey)),
      ),
      child: Row(
        children: [
          Text(
            _navItems
                .firstWhere((n) => n.index == _selectedIndex,
                    orElse: () => _navItems.first)
                .label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(displayName,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppTheme.textDark)),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundColor: AppTheme.primaryPurple,
            radius: 18,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'N',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int index;
  const _NavItem(this.icon, this.label, this.index);
}

/// NGO chat rooms view — shows all needs with active assignments as chat rooms.
class _NgoChatRoomsView extends StatefulWidget {
  final String ngoId;
  const _NgoChatRoomsView({required this.ngoId});

  @override
  State<_NgoChatRoomsView> createState() => _NgoChatRoomsViewState();
}

class _NgoChatRoomsViewState extends State<_NgoChatRoomsView> {
  String? _selectedRoomId;
  String? _selectedRoomTitle;

  @override
  Widget build(BuildContext context) {
    if (_selectedRoomId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _selectedRoomId = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to rooms'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: ChatView(
              taskId: _selectedRoomId!,
              taskTitle: _selectedRoomTitle ?? _selectedRoomId!,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Group Chats', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 4),
        const Text('Chat with volunteers on your tasks.',
            style: TextStyle(color: AppTheme.textGrey)),
        const SizedBox(height: 24),
        // Show all needs that have at least one accepted assignment
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('task_assignments')
              .where('ngoId', isEqualTo: widget.ngoId)
              .snapshots(),
          builder: (context, assignSnap) {
            if (!assignSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            // Get unique needIds that have accepted/in-progress assignments
            final activeStatuses = {'accepted', 'in-progress', 'reported', 'verified'};
            final needIds = assignSnap.data!.docs
                .where((d) {
                  final status = (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
                  return activeStatuses.contains(status);
                })
                .map((d) => (d.data() as Map<String, dynamic>)['needId'] as String? ?? '')
                .where((id) => id.isNotEmpty)
                .toSet()
                .toList();

            if (needIds.isEmpty) {
              return _buildEmpty();
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: needIds.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final needId = needIds[i];
                return _RoomCard(
                  roomId: needId,
                  needId: needId,
                  onTap: (title) async {
                    // Ensure chat room exists with NGO as participant
                    await FirebaseService.ensureChatRoom(needId, [widget.ngoId]);
                    setState(() {
                      _selectedRoomId = needId;
                      _selectedRoomTitle = title;
                    });
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGrey)),
      child: const Column(
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.textGrey),
          SizedBox(height: 16),
          Text('No active task chats',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          SizedBox(height: 8),
          Text('Chats appear when volunteers accept your tasks.',
              style: TextStyle(color: AppTheme.textGrey),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final String roomId;
  final String needId;
  final void Function(String title) onTap;

  const _RoomCard({required this.roomId, required this.needId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('needs').doc(needId).get(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final title = data?['title'] as String? ?? 'Task $needId';
        return InkWell(
          onTap: () => onTap(title),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
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
                    color: AppTheme.primaryPurple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.group,
                      color: AppTheme.primaryPurple, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      const Text('Tap to open chat',
                          style: TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textGrey),
              ],
            ),
          ),
        );
      },
    );
  }
}
