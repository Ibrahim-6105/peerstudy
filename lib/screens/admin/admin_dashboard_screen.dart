// Corrected two-tab Admin Dashboard for PeerStudy.
//
// Beginner note:
// Admins manage the academic catalog and official PDFs in the first tab. They
// review Student reports in the second tab. Supabase RLS independently checks
// every read and write, so hiding a button is never the security boundary.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:peerstudy/models/community_attachment.dart';
import 'package:peerstudy/routes/app_routes.dart';
import 'package:peerstudy/screens/admin/admin_form_pages.dart';
import 'package:peerstudy/services/auth_service.dart';
import 'package:peerstudy/services/backend_api_service.dart';
import 'package:peerstudy/services/supabase_service.dart';
import 'package:peerstudy/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// A short alias makes database rows less intimidating in this beginner file.
typedef _Row = Map<String, dynamic>;

// AdminDashboardScreen owns the two use-case groups required by the PDF.
class AdminDashboardScreen extends StatefulWidget {
  // The const constructor lets the router build this page efficiently.
  const AdminDashboardScreen({super.key});

  // Flutter asks this method for the mutable page state.
  @override
  State<AdminDashboardScreen> createState() {
    return _AdminDashboardScreenState();
  }
}

// The page state handles one shared refresh signal and safe sign-out.
class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  // Changing this number tells both tabs to reload their canonical rows.
  int _refreshVersion = 0;

  // This flag prevents a double sign-out tap.
  bool _isSigningOut = false;

  // Sign out of Supabase and remove every protected route from navigation.
  Future<void> _signOut() async {
    // Ignore a second tap while the first request is running.
    if (_isSigningOut) return;

    // Disable the button and show progress.
    setState(() => _isSigningOut = true);

    // The simple Auth service closes the real Supabase session.
    await AuthService.instance.signOut();

    // Do not use this State after an asynchronous page removal.
    if (!mounted) return;

    // Replace the complete Admin navigation stack with the Login page.
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  // Build one predictable dashboard with the two corrected Admin use cases.
  @override
  Widget build(BuildContext context) {
    // DefaultTabController keeps tab state simple for a student project.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        // The app bar always exposes refresh and sign-out.
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          actions: <Widget>[
            // Settings lets an Admin choose the same Light or Dark appearance.
            IconButton(
              tooltip: 'Appearance settings',
              onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
              icon: const Icon(Icons.settings_outlined),
            ),
            // Refresh reloads both tabs from the authoritative backend.
            IconButton(
              tooltip: 'Refresh Admin data',
              onPressed: () => setState(() => _refreshVersion++),
              icon: const Icon(Icons.refresh_rounded),
            ),
            // Sign-out progress replaces the normal icon during the request.
            IconButton(
              tooltip: 'Sign out',
              onPressed: _isSigningOut ? null : _signOut,
              icon: _isSigningOut
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded),
            ),
          ],
          // These labels are the two Admin use-case groups in the corrected PDF.
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.account_tree_outlined), text: 'Academic'),
              Tab(icon: Icon(Icons.flag_outlined), text: 'Reports'),
            ],
          ),
        ),
        // Each child receives the refresh number as a reload key.
        body: SafeArea(
          child: TabBarView(
            children: <Widget>[
              _AcademicContentTab(refreshVersion: _refreshVersion),
              _ReportsTab(refreshVersion: _refreshVersion),
            ],
          ),
        ),
      ),
    );
  }
}

// _AcademicContentTab manages Area -> Department -> Subject -> Material.
class _AcademicContentTab extends StatefulWidget {
  // refreshVersion changes whenever the app-bar refresh button is pressed.
  const _AcademicContentTab({required this.refreshVersion});

  // Parent-controlled reload signal.
  final int refreshVersion;

  // Flutter creates the mutable catalog state here.
  @override
  State<_AcademicContentTab> createState() => _AcademicContentTabState();
}

// This state intentionally keeps the hierarchy in four small row lists.
class _AcademicContentTabState extends State<_AcademicContentTab> {
  // The public mobile client carries only the Supabase publishable key.
  SupabaseClient get _client => SupabaseService.client;

  // Official PDF operations are centralized in the protected backend gateway.
  final BackendApiService _backend = BackendApiService();

  // The one school supplies parent context for Academic Areas.
  _Row? _school;

  // Canonical catalog rows loaded under Admin RLS.
  List<_Row> _areas = const <_Row>[];
  List<_Row> _departments = const <_Row>[];
  List<_Row> _subjects = const <_Row>[];
  List<_Row> _materials = const <_Row>[];

  // These UUIDs represent the current hierarchy selection.
  String? _areaId;
  String? _departmentId;
  String? _subjectId;

  // Loading and error states are explicit instead of showing sample content.
  bool _isLoading = true;
  bool _isWorking = false;
  String? _errorMessage;

