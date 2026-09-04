// Secure official-PDF opener shared by Students and Admins.
//
// Community PDF attachments already open reliably in the phone's browser or
// installed PDF application. Official lecture PDFs use that same external-app
// path here instead of the embedded renderer that could finish loading and then
// show a blank white canvas on some devices.

import 'package:flutter/material.dart';
import 'package:peerstudy/components/error_view.dart';
import 'package:peerstudy/components/loading_view.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:url_launcher/url_launcher.dart';

// Small injectable boundaries keep the real external-launch behavior testable.
typedef MaterialAccessLoader = Future<Uri> Function(String materialId);
typedef MaterialExternalLauncher = Future<bool> Function(Uri uri);

// MaterialViewerScreen keeps its established name so both existing call sites
// continue to share one implementation. It now prepares and launches the PDF
// externally rather than rendering the document inside a Flutter texture.
class MaterialViewerScreen extends StatefulWidget {
  const MaterialViewerScreen({
    super.key,
    required this.material,
    this.accessLoader,
    this.externalLauncher,
  });

  final StudyMaterial material;

  // Tests can replace network and platform-plugin calls with local callbacks.
  final MaterialAccessLoader? accessLoader;
  final MaterialExternalLauncher? externalLauncher;

  // Guard the originating list as well as the route itself. Without this,
  // two fast taps can push two opener routes before either route builds.
  static final Set<String> _activeMaterialIds = <String>{};

  static Future<void> open(
    BuildContext context, {
    required StudyMaterial material,
    MaterialAccessLoader? accessLoader,
    MaterialExternalLauncher? externalLauncher,
  }) async {
    if (!_activeMaterialIds.add(material.id)) return;
    try {
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => MaterialViewerScreen(
            material: material,
            accessLoader: accessLoader,
            externalLauncher: externalLauncher,
          ),
        ),
      );
    } finally {
      _activeMaterialIds.remove(material.id);
    }
  }

  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  BackendApiService? _backend;

  // This synchronous guard prevents rapid taps or retries from launching twice.
  bool _isOpening = false;
  bool _openedSuccessfully = false;
  String? _openError;

  @override
  void initState() {
    super.initState();
    _openMaterial();
  }

  // Ask Supabase for temporary access and hand it to the same external viewer
  // path used by Community attachments. No permanent public URL is stored.
  Future<void> _openMaterial() async {
    if (_isOpening) return;

    setState(() {
      _isOpening = true;
      _openedSuccessfully = false;
      _openError = null;
    });

    try {
      final customLoader = widget.accessLoader;
      final uri = customLoader != null
          ? await customLoader(widget.material.id)
          : await (_backend ??= BackendApiService()).requestMaterialAccess(
              widget.material.id,
            );
      if (!mounted) return;

      final customLauncher = widget.externalLauncher;
      final opened = customLauncher != null
          ? await customLauncher(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw StateError('No external PDF application accepted the link.');
      }
      if (!mounted) return;

      setState(() {
        _isOpening = false;
        _openedSuccessfully = true;
      });

      // Production always pushes this screen above the Subject/Admin list. A
      // focused root-level test keeps the harmless success state visible.
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isOpening = false;
        _openError = error is BackendException
            ? error.message
            : 'This lecture could not be opened in your PDF app or browser. '
                  'Check your connection and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.material.title)),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isOpening) {
      return const LoadingView(message: 'Opening secure lecture PDF...');
    }

    if (_openError != null) {
      return ErrorView(message: _openError!, onRetry: _openMaterial);
    }

    // This state is normally visible only in a root-level widget test because
    // a successful production launch immediately returns to the previous page.
    if (_openedSuccessfully) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.picture_as_pdf_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                'The lecture PDF opened securely.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openMaterial,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open again'),
              ),
            ],
          ),
        ),
      );
    }

    return ErrorView(
      message: 'The secure lecture link is unavailable.',
      onRetry: _openMaterial,
    );
  }
}
