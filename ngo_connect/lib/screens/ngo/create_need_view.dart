import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../services/firebase_service.dart';
import '../../services/matching_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/storage_service.dart';

/// CreateNeedView — merged with Document Hub.
/// Supports AI extraction from pasted text OR uploaded PDF/CSV.
/// Requirements: 2.1, 2.2, 2.5, 3.1, 3.2, 3.4, 3.6, 10.4
class CreateNeedView extends StatefulWidget {
  final String ngoId;
  const CreateNeedView({super.key, required this.ngoId});

  @override
  State<CreateNeedView> createState() => _CreateNeedViewState();
}

class _CreateNeedViewState extends State<CreateNeedView> {
  // ── Form controllers ───────────────────────────────────────────────────────
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _deadlineController = TextEditingController();
  final _aiTextController = TextEditingController();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isSaving = false;
  bool _isExtracting = false;
  bool _isUploading = false;
  String _urgency = 'Medium';
  String _category = 'Technology';
  List<String> _selectedSkills = [];
  double _lat = 0.0;
  double _lng = 0.0;
  bool _coordsResolved = false;
  String? _uploadError;
  List<Map<String, dynamic>> _extractedNeeds = [];

  final Map<String, List<String>> _skillsByCategory = {
    'Technology': ['Flutter', 'Firebase', 'UI/UX', 'Python', 'JavaScript'],
    'Education': ['Teaching', 'Special Needs', 'Adult Literacy', 'STEM'],
    'Environment': ['Conservation', 'Solar Energy', 'Environmental Science', 'Gardening'],
    'Medical': ['First Aid', 'Nursing', 'Mental Health', 'Counseling'],
    'Legal': ['Legal Aid', 'Advocacy', 'Paralegal', 'Human Rights'],
    'Community': ['Food Distribution', 'Fundraising', 'Event Organization'],
  };

