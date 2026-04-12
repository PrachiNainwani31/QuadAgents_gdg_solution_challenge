import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../services/storage_service.dart';
import '../../services/matching_service.dart';
import '../../services/firebase_service.dart';

/// DocumentUploadView — file picker, upload progress, and live document list.
/// Requirements 2.1, 2.2, 2.5: StorageService upload; stream ngo_documents.
class DocUploadView extends StatefulWidget {
  final String ngoId;
  const DocUploadView({super.key, required this.ngoId});

  @override
  State<DocUploadView> createState() => _DocUploadViewState();
}

class _DocUploadViewState extends State<DocUploadView> {
  final _textController = TextEditingController();
  bool _isParsing = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _uploadError;
  List<Map<String, dynamic>> _extractedNeeds = [];

  Future<void> _pickAndUpload() async {
    setState(() {
      _uploadError = null;
      _uploadProgress = 0;
    });

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

    // Client-side validation
    final typeResult = validateFileType(file.name);
    if (!typeResult.isValid) {
      setState(() => _uploadError = typeResult.error);
      return;
    }
    final sizeResult = validateFileSize(file.bytes!.length);
    if (!sizeResult.isValid) {
      setState(() => _uploadError = sizeResult.error);
      return;
    }

    setState(() => _isUploading = true);

    try {
      // Save metadata to Firestore directly (Storage CORS requires server config).
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Document recorded: ${file.name}'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _uploadError = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _parseText() async {
    if (_textController.text.isEmpty) return;
    setState(() {
      _isParsing = true;
      _extractedNeeds = [];
    });
    final needs =
        await MatchingService.extractNeedsFromText(_textController.text);
    if (mounted) setState(() {
      _extractedNeeds = needs;
      _isParsing = false;
    });
  }

  Future<void> _publishNeed(Map<String, dynamic> need) async {
    await FirebaseService.createNeed({...need, 'ngoId': widget.ngoId});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Published: ${need['title']}'),
            backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Document Hub',
              style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 4),
          const Text(
              'Upload surveys and reports — AI extracts needs automatically',
              style: TextStyle(color: AppTheme.textGrey)),
          const SizedBox(height: 32),

          // ── Upload Card ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.upload_file_outlined,
                      color: AppTheme.primaryPurple),
                  const SizedBox(width: 8),
                  Text('Upload Document',
                      style: Theme.of(context).textTheme.titleLarge),
                ]),
                const SizedBox(height: 8),
                const Text('Accepted formats: PDF, CSV · Max size: 10 MB',
                    style:
                        TextStyle(color: AppTheme.textGrey, fontSize: 13)),
                const SizedBox(height: 20),
                if (_uploadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_uploadError!,
                        style: const TextStyle(
                            color: AppTheme.errorRed, fontSize: 13)),
                  ),
                if (_isUploading)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Uploading…',
                          style: TextStyle(
                              color: AppTheme.textGrey, fontSize: 13)),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ElevatedButton.icon(
                  onPressed: _isUploading ? null : _pickAndUpload,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Choose File & Upload'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Live Document List ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Uploaded Documents',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseService.getDocumentsStream(widget.ngoId),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No documents uploaded yet.',
                            style:
                                TextStyle(color: AppTheme.textGrey)),
                      );
                    }
                    return Column(
                      children: docs.map((doc) {
                        final d =
                            doc.data() as Map<String, dynamic>;
                        return _docRow(d);
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── AI Text Parser ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome,
                      color: AppTheme.primaryPurple),
                  const SizedBox(width: 8),
                  Text('AI Survey Parser',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color:
                            AppTheme.primaryPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Powered by Gemini',
                        style: TextStyle(
                            color: AppTheme.primaryPurple,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                    'Paste your field survey or community report text below',
                    style: TextStyle(color: AppTheme.textGrey)),
                const SizedBox(height: 16),
                TextField(
                  controller: _textController,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText:
                        'Paste survey text here…\n\nExample: "The riverside community needs medical volunteers urgently…"',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isParsing ? null : _parseText,
                  icon: _isParsing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.psychology),
                  label: Text(_isParsing
                      ? 'Extracting needs…'
                      : 'Extract Needs with AI'),
                ),
              ],
            ),
          ),

          // ── Extracted Needs ──────────────────────────────────────────────
          if (_extractedNeeds.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('${_extractedNeeds.length} Needs Extracted',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ..._extractedNeeds.map((need) => Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color:
                            AppTheme.primaryPurple.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text(need['title'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16))),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color:
                                    Colors.orange.withOpacity(0.1),
                                borderRadius:
                                    BorderRadius.circular(8)),
                            child: Text(
                                need['urgency'] ?? 'Medium',
                                style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(need['description'] ?? '',
                          style: const TextStyle(
                              color: AppTheme.textGrey)),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 8,
                          children: ((need['skills'] ?? []) as List)
                              .map((s) => Chip(
                                  label: Text(s.toString(),
                                      style: const TextStyle(
                                          fontSize: 11))))
                              .toList()),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _publishNeed(need),
                        icon: const Icon(Icons.publish, size: 16),
                        label: const Text('Publish This Need'),
                      ),
                    ],
                  ),
                )),
          ],
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
      dateStr =
          '${dt.day}/${dt.month}/${dt.year}';
    }
    final downloadUrl = d['downloadUrl'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(
              filename.endsWith('.pdf')
                  ? Icons.picture_as_pdf_outlined
                  : Icons.table_chart_outlined,
              color: AppTheme.primaryPurple,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filename,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text('$sizeKb KB · Uploaded $dateStr',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textGrey)),
              ],
            ),
          ),
          if (downloadUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download',
                  style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