  // The first frame immediately loads authoritative catalog data.
  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  // A changed app-bar refresh version starts a new read.
  @override
  void didUpdateWidget(covariant _AcademicContentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _loadCatalog();
    }
  }

  // Read all small hierarchy tables and keep valid current selections.
  Future<void> _loadCatalog() async {
    // Show full progress only when no catalog has been drawn yet.
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Independent catalog reads run together to reduce dashboard latency.
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _client.from('schools').select().order('name'),
        _client
            .from('academic_areas')
            .select()
            .order('display_order')
            .order('name'),
        _client
            .from('departments')
            .select()
            .order('display_order')
            .order('name'),
        _client.from('subjects').select().order('display_order').order('name'),
      ]);

      // Convert PostgREST dynamic data into predictable string-key maps.
      final schools = _rows(results[0]);
      final areas = _rows(results[1]);
      final departments = _rows(results[2]);
      final subjects = _rows(results[3]);

      // Stop if this tab was removed while the network request ran.
      if (!mounted) return;

      // Preserve a selected UUID only while its row still exists.
      final nextAreaId =
          _existingId(_areaId, areas) ??
          (areas.isEmpty ? null : _id(areas.first));
      final visibleDepartments = departments
          .where((row) => row['area_id']?.toString() == nextAreaId)
          .toList(growable: false);
      final nextDepartmentId =
          _existingId(_departmentId, visibleDepartments) ??
          (visibleDepartments.isEmpty ? null : _id(visibleDepartments.first));
      final visibleSubjects = subjects
          .where((row) => row['department_id']?.toString() == nextDepartmentId)
          .toList(growable: false);
      final nextSubjectId =
          _existingId(_subjectId, visibleSubjects) ??
          (visibleSubjects.isEmpty ? null : _id(visibleSubjects.first));

      // Publish one consistent hierarchy selection.
      setState(() {
        _school = schools.isEmpty ? null : schools.first;
        _areas = areas;
        _departments = departments;
        _subjects = subjects;
        _areaId = nextAreaId;
        _departmentId = nextDepartmentId;
        _subjectId = nextSubjectId;
        _isLoading = false;
      });

      // Official materials are scoped to the final selected Subject.
      await _loadMaterials();
    } on Object catch (error) {
      // Store a friendly error while keeping the tab retryable.
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyAdminError(error);
      });
    }
  }

  // Read every material state so Admins can resume or remove failed uploads.
  Future<void> _loadMaterials() async {
    // No Subject means there can be no material query.
    final subjectId = _subjectId;
    if (subjectId == null || subjectId.isEmpty) {
      if (mounted) setState(() => _materials = const <_Row>[]);
      return;
    }

    try {
      // Admin RLS returns approved, uploading, and removed metadata.
      final response = await _client
          .from('subject_materials')
          .select()
          .eq('subject_id', subjectId)
          .order('display_order')
          .order('created_at', ascending: false);

      // Ignore the result if selection changed during the request.
      if (!mounted || _subjectId != subjectId) return;
      setState(() => _materials = _rows(response));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyAdminError(error));
    }
  }

  // Change the selected Area and reset its dependent levels.
  Future<void> _selectArea(String? value) async {
    // A null Dropdown value represents no valid selection.
    setState(() {
      _areaId = value;
      final departments = _visibleDepartmentsFor(value);
      _departmentId = departments.isEmpty ? null : _id(departments.first);
      final subjects = _visibleSubjectsFor(_departmentId);
      _subjectId = subjects.isEmpty ? null : _id(subjects.first);
      _materials = const <_Row>[];
    });
    await _loadMaterials();
  }

  // Change the selected Department and reset the Subject level.
  Future<void> _selectDepartment(String? value) async {
    setState(() {
      _departmentId = value;
      final subjects = _visibleSubjectsFor(value);
      _subjectId = subjects.isEmpty ? null : _id(subjects.first);
      _materials = const <_Row>[];
    });
    await _loadMaterials();
  }

  // Change only the Subject and reload its official PDFs.
  Future<void> _selectSubject(String? value) async {
    setState(() {
      _subjectId = value;
      _materials = const <_Row>[];
    });
    await _loadMaterials();
  }

  // Return Departments below one selected Area.
  List<_Row> _visibleDepartmentsFor(String? areaId) {
    return _departments
        .where((row) => row['area_id']?.toString() == areaId)
        .toList(growable: false);
  }

  // Return Subjects below one selected Department.
  List<_Row> _visibleSubjectsFor(String? departmentId) {
    return _subjects
        .where((row) => row['department_id']?.toString() == departmentId)
        .toList(growable: false);
  }

  // Add or edit one Academic Area under the fixed school.
  Future<void> _editArea({_Row? existing}) async {
    // A missing school means the seed invariant must be repaired first.
    final schoolId = _school?['id']?.toString() ?? '';
    if (schoolId.isEmpty) {
      _showMessage('The School record is missing. Refresh the database seed.');
      return;
    }

    // Open a quiet full page so the form remains comfortable on a phone.
    final input = await Navigator.push<AcademicAreaFormValue>(
      context,
      MaterialPageRoute<AcademicAreaFormValue>(
        builder: (context) => AcademicAreaFormPage(existing: existing),
      ),
    );
    if (!mounted || input == null) return;

    // Execute one Admin-only direct table mutation.
    await _runAdminWrite(() async {
      final values = <String, dynamic>{
        'school_id': schoolId,
        'code': input.code,
        'name': input.name,
        'status': input.status,
        'display_order': input.displayOrder,
      };
      if (existing == null) {
        await _client.from('academic_areas').insert(values);
      } else {
        await _client
            .from('academic_areas')
            .update(values)
            .eq('id', _id(existing));
      }
    }, successMessage: existing == null ? 'Area added.' : 'Area updated.');
  }

  // Add or edit one Department under the selected Area.
  Future<void> _editDepartment({_Row? existing}) async {
    // A Department always needs an Area parent.
    final areaId = _areaId;
    if (areaId == null) {
      _showMessage('Choose an Academic Area first.');
      return;
    }

    // Show the selected parent on a full-page Department form.
    final selectedArea = _rowById(_areas, areaId);
    final input = await Navigator.push<DepartmentFormValue>(
      context,
      MaterialPageRoute<DepartmentFormValue>(
        builder: (context) => DepartmentFormPage(
          areaName: selectedArea?['name']?.toString() ?? 'Selected area',
          existing: existing,
        ),
      ),
    );
    if (!mounted || input == null) return;

    // Save the row under Admin-only RLS.
    await _runAdminWrite(
      () async {
        final values = <String, dynamic>{
          'area_id': areaId,
          'name': input.name,
          'status': input.status,
          'display_order': input.displayOrder,
        };
        if (existing == null) {
          await _client.from('departments').insert(values);
        } else {
          await _client
              .from('departments')
              .update(values)
              .eq('id', _id(existing));
        }
      },
      successMessage: existing == null
          ? 'Department added.'
          : 'Department updated.',
    );
  }

  // Add or edit one Subject; creation also creates its one Community atomically.
  Future<void> _editSubject({_Row? existing}) async {
    // A Subject always needs a Department parent.
    final departmentId = _departmentId;
    if (departmentId == null) {
      _showMessage('Choose a Department first.');
      return;
    }

    // Collect the corrected fields on one grouped, keyboard-safe full page.
    final selectedDepartment = _rowById(_departments, departmentId);
    final input = await Navigator.push<SubjectFormValue>(
      context,
      MaterialPageRoute<SubjectFormValue>(
        builder: (context) => SubjectFormPage(
          departmentName:
              selectedDepartment?['name']?.toString() ?? 'Selected department',
          existing: existing,
        ),
      ),
    );
    if (!mounted || input == null) return;

    // Subject creation uses the transaction RPC required by the corrected PDF.
    await _runAdminWrite(
      () async {
        if (existing == null) {
          await _client.rpc(
            'admin_create_subject_with_community',
            params: <String, Object?>{
              'p_department_id': departmentId,
              'p_code': input.code,
              'p_name': input.name,
              'p_description': input.description,
              'p_study_level': input.studyLevel,
              'p_semester': input.semester,
              'p_display_order': input.displayOrder,
              'p_status': input.status,
            },
          );
        } else {
          await _client
              .from('subjects')
              .update(<String, dynamic>{
                'code': input.code,
                'name': input.name,
                'description': input.description,
                'study_level': input.studyLevel,
                'semester': input.semester,
                'display_order': input.displayOrder,
                'status': input.status,
              })
              .eq('id', _id(existing));
        }
      },
      successMessage: existing == null
          ? 'Subject and Community added.'
          : 'Subject updated.',
    );
  }

  // Confirm and delete one catalog row; foreign keys safely block unsafe deletes.
  Future<void> _deleteCatalogRow({
    required String table,
    required _Row row,
    required String label,
  }) async {
    // The confirmation names the exact target.
    final confirmed = await _confirm(
      title: 'Delete $label?',
      message:
          'Delete "${row['name']}"? Rows with dependent content are protected by the database.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;

    // Admin RLS and foreign keys make this mutation fail closed.
    await _runAdminWrite(
      () => _client.from(table).delete().eq('id', _id(row)),
      successMessage: '$label deleted.',
    );
  }

  // Pick, upload, checksum, and approve one official PDF.
  Future<void> _uploadMaterial({_Row? replacing}) async {
    // Official materials always belong to the selected Subject.
    final subjectId = _subjectId;
    if (subjectId == null) {
      _showMessage('Choose a Subject first.');
      return;
    }

    // Select one PDF and keep its bytes for the official signed-upload method.
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf'],
      allowMultiple: false,
      withData: true,
    );
    // The Admin may have left this tab while the system file picker was open.
    if (!mounted) return;
    if (selection == null || selection.files.isEmpty) return;
    final file = selection.files.single;
    if (file.bytes == null || file.size <= 0 || file.size > 25 * 1024 * 1024) {
      _showMessage('Choose a readable PDF no larger than 25 MB.');
      return;
    }

    // Review metadata on a full page before creating the protected upload.
    final details = await Navigator.push<MaterialFormValue>(
      context,
      MaterialPageRoute<MaterialFormValue>(
        builder: (context) => MaterialFormPage(
          fileName: file.name,
          existing: replacing,
          isReplacingFile: replacing != null,
        ),
      ),
    );
    if (!mounted || details == null) return;

    // Keep the screen visibly busy throughout the complete safe workflow.
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      // First create fail-closed uploading metadata and a signed private path.
      final session = await _backend.createMaterialUpload(
        subjectId: subjectId,
        title: details.title,
        summary: details.summary,
        fileName: file.name,
        sizeBytes: file.size,
        displayOrder: details.displayOrder,
        materialId: replacing == null ? null : _id(replacing),
        expectedVersion: replacing?['version'] as int?,
      );

      // Then upload exact bytes and save their SHA-256 checksum.
      await _backend.uploadSignedStream(
        session: session,
        bytes: Stream<List<int>>.value(file.bytes!),
        sizeBytes: file.size,
      );

      // Finally approve the metadata only after the upload and checksum succeed.
      await _backend.finalizeMaterialUpload(session.uploadId);

      // Reload all canonical metadata and announce the real result.
      await _loadCatalog();
      if (!mounted) return;
      _showMessage(replacing == null ? 'PDF uploaded.' : 'PDF replaced.');
    } on Object catch (error) {
      // A failed workflow leaves an uploading row, never a fake approved PDF.
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyAdminError(error));
    } finally {
      // Re-enable controls after success or failure.
      if (mounted) setState(() => _isWorking = false);
    }
  }

  // Edit title, summary, and order without replacing verified PDF bytes.
  Future<void> _editMaterialMetadata(_Row material) async {
    // Edit safe metadata on the same full-page form without replacing bytes.
    final input = await Navigator.push<MaterialFormValue>(
      context,
      MaterialPageRoute<MaterialFormValue>(
        builder: (context) => MaterialFormPage(
          fileName: material['storage_path']?.toString() ?? 'PDF',
          existing: material,
        ),
      ),
    );
    if (!mounted || input == null) return;

    // The backend updates only safe metadata fields.
    await _runAdminWrite(() async {
      await _backend.updateMaterialMetadata(
        materialId: _id(material),
        expectedVersion: (material['version'] as num?)?.toInt() ?? 1,
        title: input.title,
        summary: input.summary,
        displayOrder: input.displayOrder,
      );
    }, successMessage: 'Material details updated.');
  }

  // Remove official PDF bytes and keep a removed audit metadata row.
  Future<void> _removeMaterial(_Row material) async {
    // Confirm the exact title before deleting private Storage bytes.
    final confirmed = await _confirm(
      title: 'Remove official PDF?',
      message:
          'Remove "${material['title']}" from Student access and private Storage?',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;

    // BackendApiService coordinates private byte removal and row status.
    await _runAdminWrite(() async {
      await _backend.archiveMaterial(
        materialId: _id(material),
        expectedVersion: (material['version'] as num?)?.toInt() ?? 1,
        reason: 'Removed by Admin from Academic Content',
      );
    }, successMessage: 'Official PDF removed.');
  }

  // Run one Admin mutation with uniform progress, refresh, and error handling.
  Future<void> _runAdminWrite(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    // Do not allow overlapping catalog mutations.
    if (_isWorking) return;
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      // Execute the protected mutation and reload authoritative rows.
      await action();
      await _loadCatalog();
      if (mounted) _showMessage(successMessage);
    } on Object catch (error) {
      // Keep the technical exception out of the visual UI.
      if (mounted) {
        setState(() => _errorMessage = _friendlyAdminError(error));
      }
    } finally {
      // Always re-enable the controls.
      if (mounted) setState(() => _isWorking = false);
    }
  }

  // Show one reusable destructive confirmation dialog.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    // Null from a dismissed dialog is treated as cancel.
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  // Show a short result at the bottom of the current tab.
  void _showMessage(String message) {
    // Replace an old snackbar so the latest operation is unambiguous.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Draw the simple hierarchy selectors and official material list.
  @override
  Widget build(BuildContext context) {
    // The first load uses one centered progress indicator.
    if (_isLoading && _areas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter dependent rows from the canonical in-memory catalog.
    final visibleDepartments = _visibleDepartmentsFor(_areaId);
    final visibleSubjects = _visibleSubjectsFor(_departmentId);
    final selectedArea = _rowById(_areas, _areaId);
    final selectedDepartment = _rowById(_departments, _departmentId);
    final selectedSubject = _rowById(_subjects, _subjectId);

    // RefreshIndicator gives touch users a second familiar reload gesture.
    return RefreshIndicator(
      onRefresh: _loadCatalog,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          // Keep content readable on tablets as well as phones.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.contentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Explain the fixed hierarchy without technical jargon.
                  Text(
                    _school?['name']?.toString() ??
                        'School of Technology and Engineering',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Manage Area -> Department -> Subject, then its approved PDF Materials.',
                  ),
                  if (_isWorking) ...<Widget>[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _AdminErrorCard(
                      message: _errorMessage!,
                      onRetry: _loadCatalog,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Area selector and CRUD controls.
                  _CatalogSelectorCard(
                    title: '1. Academic Area',
                    selectedId: _areaId,
                    rows: _areas,
                    onChanged: _isWorking ? null : _selectArea,
                    onAdd: _isWorking ? null : () => _editArea(),
                    onEdit: _isWorking || selectedArea == null
                        ? null
                        : () => _editArea(existing: selectedArea),
                    onDelete: _isWorking || selectedArea == null
                        ? null
                        : () => _deleteCatalogRow(
                            table: 'academic_areas',
                            row: selectedArea,
                            label: 'Academic Area',
                          ),
                  ),
                  const SizedBox(height: 12),
                  // Department selector and CRUD controls.
                  _CatalogSelectorCard(
                    title: '2. Department',
                    selectedId: _departmentId,
                    rows: visibleDepartments,
                    onChanged: _isWorking ? null : _selectDepartment,
                    onAdd: _isWorking || _areaId == null
                        ? null
                        : () => _editDepartment(),
                    onEdit: _isWorking || selectedDepartment == null
                        ? null
                        : () => _editDepartment(existing: selectedDepartment),
                    onDelete: _isWorking || selectedDepartment == null
                        ? null
                        : () => _deleteCatalogRow(
                            table: 'departments',
                            row: selectedDepartment,
                            label: 'Department',
                          ),
                  ),
                  const SizedBox(height: 12),
                  // Subject selector and atomic create-with-Community controls.
                  _CatalogSelectorCard(
                    title: '3. Subject',
                    selectedId: _subjectId,
                    rows: visibleSubjects,
                    onChanged: _isWorking ? null : _selectSubject,
                    onAdd: _isWorking || _departmentId == null
                        ? null
                        : () => _editSubject(),
                    onEdit: _isWorking || selectedSubject == null
                        ? null
                        : () => _editSubject(existing: selectedSubject),
                    onDelete: _isWorking || selectedSubject == null
                        ? null
                        : () => _deleteCatalogRow(
                            table: 'subjects',
                            row: selectedSubject,
                            label: 'Subject',
                          ),
                  ),
                  const SizedBox(height: 14),
                  // Material management belongs to the selected Subject.
                  _MaterialsCard(
                    subject: selectedSubject,
                    materials: _materials,
                    isWorking: _isWorking,
                    onUpload: selectedSubject == null || _isWorking
                        ? null
                        : () => _uploadMaterial(),
                    onReplace: _isWorking
                        ? null
                        : (material) => _uploadMaterial(replacing: material),
                    onEdit: _isWorking ? null : _editMaterialMetadata,
                    onRemove: _isWorking ? null : _removeMaterial,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// _ReportsTab lists pending and resolved reports and their exact targets.
class _ReportsTab extends StatefulWidget {
  // The parent increments this value after the Admin taps refresh.
  const _ReportsTab({required this.refreshVersion});

  // Parent-controlled reload signal.
  final int refreshVersion;

  // Flutter creates mutable report state here.
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

// Report state keeps target previews separate from immutable report rows.
class _ReportsTabState extends State<_ReportsTab> {
  // The initialized client automatically carries the Admin JWT.
  SupabaseClient get _client => SupabaseService.client;

  // Moderation decisions use the protected atomic RPC gateway.
  final BackendApiService _backend = BackendApiService();

  // Bounded report list, newest-first.
  List<_Row> _reports = const <_Row>[];

  // Target UUID maps to its safe author/body preview.
  Map<String, _Row> _targets = const <String, _Row>{};

  // Target UUID maps to ready private files needed for a moderation decision.
  Map<String, List<CommunityAttachment>> _attachmentsByTarget =
      const <String, List<CommunityAttachment>>{};

  // True shows pending reports; false shows resolved history.
  bool _showPending = true;

  // Explicit progress and failure states prevent sample rows.
  bool _isLoading = true;
  String? _workingReportId;
  String? _errorMessage;

  // Load reports when this tab is first created.
  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  // Reload after the shared app-bar refresh button is pressed.
  @override
  void didUpdateWidget(covariant _ReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) {
      _loadReports();
    }
  }

  // Load report rows, then separately load their current target previews.
  Future<void> _loadReports() async {
    // Keep old rows visible only while a refresh is in progress.
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // A bounded history protects phone memory while covering current work.
      final response = await _client
          .from('reports')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      final reports = _rows(response);

      // Split target UUIDs by their exact report target type.
      final postIds = reports
          .where((row) => row['target_type'] == 'post')
          .map((row) => row['target_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      final commentIds = reports
          .where((row) => row['target_type'] == 'comment')
          .map((row) => row['target_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      // Load only current target fields required for a moderation decision.
      final targetResults = await Future.wait<dynamic>(<Future<dynamic>>[
        postIds.isEmpty
            ? Future<dynamic>.value(<dynamic>[])
            : _client
                  .from('community_posts')
                  .select('id, author_id, author_name, body, status, version')
                  .inFilter('id', postIds),
        commentIds.isEmpty
            ? Future<dynamic>.value(<dynamic>[])
            : _client
                  .from('community_comments')
                  .select('id, author_id, author_name, body, status, version')
                  .inFilter('id', commentIds),
        postIds.isEmpty
            ? Future<dynamic>.value(<dynamic>[])
            : _client
                  .from('community_attachments')
                  .select()
                  .inFilter('post_id', postIds)
                  .eq('status', 'ready')
                  .order('created_at'),
        commentIds.isEmpty
            ? Future<dynamic>.value(<dynamic>[])
            : _client
                  .from('community_attachments')
                  .select()
                  .inFilter('comment_id', commentIds)
                  .eq('status', 'ready')
                  .order('created_at'),
      ]);

      // Merge both target kinds by UUID for O(1) report-card lookup.
      final targetMap = <String, _Row>{};
      for (final row in <_Row>[
        ..._rows(targetResults[0]),
        ..._rows(targetResults[1]),
      ]) {
        targetMap[_id(row)] = row;
      }

      // Group attachments under the exact reported post or comment UUID.
      final attachmentMap = <String, List<CommunityAttachment>>{};
      for (final row in <_Row>[
        ..._rows(targetResults[2]),
        ..._rows(targetResults[3]),
      ]) {
        final attachment = CommunityAttachment.fromSupabaseRow(row);
        final targetId = attachment.postId ?? attachment.commentId;
        if (attachment.id.isEmpty || targetId == null) continue;
        attachmentMap.putIfAbsent(targetId, () => []).add(attachment);
      }

      // Publish only after both reports and target previews are ready.
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _targets = Map<String, _Row>.unmodifiable(targetMap);
        _attachmentsByTarget =
            Map<String, List<CommunityAttachment>>.unmodifiable(<
              String,
              List<CommunityAttachment>
            >{
              for (final entry in attachmentMap.entries)
                entry.key: List<CommunityAttachment>.unmodifiable(entry.value),
            });
        _isLoading = false;
      });
    } on Object catch (error) {
      // Keep the failure retryable and do not invent target content.
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyAdminError(error);
      });
    }
  }

  // Ask for a resolution note, then atomically resolve one pending report.
  Future<void> _resolve(_Row report, String action) async {
    // One report action at a time prevents duplicate decisions.
    if (_workingReportId != null) return;

    // A meaningful note is required by the backend audit constraint.
    final note = await _askForResolutionNote(action);
    if (note == null) return;

    // Mark only this card busy.
    setState(() {
      _workingReportId = _id(report);
      _errorMessage = null;
    });

    try {
      // The RPC combines resolution and optional remove/restrict atomically.
      await _backend.moderateReport(
        reportId: _id(report),
        action: action,
        expectedReportVersion: 1,
        expectedTargetVersion:
            (_targets[report['target_id']?.toString()]?['version'] as num?)
                ?.toInt() ??
            1,
        resolutionNote: note,
      );

      // Reload exact status, target state, and history after success.
      await _loadReports();
      if (!mounted) return;
      _showMessage('Report action completed.');
    } on Object catch (error) {
      // Preserve the pending report and show a useful error.
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyAdminError(error));
    } finally {
      // Re-enable every card.
      if (mounted) setState(() => _workingReportId = null);
    }
  }

  // Collect the required five-or-more-character Admin audit note.
  Future<String?> _askForResolutionNote(String action) async {
    // A local controller owns the dialog text only.
    final controller = TextEditingController();

    // showDialog returns the trimmed note or null on cancel.
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_actionLabel(action)} report'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Resolution note',
            hintText: 'Explain the Admin decision',
            alignLabelWithHint: true,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length >= 5) Navigator.pop(dialogContext, text);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    // Dispose the temporary input after the dialog closes.
    controller.dispose();
    return result;
  }

  // Show one operation result at the bottom of the page.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Draw filter controls followed by the selected real report rows.
  @override
  Widget build(BuildContext context) {
    // Pending is one status; every other allowed status is resolved history.
    final visibleReports = _reports
        .where((report) {
          final isPending = report['status'] == 'pending';
          return _showPending ? isPending : !isPending;
        })
        .toList(growable: false);

    // The first load uses one central progress indicator.
    if (_isLoading && _reports.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Pull-to-refresh works even when no reports exist.
    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.contentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Reports Management',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Dismiss the report, remove its exact content, or restrict the content author.',
                  ),
                  const SizedBox(height: 12),
                  // SegmentedButton makes pending/history state unmistakable.
                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.pending_actions_outlined),
                        label: Text('Pending'),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.history_rounded),
                        label: Text('Resolved'),
                      ),
                    ],
                    selected: <bool>{_showPending},
                    onSelectionChanged: (selection) {
                      setState(() => _showPending = selection.first);
                    },
                  ),
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _AdminErrorCard(
                      message: _errorMessage!,
                      onRetry: _loadReports,
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Empty state is honest and does not create sample reports.
                  if (visibleReports.isEmpty)
                    _EmptyAdminCard(
                      icon: _showPending
                          ? Icons.task_alt_rounded
                          : Icons.history_toggle_off_rounded,
                      title: _showPending
                          ? 'No pending reports'
                          : 'No resolved reports',
                      message: _showPending
                          ? 'Student reports that need action will appear here.'
                          : 'Completed Admin decisions will appear here.',
                    )
                  else
                    // Each report card preserves target, reason, and action.
                    for (final report in visibleReports) ...<Widget>[
                      _ReportCard(
                        report: report,
                        target: _targets[report['target_id']?.toString()],
                        attachments:
                            _attachmentsByTarget[report['target_id']
                                ?.toString()] ??
                            const <CommunityAttachment>[],
                        isWorking: _workingReportId == _id(report),
                        onAction: report['status'] == 'pending'
                            ? (action) => _resolve(report, action)
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// _CatalogSelectorCard shows one hierarchy level and its CRUD buttons.
class _CatalogSelectorCard extends StatelessWidget {
  // All callbacks become null while an Admin mutation is running.
  const _CatalogSelectorCard({
    required this.title,
    required this.selectedId,
    required this.rows,
    required this.onChanged,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  // Visible hierarchy label.
  final String title;

  // Selected row UUID.
  final String? selectedId;

  // Rows available at this parent level.
  final List<_Row> rows;

  // Selection and CRUD actions.
  final ValueChanged<String?>? onChanged;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  // Draw a dropdown followed by beginner-obvious action buttons.
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Add item',
                  visualDensity: VisualDensity.compact,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Edit selected item',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  tooltip: 'Delete selected item',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey<String?>('$title:$selectedId:${rows.length}'),
              initialValue: _existingId(selectedId, rows),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Selected item'),
              items: rows
                  .map((row) {
                    final code = row['code']?.toString().trim() ?? '';
                    final name = row['name']?.toString() ?? 'Unnamed';
                    final status = row['status']?.toString() ?? 'inactive';
                    final label = code.isEmpty ? name : '$code - $name';
                    return DropdownMenuItem<String>(
                      value: _id(row),
                      child: Text('$label ($status)'),
                    );
                  })
                  .toList(growable: false),
              onChanged: rows.isEmpty ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// _MaterialsCard shows official PDF state and upload/replace/remove actions.
class _MaterialsCard extends StatelessWidget {
  // The selected Subject may be null when a Department has no Subjects.
  const _MaterialsCard({
    required this.subject,
    required this.materials,
    required this.isWorking,
    required this.onUpload,
    required this.onReplace,
    required this.onEdit,
    required this.onRemove,
  });

  // Current Subject row and its material rows.
  final _Row? subject;
  final List<_Row> materials;
  final bool isWorking;

  // Material callbacks are owned by the state above.
  final VoidCallback? onUpload;
  final ValueChanged<_Row>? onReplace;
  final ValueChanged<_Row>? onEdit;
  final ValueChanged<_Row>? onRemove;

  // Draw the selected Subject's full official material management card.
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.picture_as_pdf_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '4. Official PDF Materials',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onUpload,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Upload'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subject == null
                  ? 'Choose a Subject to manage its approved PDFs.'
                  : 'Subject: ${subject!['code']} - ${subject!['name']}',
            ),
            const Divider(height: 24),
            if (materials.isEmpty)
              const Text('No material metadata exists for this Subject.')
            else
              for (final material in materials) ...<Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(material['title']?.toString() ?? 'Untitled PDF'),
                  subtitle: Text(
                    '${material['status'] ?? 'unknown'} - '
                    '${_formatBytes((material['size_bytes'] as num?)?.toInt() ?? 0)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: !isWorking,
                    tooltip: 'Material actions',
                    onSelected: (action) {
                      if (action == 'edit') onEdit?.call(material);
                      if (action == 'replace') onReplace?.call(material);
                      if (action == 'remove') onRemove?.call(material);
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text('Edit details'),
                      ),
                      PopupMenuItem<String>(
                        value: 'replace',
                        child: Text('Replace PDF'),
                      ),
                      PopupMenuItem<String>(
                        value: 'remove',
                        child: Text('Remove PDF'),
                      ),
                    ],
                  ),
                ),
                if (material != materials.last) const Divider(height: 1),
              ],
          ],
        ),
      ),
    );
  }
}

