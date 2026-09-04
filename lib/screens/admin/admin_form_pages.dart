// Full-page Admin forms for the PeerStudy academic catalog and official PDFs.
//
// Beginner note:
// Each form is a normal StatefulWidget. The screen owns its TextEditingController
// objects, validates the fields, and returns one small value object with
// Navigator.pop. There is no state-management package or hidden form logic.

import 'package:flutter/material.dart';

// A database row is passed in only when an Admin edits an existing item.
typedef AdminRow = Map<String, dynamic>;

// DepartmentFormValue contains the validated values returned by the Department page.
class DepartmentFormValue {
  // The constructor groups the three editable Department fields.
  const DepartmentFormValue({
    required this.name,
    required this.status,
    required this.displayOrder,
  });

  // These fields map directly to the departments table.
  final String name;
  final String status;
  final int displayOrder;
}

// SubjectFormValue contains every field needed by the atomic subject RPC.
class SubjectFormValue {
  // The constructor keeps required and optional study details explicit.
  const SubjectFormValue({
    required this.code,
    required this.name,
    required this.description,
    required this.studyLevel,
    required this.semester,
    required this.status,
  });

  // These fields map directly to the subjects table or creation RPC.
  final String code;
  final String name;
  final String description;
  final String? studyLevel;
  final String? semester;
  final String status;
}

// MaterialFormValue contains safe editable metadata and never contains PDF bytes.
class MaterialFormValue {
  // The constructor groups the Student-facing metadata fields.
  const MaterialFormValue({required this.title, required this.summary});

  // These fields are displayed to Students beside the protected PDF.
  final String title;
  final String summary;
}

// DepartmentFormPage adds or edits a Department below the selected Area.
class DepartmentFormPage extends StatefulWidget {
  // The dashboard provides a clear parent label for orientation.
  const DepartmentFormPage({super.key, required this.areaName, this.existing});

  // Parent context and optional existing values.
  final String areaName;
  final AdminRow? existing;

  // Flutter creates local mutable form state here.
  @override
  State<DepartmentFormPage> createState() => _DepartmentFormPageState();
}

// This state owns the small Department form.
class _DepartmentFormPageState extends State<DepartmentFormPage> {
  // Validators are grouped under one FormState key.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Only name and display order need text controllers.
  late final TextEditingController _nameController;
  late final TextEditingController _orderController;
  late String _status;

