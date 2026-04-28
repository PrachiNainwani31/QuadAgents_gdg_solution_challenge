import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../theme.dart';
import '../../models/need_card.dart';
import '../../services/firebase_service.dart';
import '../../utils/validators.dart';
import 'task_detail_view.dart';

/// ExploreNeedsView — list + map toggle for volunteers.
/// Requirements 10.1, 10.2, 12.5
class ExploreNeedsView extends StatefulWidget {
  const ExploreNeedsView({super.key});

  @override
  State<ExploreNeedsView> createState() => _ExploreNeedsViewState();
}

class _ExploreNeedsViewState extends State<ExploreNeedsView> {
  bool _mapMode = false;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final _searchController = TextEditingController();

  static const _categories = [
    'All', 'Technology', 'Education', 'Environment', 'Medical', 'Logistics', 'Other'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  List<NeedCard> _filterNeeds(List<NeedCard> needs) {
    var filtered = needs;
    if (_selectedCategory != 'All') {
      filtered = filtered
          .where((n) => n.category.toLowerCase() == _selectedCategory.toLowerCase())
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.description.toLowerCase().contains(q) ||
              n.skills.any((s) => s.toLowerCase().contains(q)))
          .toList();
    }
    return sortNeeds(filtered);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.getNeedsStream(status: 'open'),
      builder: (context, snap) {
        final allNeeds = <NeedCard>[];
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            allNeeds.add(NeedCard.fromMap(doc.id, doc.data() as Map<String, dynamic>));
          }
        }
        final filtered = _filterNeeds(allNeeds);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, allNeeds.length),
            const SizedBox(height: 24),
            _buildFilterBar(),
            const SizedBox(height: 24),
            if (snap.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (_mapMode)
              _buildMapView(filtered)
            else
              _buildListView(context, filtered),
            const SizedBox(height: 48),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int totalCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Explore Needs', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 4),
            Text('Discover opportunities that match your skills.',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Row(
          children: [
            // Live count badge — Requirement 12.5
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language, size: 16, color: AppTheme.primaryPurple),
                  const SizedBox(width: 8),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(color: AppTheme.textDark, fontSize: 13),
                      children: [
                        const TextSpan(text: 'Showing '),
                        TextSpan(
                          text: '$totalCount',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' open needs'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Map / List toggle
            Container(
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderGrey),
              ),
              child: Row(
                children: [
                  _toggleButton(Icons.list, 'List', !_mapMode, () => setState(() => _mapMode = false)),
                  _toggleButton(Icons.map_outlined, 'Map', _mapMode, () => setState(() => _mapMode = true)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _toggleButton(IconData icon, String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : AppTheme.textGrey),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppTheme.textGrey)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search by title, skill, or keyword...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.borderGrey)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppTheme.borderGrey)),
              fillColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final selected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _selectedCategory = cat),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.primaryPurple : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: selected ? AppTheme.primaryPurple : AppTheme.borderGrey),
                      ),
                      child: Text(cat,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: selected ? Colors.white : AppTheme.textDark)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ── List View ──────────────────────────────────────────────────────────────

  Widget _buildListView(BuildContext context, List<NeedCard> needs) {
    if (needs.isEmpty) {
      return _buildEmptyState();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            childAspectRatio: 0.72,
          ),
          itemCount: needs.length,
          itemBuilder: (context, i) => _needCard(context, needs[i]),
        );
      },
    );
  }

  Widget _needCard(BuildContext context, NeedCard need) {
    final urgencyColor = _urgencyColor(need.urgency);
    final deadlineStr =
        '${need.deadline.day}/${need.deadline.month}/${need.deadline.year}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGrey),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: NGO + urgency badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primaryPurple.withOpacity(0.1),
                radius: 18,
                child: const Icon(Icons.business, color: AppTheme.primaryPurple, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(need.category,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: AppTheme.textDark, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 11, color: AppTheme.textGrey),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(need.location,
                              style: const TextStyle(color: AppTheme.textGrey, fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: urgencyColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: urgencyColor.withOpacity(0.3))),
                child: Text(_urgencyLabel(need.urgency),
                    style: TextStyle(
                        color: urgencyColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title
          Text(need.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          // Description
          Text(need.description,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 12, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          // Skills
          if (need.skills.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: need.skills
                  .take(3)
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: AppTheme.backgroundLight,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(s,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 10),
          // Deadline
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 12, color: AppTheme.textGrey),
              const SizedBox(width: 4),
              Text('Deadline: $deadlineStr',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            ],
          ),
          const SizedBox(height: 12),
          // Apply button — always visible
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _openTaskDetail(context, need),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.volunteer_activism, size: 14),
                  SizedBox(width: 6),
                  Text('View & Apply', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Map View ───────────────────────────────────────────────────────────────
  // Requirement 10.1: real OSM map via flutter_map + urgency-colored markers.

  Widget _buildMapView(List<NeedCard> needs) {
    // Filter needs that have valid coordinates
    final mapped = needs.where((n) => n.lat != 0.0 || n.lng != 0.0).toList();

    // Compute center: average of all pins, or world center fallback
    final center = mapped.isEmpty
        ? LatLng(20.0, 0.0)
        : LatLng(
            mapped.map((n) => n.lat).reduce((a, b) => a + b) / mapped.length,
            mapped.map((n) => n.lng).reduce((a, b) => a + b) / mapped.length,
          );

    return Container(
      height: 520,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: mapped.isEmpty ? 2.0 : 5.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.ngoconnect.app',
                ),
                MarkerLayer(
                  markers: mapped.map((need) {
                    final color = _urgencyColor(need.urgency);
                    return Marker(
                      point: LatLng(need.lat, need.lng),
                      width: 36,
                      height: 36,
                      child: GestureDetector(
                        onTap: () => _showNeedPopup(need),
                        child: Tooltip(
                          message: need.title,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6)],
                            ),
                            child: Center(
                              child: Text('${need.urgency}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            // Legend
            Positioned(
              bottom: 16,
              left: 16,
              child: _buildMapLegend(),
            ),
            // Count badge
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderGrey)),
                child: Text('${mapped.length} needs on map',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderGrey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Urgency', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _legendItem(AppTheme.successGreen, 'Low (1–2)'),
          _legendItem(AppTheme.warningOrange, 'Medium (3)'),
          _legendItem(AppTheme.errorRed, 'High (4–5)'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  void _showNeedPopup(NeedCard need) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: _urgencyColor(need.urgency).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_urgencyLabel(need.urgency),
                        style: TextStyle(
                            color: _urgencyColor(need.urgency),
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 8),
              Text(need.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(need.location,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
              const SizedBox(height: 12),
              Text(need.description,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textDark),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: need.skills
                    .take(3)
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppTheme.backgroundLight,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(s, style: const TextStyle(fontSize: 11)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openTaskDetail(context, need);
                  },
                  child: const Text('View Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGrey)),
      child: const Column(
        children: [
          Icon(Icons.search_off, size: 48, color: AppTheme.textGrey),
          SizedBox(height: 16),
          Text('No needs found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textDark)),
          SizedBox(height: 8),
          Text('Try adjusting your filters or search query.',
              style: TextStyle(color: AppTheme.textGrey)),
        ],
      ),
    );
  }

  void _openTaskDetail(BuildContext context, NeedCard need) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TaskDetailView(need: need)),
    );
  }
}