  List<String> get _currentSkills => _skillsByCategory[_category] ?? [];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _deadlineController.dispose();
    _aiTextController.dispose();
    super.dispose();
  }

  // ── PDF/CSV upload & extract ───────────────────────────────────────────────

  Future<void> _pickAndExtract() async {
    setState(() { _uploadError = null; });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      setState(() => _uploadError = 'Could not read file bytes.');
      return;
    }

    final typeResult = validateFileType(file.name);
    if (!typeResult.isValid) { setState(() => _uploadError = typeResult.error); return; }
    final sizeResult = validateFileSize(file.bytes!.length);
    if (!sizeResult.isValid) { setState(() => _uploadError = sizeResult.error); return; }

    setState(() => _isUploading = true);

    try {
      // Save document metadata to Firestore
      final lower = file.name.toLowerCase();
      final contentType = lower.endsWith('.pdf') ? 'application/pdf' : 'text/csv';
      await FirebaseService.saveDocumentMetadata({
        'ngoId': widget.ngoId,
        'filename': file.name,
        'contentType': contentType,
        'storagePath': 'documents/${widget.ngoId}/${file.name}',
        'downloadUrl': '',
        'sizeBytes': file.bytes!.length,
      });

      // Extract text from file bytes and send to AI
      String rawText = '';
      if (lower.endsWith('.csv')) {
        rawText = String.fromCharCodes(file.bytes!);
      } else {
        // For PDF: send raw bytes as latin1 string — backend handles extraction
        rawText = String.fromCharCodes(file.bytes!.take(8000));
      }

      if (rawText.isNotEmpty) {
        setState(() { _isUploading = false; _isExtracting = true; });
        final needs = await MatchingService.extractNeedsFromText(
            'File: ${file.name}\n\n$rawText');
        if (mounted) {
          setState(() {
            _extractedNeeds = needs;
            _isExtracting = false;
          });
          if (needs.isNotEmpty) {
            _prefillFromExtracted(needs.first);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${needs.length} need(s) extracted from ${file.name}'),
              backgroundColor: AppTheme.successGreen,
            ));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No needs found in the file. Fill the form manually.'),
              backgroundColor: AppTheme.warningOrange,
            ));
          }
        }
      }
    } catch (e) {
      setState(() { _uploadError = 'Failed: $e'; _isUploading = false; _isExtracting = false; });
    } finally {
      if (mounted) setState(() { _isUploading = false; _isExtracting = false; });
    }
  }

  // ── Text-based AI extraction ───────────────────────────────────────────────

  Future<void> _extractFromText() async {
    final text = _aiTextController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste some survey or report text first.')),
      );
      return;
    }
    setState(() => _isExtracting = true);
    try {
      final results = await MatchingService.extractNeedsFromText(text);
      if (results.isNotEmpty && mounted) {
        setState(() => _extractedNeeds = results);
        _prefillFromExtracted(results.first);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${results.length} need(s) extracted — form pre-filled.'),
          backgroundColor: AppTheme.successGreen,
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No needs found in the provided text.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI extraction failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  void _prefillFromExtracted(Map<String, dynamic> need) {
    setState(() {
      _titleController.text = need['title'] as String? ?? '';
      _descController.text = need['description'] as String? ?? '';
      _locationController.text = need['location'] as String? ?? '';
      _coordsResolved = false;
      final rawSkills = need['skills'];
      if (rawSkills is List) _selectedSkills = rawSkills.map((s) => s.toString()).toList();
      final rawUrgency = need['urgency'];
      if (rawUrgency != null) _urgency = rawUrgency.toString();
    });
  }

  // ── Geocode ────────────────────────────────────────────────────────────────

  Future<void> _resolveLocation() async {
    final address = _locationController.text.trim();
    if (address.isEmpty) return;
    final geo = await GeocodingService.geocodeAddress(address);
    if (geo != null && mounted) {
      setState(() { _lat = geo.lat; _lng = geo.lng; _coordsResolved = true; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Location resolved: ${geo.lat.toStringAsFixed(4)}, ${geo.lng.toStringAsFixed(4)}'),
        backgroundColor: Colors.green,
      ));
    } else if (mounted) {
      setState(() => _coordsResolved = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Address not found — enter a more specific address.'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  // ── Submit need ────────────────────────────────────────────────────────────

  Future<void> _submitNeed() async {
    if (_titleController.text.trim().isEmpty || _descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in title and description.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    if (!_coordsResolved) await _resolveLocation();
    try {
      final needId = await FirebaseService.createNeed({
        'ngoId': widget.ngoId,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'location': _locationController.text.trim(),
        'lat': _lat,
        'lng': _lng,
        'deadline': _deadlineController.text.trim(),
        'urgency': _urgencyToInt(_urgency),
        'category': _category,
        'skills': _selectedSkills,
        'applicantCount': 0,
      });
      await MatchingService.matchNeedToVolunteers(needId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Need posted & AI matching started.'),
          backgroundColor: Colors.green,
        ));
        _clearForm();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post need: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _publishExtracted(Map<String, dynamic> need) async {
    await FirebaseService.createNeed({...need, 'ngoId': widget.ngoId});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Published: ${need['title']}'),
      backgroundColor: Colors.green,
    ));
  }

  void _clearForm() {
    _titleController.clear();
    _descController.clear();
    _locationController.clear();
    _deadlineController.clear();
    _aiTextController.clear();
    setState(() {
      _selectedSkills = [];
      _urgency = 'Medium';
      _lat = 0.0; _lng = 0.0;
      _coordsResolved = false;
      _extractedNeeds = [];
    });
  }

  int _urgencyToInt(String label) {
    switch (label.toLowerCase()) {
      case 'low': return 1;
      case 'medium': return 2;
      case 'high': return 3;
      case 'critical': return 4;
      case 'immediate': return 5;
      default: return 2;
    }
  }

  String _monthName(int month) {
    const names = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[month];
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
  );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create Need', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 4),
          const Text('Upload a document or paste text — AI extracts needs automatically.',
              style: TextStyle(color: AppTheme.textGrey)),
          const SizedBox(height: 24),

          // ── AI Input Section ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryPurple.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, color: AppTheme.primaryPurple, size: 18),
                  const SizedBox(width: 8),
                  Text('AI Need Extractor',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: AppTheme.primaryPurple)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Powered by Gemini',
                        style: TextStyle(color: AppTheme.primaryPurple,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 16),

                // Upload PDF/CSV
                Row(children: [
                  ElevatedButton.icon(
                    onPressed: (_isUploading || _isExtracting) ? null : _pickAndExtract,
                    icon: (_isUploading || _isExtracting)
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_file_outlined, size: 16),
                    label: Text(_isUploading ? 'Uploading…'
                        : _isExtracting ? 'Extracting…'
                        : 'Upload PDF / CSV'),
                  ),
                  const SizedBox(width: 12),
                  const Text('PDF, CSV · Max 10 MB',
                      style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
                ]),
                if (_uploadError != null) ...[
                  const SizedBox(height: 8),
                  Text(_uploadError!, style: const TextStyle(color: AppTheme.errorRed, fontSize: 12)),
                ],

                const SizedBox(height: 16),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or paste text', style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),

                // Paste text
                TextField(
                  controller: _aiTextController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: 'Paste survey or report text here…\n\nExample: "The riverside community needs medical volunteers urgently…"',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isExtracting ? null : _extractFromText,
                  icon: _isExtracting
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.psychology, size: 16),
                  label: Text(_isExtracting ? 'Extracting…' : 'Extract from Text'),
                ),
              ],
            ),
          ),

          // ── Extracted needs list ─────────────────────────────────────────
          if (_extractedNeeds.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('${_extractedNeeds.length} Need(s) Extracted',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ..._extractedNeeds.map((need) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryPurple.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(need['title'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(need['description'] ?? '',
                            style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(need['urgency'] ?? 'Medium',
                                style: const TextStyle(color: Colors.orange,
                                    fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          ...((need['skills'] ?? []) as List).take(3).map((s) =>
                            Chip(label: Text(s.toString(),
                                style: const TextStyle(fontSize: 10)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(children: [
                    ElevatedButton.icon(
                      onPressed: () => _prefillFromExtracted(need),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Edit', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () => _publishExtracted(need),
                      icon: const Icon(Icons.publish, size: 14),
                      label: const Text('Publish', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    ),
                  ]),
                ],
              ),
            )),
          ],

          // ── Uploaded Documents ───────────────────────────────────────────
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Uploaded Documents', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseService.getDocumentsStream(widget.ngoId),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Text('No documents uploaded yet.',
                          style: TextStyle(color: AppTheme.textGrey));
                    }
                    return Column(
                      children: docs.map((doc) => _docRow(doc.data() as Map<String, dynamic>)).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Need Form ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Need Details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Review and edit the extracted details or fill manually.',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                const SizedBox(height: 20),

                _label('Title'),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(hintText: 'e.g. Full Stack Developer for Crisis App'),
                ),
                const SizedBox(height: 16),

                _label('Description'),
                TextFormField(
                  controller: _descController,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: 'Describe the need in detail…'),
                ),
                const SizedBox(height: 16),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label('Category'),
                    DropdownButtonFormField<String>(
                      value: _category,
                      items: ['Technology', 'Education', 'Environment', 'Medical', 'Legal', 'Community']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) { if (v != null) setState(() { _category = v; _selectedSkills = []; }); },
                    ),
                  ])),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label('Urgency'),
                    DropdownButtonFormField<String>(
                      value: _urgency,
                      items: ['Low', 'Medium', 'High', 'Critical', 'Immediate']
                          .map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                      onChanged: (v) { if (v != null) setState(() => _urgency = v); },
                    ),
                  ])),
                ]),
                const SizedBox(height: 16),

                _label('Skills Required'),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _currentSkills.map((skill) {
                    final selected = _selectedSkills.contains(skill);
                    return GestureDetector(
                      onTap: () => setState(() =>
                          selected ? _selectedSkills.remove(skill) : _selectedSkills.add(skill)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primaryPurple : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: selected ? AppTheme.primaryPurple : AppTheme.borderGrey),
                        ),
                        child: Text(skill, style: TextStyle(
                            color: selected ? Colors.white : AppTheme.textDark, fontSize: 13)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                _label('Deadline'),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2027),
                    );
                    if (picked != null) {
                      _deadlineController.text = '${picked.day} ${_monthName(picked.month)} ${picked.year}';
                    }
                  },
                  child: AbsorbPointer(
                    child: TextFormField(
                      controller: _deadlineController,
                      decoration: const InputDecoration(
                        hintText: 'Select deadline',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _label('Location'),
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    hintText: 'City, address, or "Remote"',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _coordsResolved ? Icons.location_on : Icons.location_searching,
                        color: _coordsResolved ? AppTheme.successGreen : AppTheme.textGrey,
                      ),
                      onPressed: _resolveLocation,
                      tooltip: 'Resolve coordinates',
                    ),
                  ),
                  onChanged: (_) => setState(() => _coordsResolved = false),
                ),
                if (_coordsResolved)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('📍 ${_lat.toStringAsFixed(4)}, ${_lng.toStringAsFixed(4)}',
                        style: const TextStyle(color: AppTheme.successGreen, fontSize: 11)),
                  ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submitNeed,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Post Need & Find AI Matches'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryPurple, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _docRow(Map<String, dynamic> d) {
    final filename = d['filename'] as String? ?? 'Unknown';
    final sizeBytes = (d['sizeBytes'] as num?)?.toInt() ?? 0;
    final sizeKb = (sizeBytes / 1024).toStringAsFixed(1);
    final uploadedAt = d['uploadedAt'];
    String dateStr = '—';
    if (uploadedAt is Timestamp) {
      final dt = uploadedAt.toDate();
      dateStr = '${dt.day}/${dt.month}/${dt.year}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(
            filename.endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.table_chart_outlined,
            color: AppTheme.primaryPurple, size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(filename, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text('$sizeKb KB · $dateStr',
              style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
        ])),
      ]),
    );
  }
}