// _ReportCard displays the exact target and only valid pending actions.
class _ReportCard extends StatelessWidget {
  // target may be null if content was removed outside this report flow.
  const _ReportCard({
    required this.report,
    required this.target,
    required this.attachments,
    required this.isWorking,
    required this.onAction,
  });

  // Canonical report and safe target preview rows.
  final _Row report;
  final _Row? target;
  final List<CommunityAttachment> attachments;

  // Per-card progress and action callback.
  final bool isWorking;
  final ValueChanged<String>? onAction;

  // Draw preserved reason/details, target, timestamps, and decision controls.
  @override
  Widget build(BuildContext context) {
    final targetType = report['target_type']?.toString() ?? 'content';
    final status = report['status']?.toString() ?? 'unknown';
    final targetName =
        target?['author_name']?.toString() ?? 'Unavailable author';
    final targetBody =
        target?['body']?.toString() ??
        'The target is no longer available for preview.';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.flag_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${targetType.toUpperCase()} - ${report['reason']}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Chip(label: Text(status)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Target author: $targetName'),
            const SizedBox(height: 4),
            Text(targetBody, maxLines: 5, overflow: TextOverflow.ellipsis),
            if (attachments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Target attachments (${attachments.length})',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              for (final attachment in attachments) ...<Widget>[
                _AdminReportAttachmentTile(
                  key: ValueKey<String>(attachment.id),
                  attachment: attachment,
                ),
                if (attachment != attachments.last) const SizedBox(height: 5),
              ],
            ],
            if ((report['details']?.toString().trim() ?? '')
                .isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text('Reporter details: ${report['details']}'),
            ],
            const SizedBox(height: 8),
            Text(
              'Reported: ${_formatDate(report['created_at'])}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (status != 'pending') ...<Widget>[
              const SizedBox(height: 4),
              Text('Resolution: ${report['resolution_note'] ?? 'Unavailable'}'),
              Text(
                'Resolved: ${_formatDate(report['resolved_at'])}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onAction != null) ...<Widget>[
              const Divider(height: 24),
              if (isWorking)
                const LinearProgressIndicator()
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => onAction?.call('dismiss'),
                      icon: const Icon(Icons.done_rounded),
                      label: const Text('Dismiss'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => onAction?.call('remove'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove content'),
                    ),
                    FilledButton.icon(
                      onPressed: () => onAction?.call('restrict'),
                      icon: const Icon(Icons.block_rounded),
                      label: const Text('Restrict author'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// Admins can inspect the exact private files before choosing moderation action.
class _AdminReportAttachmentTile extends StatefulWidget {
  const _AdminReportAttachmentTile({required this.attachment, super.key});

  final CommunityAttachment attachment;

  @override
  State<_AdminReportAttachmentTile> createState() =>
      _AdminReportAttachmentTileState();
}

class _AdminReportAttachmentTileState
    extends State<_AdminReportAttachmentTile> {
  final BackendApiService _backend = BackendApiService();
  bool _isOpening = false;

  // A temporary link is created only after this reviewed Admin tap.
  Future<void> _open({bool download = false}) async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    try {
      final uri = await _backend.requestCommunityAttachmentAccess(
        widget.attachment.id,
        download: download,
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('No viewer is available.');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                download
                    ? 'The report attachment could not be downloaded securely.'
                    : 'The report attachment could not be opened securely.',
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: _isOpening ? null : () => _open(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: <Widget>[
                    if (_isOpening)
                      const SizedBox.square(
                        dimension: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _adminAttachmentIcon(widget.attachment.mimeType),
                        size: 20,
                        color: colors.primary,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.attachment.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${formatCommunityAttachmentSize(widget.attachment.sizeBytes)} • Private file',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded, size: 17),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Download report attachment securely',
            visualDensity: VisualDensity.compact,
            onPressed: _isOpening ? null : () => _open(download: true),
            icon: const Icon(Icons.download_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

// Use familiar file icons in the compact moderation card.
IconData _adminAttachmentIcon(String mimeType) {
  if (mimeType.startsWith('image/')) return Icons.image_outlined;
  if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.description_outlined;
}

// _AdminErrorCard renders one friendly retryable backend failure.
class _AdminErrorCard extends StatelessWidget {
  // The parent supplies both the message and canonical reload callback.
  const _AdminErrorCard({required this.message, required this.onRetry});

  // Visible message and retry action.
  final String message;
  final VoidCallback onRetry;

  // Use the theme error container for clear but accessible contrast.
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// _EmptyAdminCard is shared by honest empty report states.
class _EmptyAdminCard extends StatelessWidget {
  // The caller chooses a matching icon, title, and explanation.
  const _EmptyAdminCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  // Visible empty-state values.
  final IconData icon;
  final String title;
  final String message;

  // Draw one calm centered empty state.
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 5),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// Convert a dynamic PostgREST list into predictable string-keyed rows.
List<_Row> _rows(dynamic response) {
  // A non-list response is a backend contract error.
  if (response is! Iterable) {
    throw StateError('Supabase returned invalid Admin data.');
  }

  // Convert each Map implementation into the local row alias.
  return response
      .map<_Row>((item) {
        if (item is Map<String, dynamic>) return item;
        if (item is Map) {
          return item.map((key, value) => MapEntry(key.toString(), value));
        }
        throw StateError('Supabase returned an invalid Admin row.');
      })
      .toList(growable: false);
}

// Read a required row UUID.
String _id(_Row row) {
  // An empty UUID will cause the protected backend mutation to fail safely.
  return row['id']?.toString() ?? '';
}

// Preserve a selection only if its row still exists.
String? _existingId(String? id, List<_Row> rows) {
  // Null and deleted selections both become no selection.
  if (id == null) return null;
  return rows.any((row) => _id(row) == id) ? id : null;
}

// Find one selected row by UUID.
_Row? _rowById(List<_Row> rows, String? id) {
  // A small loop is clearer than throwing firstWhere for an optional result.
  for (final row in rows) {
    if (_id(row) == id) return row;
  }
  return null;
}

// Format private PDF byte size without adding another dependency.
String _formatBytes(int bytes) {
  // Values below one KiB remain exact.
  if (bytes < 1024) return '$bytes B';

  // Values below one MiB use one decimal KiB.
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';

  // Larger official PDFs use one decimal MiB.
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

// Format a Supabase timestamp for a compact report card.
String _formatDate(Object? value) {
  // Parse the ISO-8601 value returned by PostgREST.
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (parsed == null) return 'Unavailable';

  // Use a clear sortable date and minute precision.
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${parsed.year}-$month-$day $hour:$minute';
}

// Convert a report action into a short dialog title.
String _actionLabel(String action) {
  // These are the only values accepted by admin_resolve_report.
  return switch (action) {
    'dismiss' => 'Dismiss',
    'remove' => 'Remove content for',
    'restrict' => 'Restrict author for',
    _ => 'Resolve',
  };
}

// Translate backend errors into useful Admin messages.
String _friendlyAdminError(Object error) {
  // BackendApiService messages are already reviewed for display.
  if (error is BackendException) return error.message;

  // RLS insufficient privilege has one simple explanation.
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return 'This account is not allowed to perform that Admin action.';
    }
    if (error.code == '23503') {
      return 'This item still has dependent content and cannot be deleted.';
    }
    if (error.code == '23505') {
      return 'An item with the same code or name already exists.';
    }
    return error.message;
  }

  // Storage errors remain short and retryable.
  if (error is StorageException) return error.message;

  // Local validation errors already use friendly wording.
  if (error is StateError) return error.message;

  // Unknown errors avoid leaking a stack trace into the UI.
  return 'The Admin operation could not be completed. Refresh and try again.';
}
