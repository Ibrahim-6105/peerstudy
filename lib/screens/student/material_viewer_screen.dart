// Internal secure PDF viewer with scroll, zoom, and page controls.
//
// Beginner note:
// PeerStudy requests a short-lived private URL only while this screen is open.
// The PDF library may use temporary memory/system cache while viewing, but this
// app never creates a permanent material collection on the device.

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:peerstudy/components/error_view.dart';
import 'package:peerstudy/components/loading_view.dart';
import 'package:peerstudy/models/subject.dart';
import 'package:peerstudy/services/backend_api_service.dart';

// MaterialViewerScreen opens one exact approved official PDF.
class MaterialViewerScreen extends StatefulWidget {
  // The Subject workspace passes the selected material metadata.
  const MaterialViewerScreen({super.key, required this.material});

  // This row contains no permanent public URL.
  final StudyMaterial material;

  // Flutter creates the mutable viewer state here.
  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

// Viewer state owns temporary access and the visible page number.
class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  // This controller supplies page navigation and zoom actions.
  final PdfViewerController _pdfController = PdfViewerController();

  // The backend gateway signs approved private Storage paths.
  final BackendApiService _backend = BackendApiService();

  // Access exists only for the current screen session.
  MaterialAccess? _access;

  // A new key rebuilds the PDF widget after a retry obtains a fresh URL.
  Key _viewerKey = UniqueKey();

  // Explicit loading and failure states avoid displaying stale bytes.
  bool _isLoading = true;
  String? _loadError;

  // Page values are updated by the actual document controller.
  int _pageNumber = 1;
  int _pageCount = 0;

  // Request temporary access as soon as the screen opens.
  @override
  void initState() {
    super.initState();
    _openMaterial();
  }

  // Request a fresh ten-minute signed URL for this approved material.
  Future<void> _openMaterial() async {
    // Reset the viewer state before the protected request.
    setState(() {
      _isLoading = true;
      _loadError = null;
      _access = null;
      _pageNumber = 1;
      _pageCount = 0;
    });

    try {
      // BackendApiService verifies status, MIME type, path, and checksum.
      final access = await _backend.requestMaterialAccess(widget.material.id);

      // Ignore a response after the user already closed the viewer.
      if (!mounted) return;

      // Store temporary access only in this in-memory State object.
      setState(() {
        _access = access;
        _viewerKey = UniqueKey();
        _isLoading = false;
      });
    } on Object {
      // Never expose signed URLs, bucket paths, provider data, or stack traces.
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError =
            'This approved PDF could not be opened securely. Check your connection and retry.';
      });
    }
  }

  // Build the internal viewer and its explicit controls.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The material title stays visible while the PDF scrolls.
      appBar: AppBar(
        title: Text(widget.material.title),
        actions: <Widget>[
          // This chip explains that the viewer does not save a permanent copy.
          if (!_isLoading && _loadError == null)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Center(
                child: Tooltip(
                  message: 'The PDF is available only for this secure session',
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(Icons.lock_clock_outlined, size: 18),
                    label: Text('Secure'),
                  ),
                ),
              ),
            ),
        ],
      ),
      // Body switches among real loading, error, and PDF states.
      body: SafeArea(top: false, bottom: false, child: _buildBody()),
      // Page and zoom controls appear only after the document is ready.
      bottomNavigationBar: _buildViewerControls(),
    );
  }

  // Choose the correct full-screen viewer state.
  Widget _buildBody() {
    // First request and retry both use the same honest loading state.
    if (_isLoading) {
      return const LoadingView(message: 'Opening secure PDF...');
    }

    // A failed request offers a fresh signed-access retry.
    if (_loadError != null) {
      return ErrorView(message: _loadError!, onRetry: _openMaterial);
    }

    // A successful state must contain temporary access.
    final access = _access;
    if (access == null) {
      return ErrorView(
        message: 'The secure PDF session is unavailable.',
        onRetry: _openMaterial,
      );
    }

    // PdfViewerParams connects real document state to the visible controls.
    final params = PdfViewerParams(
      // Text semantics improve accessibility for PDFs that contain text.
      forceEnableTextSemantics: true,

      // Ready supplies the authoritative page count and current page.
      onViewerReady: (document, controller) {
        if (!mounted) return;
        setState(() {
          _pageCount = controller.pageCount;
          _pageNumber = controller.pageNumber ?? 1;
        });
      },

      // Scrolling updates the visible page label.
      onPageChanged: (pageNumber) {
        if (!mounted || pageNumber == null) return;
        setState(() => _pageNumber = pageNumber);
      },

      // Network range-download progress appears inside the viewer.
      loadingBannerBuilder: (context, downloaded, total) {
        final progress = total == null || total == 0
            ? null
            : downloaded / total;
        return Center(
          child: SizedBox.square(
            dimension: 30,
            child: CircularProgressIndicator(value: progress, strokeWidth: 2.5),
          ),
        );
      },

      // A damaged or expired document offers a complete signed-access retry.
      errorBannerBuilder: (context, error, stackTrace, documentRef) {
        return ErrorView(
          message: 'This PDF session expired or the file is damaged.',
          onRetry: _openMaterial,
        );
      },
    );

    // Uri range access starts rendering without permanently saving the PDF.
    return PdfViewer.uri(
      access.signedUrl,
      key: _viewerKey,
      controller: _pdfController,
      params: params,
      preferRangeAccess: true,
      timeout: const Duration(seconds: 25),
    );
  }

  // Build page and zoom buttons after the real PDF is ready.
  Widget? _buildViewerControls() {
    // Controls are hidden while there is no authoritative document state.
    if (_isLoading || _loadError != null || _pageCount == 0) return null;

    // SafeArea avoids the Android navigation bar and phone gesture area.
    return SafeArea(
      child: SizedBox(
        height: 54,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Zoom out to the previous safe zoom step.
            IconButton(
              tooltip: 'Zoom out',
              onPressed: _pdfController.zoomDown,
              icon: const Icon(Icons.zoom_out_rounded),
            ),

            // Move to the previous real PDF page.
            IconButton(
              tooltip: 'Previous PDF page',
              onPressed: _pageNumber <= 1
                  ? null
                  : () => _pdfController.goToPage(pageNumber: _pageNumber - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),

            // Announce page changes to screen-reader users.
            Semantics(
              liveRegion: true,
              label: 'PDF page $_pageNumber of $_pageCount',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '$_pageNumber / $_pageCount',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),

            // Move to the next real PDF page.
            IconButton(
              tooltip: 'Next PDF page',
              onPressed: _pageNumber >= _pageCount
                  ? null
                  : () => _pdfController.goToPage(pageNumber: _pageNumber + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),

            // Zoom in to the next safe zoom step.
            IconButton(
              tooltip: 'Zoom in',
              onPressed: _pdfController.zoomUp,
              icon: const Icon(Icons.zoom_in_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