  // Existing values prefill the Edit page.
  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _nameController = TextEditingController(
      text: row?['name']?.toString() ?? '',
    );
    _orderController = TextEditingController(
      text: row?['display_order']?.toString() ?? '0',
    );
    _status = _safeStatus(row?['status']);
  }

  // Dispose local controllers with the page.
  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  // Return validated Department values to the dashboard.
  void _save() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      DepartmentFormValue(
        name: _nameController.text.trim(),
        status: _status,
        displayOrder: int.parse(_orderController.text.trim()),
      ),
    );
  }

  // Draw one focused phone-friendly page.
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return _AdminFormFrame(
      title: isEditing ? 'Edit department' : 'Add department',
      intro: 'Parent area: ${widget.areaName}',
      saveLabel: isEditing ? 'Save changes' : 'Add department',
      onSave: _save,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _FormSection(
              title: 'Department details',
              description: 'Use the official department name Students know.',
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Department name',
                    prefixIcon: Icon(Icons.business_outlined),
                    counterText: '',
                  ),
                  validator: (value) => _requiredName(value, 160),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FormSection(
              title: 'Visibility and order',
              description: 'Inactive departments stay hidden from Students.',
              children: <Widget>[
                _StatusAndOrderControls(
                  status: _status,
                  orderController: _orderController,
                  onStatusChanged: (value) => setState(() => _status = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// SubjectFormPage is the most detailed Admin form in the academic catalog.
class SubjectFormPage extends StatefulWidget {
  // The selected Department is shown at the top so the parent is unambiguous.
  const SubjectFormPage({
    super.key,
    required this.departmentName,
    this.existing,
  });

  // Parent context and optional current Subject values.
  final String departmentName;
  final AdminRow? existing;

  // Flutter creates ordinary setState form state here.
  @override
  State<SubjectFormPage> createState() => _SubjectFormPageState();
}

// Subject state keeps the Student-facing Subject fields together.
class _SubjectFormPageState extends State<SubjectFormPage> {
  // This key validates the complete form before one database request starts.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers correspond directly to visible text fields.
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _levelController;
  late final TextEditingController _semesterController;
  late String _status;

  // Prefill every field once for Edit, or start with honest blank values for Add.
  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _codeController = TextEditingController(
      text: row?['code']?.toString() ?? '',
    );
    _nameController = TextEditingController(
      text: row?['name']?.toString() ?? '',
    );
    _descriptionController = TextEditingController(
      text: row?['description']?.toString() ?? '',
    );
    _levelController = TextEditingController(
      text: row?['study_level']?.toString() ?? '',
    );
    _semesterController = TextEditingController(
      text: row?['semester']?.toString() ?? '',
    );
    _status = _safeStatus(row?['status']);
  }

  // Dispose every controller when the route is removed.
  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _levelController.dispose();
    _semesterController.dispose();
    super.dispose();
  }

  // Validate all groups and return the exact canonical values.
  void _save() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final level = _levelController.text.trim();
    final semester = _semesterController.text.trim();
    Navigator.pop(
      context,
      SubjectFormValue(
        code: _codeController.text.trim().toUpperCase(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        studyLevel: level.isEmpty ? null : level,
        semester: semester.isEmpty ? null : semester,
        status: _status,
      ),
    );
  }

  // Draw three quiet groups with one fixed Save action at the bottom.
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return _AdminFormFrame(
      title: isEditing ? 'Edit subject' : 'Add subject',
      intro: isEditing
          ? 'Department: ${widget.departmentName}'
          : 'Department: ${widget.departmentName}. A matching Community will be created automatically.',
      saveLabel: isEditing ? 'Save changes' : 'Add subject',
      onSave: _save,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _FormSection(
              title: '1. Catalog identity',
              description: 'Code and name are required.',
              children: <Widget>[
                TextFormField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'Subject code',
                    hintText: 'Example: CS101',
                    prefixIcon: Icon(Icons.tag_rounded),
                    counterText: '',
                  ),
                  validator: _subjectCodeValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 180,
                  decoration: const InputDecoration(
                    labelText: 'Subject name',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                    counterText: '',
                  ),
                  validator: (value) => _requiredName(value, 180),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FormSection(
              title: '2. Study details',
              description:
                  'These details are optional and help Students understand the subject.',
              children: <Widget>[
                TextFormField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    alignLabelWithHint: true,
                    counterText: '',
                  ),
                  validator: (value) => _optionalMaximum(value, 1000),
                ),
                const SizedBox(height: 12),
                _ResponsiveFieldRow(
                  first: TextFormField(
                    controller: _levelController,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Study level (optional)',
                      hintText: 'Example: Year 1',
                      counterText: '',
                    ),
                    validator: (value) => _optionalMaximum(value, 80),
                  ),
                  second: TextFormField(
                    controller: _semesterController,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Semester (optional)',
                      hintText: 'Example: Fall',
                      counterText: '',
                    ),
                    validator: (value) => _optionalMaximum(value, 80),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FormSection(
              title: '3. Visibility',
              description: 'Active subjects appear in the Student catalog.',
              children: <Widget>[
                _StatusControl(
                  status: _status,
                  onStatusChanged: (value) => setState(() => _status = value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// MaterialFormPage edits display metadata before upload or for an existing PDF.
class MaterialFormPage extends StatefulWidget {
  // fileName explains which local or stored PDF the metadata belongs to.
  const MaterialFormPage({
    super.key,
    required this.fileName,
    this.existing,
    this.isReplacingFile = false,
  });

  // The actual PDF bytes stay in the dashboard upload workflow.
  final String fileName;
  final AdminRow? existing;

  // True distinguishes a selected replacement PDF from metadata-only Edit.
  final bool isReplacingFile;

  // Flutter creates local form state here.
  @override
  State<MaterialFormPage> createState() => _MaterialFormPageState();
}

// Material form state owns only safe text metadata.
class _MaterialFormPageState extends State<MaterialFormPage> {
  // One key validates title and summary.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controllers are initialized from current metadata or the selected filename.
  late final TextEditingController _titleController;
  late final TextEditingController _summaryController;

  // Create clean defaults once.
  @override
  void initState() {
    super.initState();
    final defaultTitle = widget.fileName
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
        .replaceAll('_', ' ');
    _titleController = TextEditingController(
      text: widget.existing?['title']?.toString() ?? defaultTitle,
    );
    _summaryController = TextEditingController(
      text: widget.existing?['summary']?.toString() ?? '',
    );
  }

  // Dispose every local controller.
  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  // Validate and return metadata without touching file bytes.
  void _save() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      MaterialFormValue(
        title: _titleController.text.trim(),
        summary: _summaryController.text.trim(),
      ),
    );
  }

  // Draw one quiet metadata page with the selected file clearly identified.
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return _AdminFormFrame(
      title: widget.isReplacingFile
          ? 'Replace official PDF'
          : isEditing
          ? 'Edit PDF details'
          : 'Official PDF details',
      intro: widget.isReplacingFile
          ? 'Review the details before the secure replacement starts.'
          : isEditing
          ? 'Update what Students see without replacing the PDF.'
          : 'Review the details before the secure PDF upload starts.',
      saveLabel: widget.isReplacingFile
          ? 'Continue replacement'
          : isEditing
          ? 'Save changes'
          : 'Continue upload',
      onSave: _save,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.picture_as_pdf_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Selected PDF'),
                subtitle: Text(
                  widget.fileName.split(RegExp(r'[/\\]')).last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FormSection(
              title: 'Student-facing details',
              description: 'Title is required. Summary is optional.',
              children: <Widget>[
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.title_rounded),
                    counterText: '',
                  ),
                  validator: (value) => _requiredName(value, 240),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _summaryController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Summary (optional)',
                    alignLabelWithHint: true,
                    counterText: '',
                  ),
                  validator: (value) => _optionalMaximum(value, 1000),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// _AdminFormFrame gives every full-page form the same SafeArea and bottom Save bar.
class _AdminFormFrame extends StatelessWidget {
  // The caller supplies only page text, form fields, and its Save callback.
  const _AdminFormFrame({
    required this.title,
    required this.intro,
    required this.saveLabel,
    required this.onSave,
    required this.child,
  });

  // Visible page values and callback.
  final String title;
  final String intro;
  final String saveLabel;
  final VoidCallback onSave;
  final Widget child;

  // Build a keyboard-safe scrolling page with a fixed bottom action.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(intro, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 14),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: onSave,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(saveLabel),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _FormSection visually groups related fields without a large noisy heading.
class _FormSection extends StatelessWidget {
  // A section has one short title, optional guidance, and its visible fields.
  const _FormSection({
    required this.title,
    required this.description,
    required this.children,
  });

  // Section values remain immutable.
  final String title;
  final String description;
  final List<Widget> children;

  // Draw one compact outlined card using the current light or dark theme.
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: textTheme.titleSmall),
            const SizedBox(height: 3),
            Text(description, style: textTheme.bodySmall),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

// _StatusAndOrderControls keeps the repeated lifecycle fields consistent.
class _StatusAndOrderControls extends StatelessWidget {
  // The parent owns dropdown state and the text controller.
  const _StatusAndOrderControls({
    required this.status,
    required this.orderController,
    required this.onStatusChanged,
  });

  // Current values and ordinary setState callback.
  final String status;
  final TextEditingController orderController;
  final ValueChanged<String> onStatusChanged;

  // Draw side-by-side fields on wide screens and stacked fields on phones.
  @override
  Widget build(BuildContext context) {
    return _ResponsiveFieldRow(
      first: _StatusControl(status: status, onStatusChanged: onStatusChanged),
      second: TextFormField(
        controller: orderController,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        decoration: const InputDecoration(
          labelText: 'Display order',
          prefixIcon: Icon(Icons.format_list_numbered_rounded),
        ),
        validator: _orderValidator,
      ),
    );
  }
}

// Subject forms use Status by itself; Area and Department forms pair it with
// their still-supported ordering control.
class _StatusControl extends StatelessWidget {
  const _StatusControl({required this.status, required this.onStatusChanged});

  final String status;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: status,
      decoration: const InputDecoration(
        labelText: 'Status',
        prefixIcon: Icon(Icons.visibility_outlined),
      ),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(value: 'active', child: Text('Active')),
        DropdownMenuItem<String>(value: 'inactive', child: Text('Inactive')),
      ],
      onChanged: (value) {
        if (value != null) onStatusChanged(value);
      },
    );
  }
}

// _ResponsiveFieldRow prevents two inputs from becoming cramped on narrow phones.
class _ResponsiveFieldRow extends StatelessWidget {
  // Both fields are supplied by the parent form.
  const _ResponsiveFieldRow({required this.first, required this.second});

  // The visible controls.
  final Widget first;
  final Widget second;

  // Switch between a Row and Column using only available local width.
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: <Widget>[first, const SizedBox(height: 12), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

// Return only lifecycle values accepted by the database constraint.
String _safeStatus(Object? value) {
  return value?.toString() == 'inactive' ? 'inactive' : 'active';
}

// Validate a human-readable required name with the table maximum length.
String? _requiredName(String? value, int maximum) {
  final text = value?.trim() ?? '';
  if (text.length < 2) return 'Enter at least 2 characters.';
  if (text.length > maximum) return 'Use $maximum characters or fewer.';
  return null;
}

// Validate the short required Subject code.
String? _subjectCodeValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Enter the subject code.';
  if (text.length > 30) return 'Use 30 characters or fewer.';
  return null;
}

// Validate an optional field only when the Admin has entered text.
String? _optionalMaximum(String? value, int maximum) {
  final text = value?.trim() ?? '';
  if (text.length > maximum) return 'Use $maximum characters or fewer.';
  return null;
}

// Display order must be a whole number before the database request starts.
String? _orderValidator(String? value) {
  if (int.tryParse(value?.trim() ?? '') == null) {
    return 'Enter a whole number.';
  }
  return null;
}
