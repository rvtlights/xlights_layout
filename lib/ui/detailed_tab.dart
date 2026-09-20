import 'package:flutter/material.dart';

import '../models/controller.dart';
import '../models/prop.dart';
import '../services/layout_store.dart';
import 'model_preview_dialog.dart';
import 'prop_icons.dart';

/// "Detailed" report: a controllers summary table (when a networks file is
/// loaded) above the full per-prop table.
class DetailedTab extends StatelessWidget {
  const DetailedTab({super.key, required this.store});

  final LayoutStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (store.controllers.isNotEmpty) ...[
          Row(
            children: [
              Checkbox(
                value: store.hideUnusedControllers,
                onChanged: (value) =>
                    store.hideUnusedControllers = value ?? false,
              ),
              const Text('Hide unused controllers'),
            ],
          ),
          _SectionTitle('Controllers (${store.visibleControllers.length})'),
          _ControllersTable(store.visibleControllers),
          const SizedBox(height: 24),
        ],
        _SectionTitle('Props (${store.props.length})'),
        if (store.rgbFileName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              store.rgbFileName!,
              style: theme.textTheme.bodySmall,
            ),
          ),
        _PropsTable(store.propsByName),
      ],
    );
  }
}

class _ControllersTable extends StatelessWidget {
  const _ControllersTable(this.controllers);

  final List<XControllerInfo> controllers;

  @override
  Widget build(BuildContext context) {
    return _HScroll(
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Description')),
          DataColumn(label: Text('IP (protocol)')),
          DataColumn(label: Text('Vendor')),
          DataColumn(label: Text('Model (Variant)')),
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Universes'), numeric: true),
          DataColumn(label: Text('Channels'), numeric: true),
        ],
        rows: [
          for (final c in controllers)
            DataRow(cells: [
              DataCell(Text(c.name)),
              DataCell(Text(c.description)),
              DataCell(Text(c.ipProtocol)),
              DataCell(Text(c.vendor)),
              DataCell(Text(c.modelVariant)),
              DataCell(Text(c.id)),
              DataCell(Text(c.universes > 0 ? '${c.universes}' : '')),
              DataCell(Text(c.channels > 0 ? '${c.channels}' : '')),
            ]),
        ],
      ),
    );
  }
}

class _PropsTable extends StatelessWidget {
  const _PropsTable(this.props);

  final List<XProp> props;

  @override
  Widget build(BuildContext context) {
    return _HScroll(
      child: DataTable(
        showCheckboxColumn: false,
        headingRowHeight: 38,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        columns: const [
          DataColumn(label: Text('')),
          DataColumn(label: Text('Prop Name')),
          DataColumn(label: Text('Node Count'), numeric: true),
          DataColumn(label: Text('Channel Count'), numeric: true),
          DataColumn(label: Text('Controller')),
          DataColumn(label: Text('Universe'), numeric: true),
          DataColumn(label: Text('Start Channel'), numeric: true),
          DataColumn(label: Text('Controller Connection')),
        ],
        rows: [
          for (final p in props)
            DataRow(
              onSelectChanged: (_) => showModelPreview(context, p),
              cells: [
                DataCell(PropShapeIcon(p.shape)),
                DataCell(Text(p.name)),
                DataCell(Text(p.nodeCount > 0 ? '${p.nodeCount}' : '')),
                DataCell(Text(p.channelCount > 0 ? '${p.channelCount}' : '')),
                DataCell(Text(p.controllerName == 'No Controller' ? '' : p.controllerName)),
                DataCell(Text(p.universe > 0 ? '${p.universe}' : '')),
                DataCell(Text(p.startChannel > 0 ? '${p.startChannel}' : '')),
                DataCell(Text(p.connectionLabel)),
              ],
            ),
        ],
      ),
    );
  }
}

/// Horizontal scroll wrapper so wide tables stay usable on narrow windows.
class _HScroll extends StatelessWidget {
  const _HScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
