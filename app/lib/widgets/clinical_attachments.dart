import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local_store.dart';
import '../data/models.dart';
import '../theme/tokens.dart';

/// Optional encrypted PDF/image files on a report, visit, or procedure.
class ClinicalAttachmentsSection extends StatefulWidget {
  const ClinicalAttachmentsSection({
    super.key,
    required this.store,
    required this.ownerType,
    required this.ownerId,
    required this.onChanged,
    this.title = 'Attached files',
    this.emptyHint =
        'Optional — add a PDF or photo so you can open it from this device later.',
  });

  final LocalStore store;
  final String ownerType;
  final String ownerId;
  final VoidCallback onChanged;
  final String title;
  final String emptyHint;

  @override
  State<ClinicalAttachmentsSection> createState() =>
      _ClinicalAttachmentsSectionState();
}

class _ClinicalAttachmentsSectionState
    extends State<ClinicalAttachmentsSection> {
  List<AttachmentRecord> _atts = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ClinicalAttachmentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId ||
        oldWidget.ownerType != widget.ownerType) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final atts = await widget.store.listAttachments(
      ownerType: widget.ownerType,
      ownerId: widget.ownerId,
    );
    if (!mounted) return;
    setState(() {
      _atts = atts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(widget.emptyHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_atts.isEmpty)
          OutlinedButton.icon(
            onPressed: _attach,
            icon: const Icon(Icons.attach_file),
            label: const Text('Attach PDF or image'),
            style: OutlinedButton.styleFrom(
              foregroundColor: BodylineColors.tealDark,
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: BodylineColors.border),
            ),
          )
        else ...[
          for (final a in _atts) _attRow(a),
          TextButton.icon(
            onPressed: _attach,
            icon: const Icon(Icons.add),
            label: const Text('Add another file'),
          ),
        ],
      ],
    );
  }

  Widget _attRow(AttachmentRecord a) {
    final kb = (a.byteSize / 1024).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: BodylineColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
          side: BorderSide(color: BodylineColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.description_outlined,
                  color: BodylineColors.tealDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.fileName ?? 'Attachment',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$kb KB · encrypted on this device',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open',
                onPressed: () => _open(a),
                icon: const Icon(Icons.open_in_new, size: 20),
              ),
              IconButton(
                tooltip: 'Share',
                onPressed: () => _share(a),
                icon: const Icon(Icons.ios_share, size: 20),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => _remove(a),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove(AttachmentRecord a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove file?'),
        content: Text(
          'Remove ${a.fileName ?? 'this file'} from this record? '
          'It stays encrypted until wiped with the vault.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.softDeleteAttachment(a.id);
    widget.onChanged();
    await _load();
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'heic'],
      withData: false,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      await widget.store.addAttachment(
        ownerType: widget.ownerType,
        ownerId: widget.ownerId,
        filePath: path,
        mime: mimeForExtension(f.extension),
        fileName: f.name,
      );
    }
    widget.onChanged();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File saved encrypted on this device.')),
      );
    }
  }

  Future<void> _open(AttachmentRecord a) async {
    try {
      final file = await widget.store.materializeAttachment(a);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that file.')),
      );
    }
  }

  Future<void> _share(AttachmentRecord a) async {
    try {
      final file = await widget.store.materializeAttachment(a);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: a.mime, name: a.fileName)],
        subject: a.fileName ?? 'bodyline file',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share that file.')),
      );
    }
  }
}

String mimeForExtension(String? ext) {
  switch ((ext ?? '').toLowerCase()) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    default:
      return 'application/octet-stream';
  }
}

/// Pick files before an owner row exists; caller attaches after save.
Future<List<PendingClinicalFile>> pickClinicalFiles() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'heic'],
    withData: false,
    allowMultiple: true,
  );
  if (result == null || result.files.isEmpty) return const [];
  return [
    for (final f in result.files)
      if (f.path != null)
        PendingClinicalFile(
          path: f.path!,
          mime: mimeForExtension(f.extension),
          fileName: f.name,
        ),
  ];
}

class PendingClinicalFile {
  const PendingClinicalFile({
    required this.path,
    required this.mime,
    required this.fileName,
  });
  final String path;
  final String mime;
  final String fileName;
}

Future<void> attachPendingFiles({
  required LocalStore store,
  required String ownerType,
  required String ownerId,
  required List<PendingClinicalFile> files,
}) async {
  for (final f in files) {
    await store.addAttachment(
      ownerType: ownerType,
      ownerId: ownerId,
      filePath: f.path,
      mime: f.mime,
      fileName: f.fileName,
    );
  }
}
