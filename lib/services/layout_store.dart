import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/controller.dart';
import '../models/prop.dart';
import 'xlights_parser.dart';

/// Props wired to one smart receiver (a single A–F remote on a controller).
class SmartReceiver {
  SmartReceiver(this.remote);

  /// 1 = A, 2 = B, … (matches [XProp.smartRemote]).
  final int remote;

  /// Port number → props on that port (chained props share a port).
  final Map<int, List<XProp>> ports = {};

  String get letter => String.fromCharCode(0x40 + remote);

  Iterable<int> get sortedPorts => ports.keys.toList()..sort();
}

/// One controller plus the props wired to it. Non-smart-remote ports are split
/// by [PortKind] (string / panel matrix / serial); smart-remote ports are
/// grouped into [receivers] keyed by remote letter.
class ControllerGroup {
  ControllerGroup(this.name);

  final String name;

  /// Regular pixel string ports: port number → props (chained props share one).
  final Map<int, List<XProp>> stringPorts = {};

  /// LED/virtual panel-matrix ports.
  final Map<int, List<XProp>> panelPorts = {};

  /// Serial / DMX ports.
  final Map<int, List<XProp>> serialPorts = {};

  /// Smart receivers keyed by remote index (1 = A …).
  final Map<int, SmartReceiver> receivers = {};

  /// Props that reference this controller but have no port assigned.
  final List<XProp> unported = [];

  bool get isEmpty =>
      stringPorts.isEmpty &&
      panelPorts.isEmpty &&
      serialPorts.isEmpty &&
      receivers.isEmpty &&
      unported.isEmpty;

  /// Every prop wired to this controller, across all port kinds -- the input
  /// [buildLayoutMap] needs to draw just this controller's cross-section of
  /// the layout (see ControllerMapView in controller_map.dart).
  List<XProp> get allProps => [
        for (final list in stringPorts.values) ...list,
        for (final r in receivers.values) for (final list in r.ports.values) ...list,
        for (final list in panelPorts.values) ...list,
        for (final list in serialPorts.values) ...list,
        ...unported,
      ];

  Iterable<SmartReceiver> get sortedReceivers =>
      receivers.values.toList()..sort((a, b) => a.remote.compareTo(b.remote));

  /// Lowest controller port used by any smart receiver on this controller, or
  /// null when there are none. Smart receivers cascade on the same physical
  /// ports, so all letters share one port range.
  int? get _smartBankStart {
    int? min;
    for (final r in receivers.values) {
      for (final p in r.ports.keys) {
        if (min == null || p < min) min = p;
      }
    }
    return min;
  }

  /// Smart receiver hardware type seen on this controller (e.g. `fpp_v2`), or
  /// empty when unknown.
  String get smartReceiverType => receivers.values
      .expand((rc) => rc.ports.values)
      .expand((l) => l)
      .map((p) => p.smartRemoteType)
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');

  /// Header label for a smart receiver, e.g. `Smart Receiver 25-28A (fpp_v2)`.
  String smartReceiverLabel(SmartReceiver r) {
    final start = _smartBankStart;
    if (start == null) return 'Smart Receiver ${r.letter}';
    final type = smartReceiverType;
    final end = start + smartReceiverPortCount(type) - 1;
    final suffix = type.isEmpty ? '' : ' ($type)';
    return 'Smart Receiver $start-$end${r.letter}$suffix';
  }

  static Iterable<int> sortedKeys(Map<int, List<XProp>> m) =>
      m.keys.toList()..sort();
}

/// Central state holder for the loaded xLights files.
class LayoutStore extends ChangeNotifier {
  List<XControllerInfo> _controllers = [];
  List<XProp> _props = [];
  String? _rgbFileName;
  String? _networksFileName;
  String? _error;
  bool _hideUnassigned = false;
  bool _hideUnusedControllers = false;

  List<XControllerInfo> get controllers => _controllers;
  List<XProp> get props => _props;
  String? get rgbFileName => _rgbFileName;
  String? get networksFileName => _networksFileName;
  String? get error => _error;

  /// Whether the Controller Wiring view (and its PDF export) hides the "not
  /// assigned" section of generic/unwired models.
  bool get hideUnassigned => _hideUnassigned;

  set hideUnassigned(bool value) {
    if (_hideUnassigned == value) return;
    _hideUnassigned = value;
    notifyListeners();
  }

  /// Whether the Layout view (and its PDF export) hides controllers that have
  /// no models assigned.
  bool get hideUnusedControllers => _hideUnusedControllers;

  set hideUnusedControllers(bool value) {
    if (_hideUnusedControllers == value) return;
    _hideUnusedControllers = value;
    notifyListeners();
  }

  /// Controllers to list in the Layout view, honoring [hideUnusedControllers].
  List<XControllerInfo> get visibleControllers {
    if (!_hideUnusedControllers) return _controllers;
    final used = {for (final p in _props) p.controllerName};
    return [
      for (final c in _controllers)
        if (used.contains(c.name)) c,
    ];
  }

  /// True once the required rgbeffects file has been loaded.
  bool get hasData => _props.isNotEmpty;

  /// Loads `xlights_rgbeffects.xml` (required) from raw bytes.
  void loadRgbEffects(List<int> bytes, String fileName) {
    try {
      _props = XLightsParser.parseModels(utf8.decode(bytes));
      _rgbFileName = fileName;
      _error = null;
    } catch (e) {
      _error = 'Could not parse $fileName: $e';
    }
    notifyListeners();
  }

  /// Loads `xlights_networks.xml` (optional) from raw bytes.
  void loadNetworks(List<int> bytes, String fileName) {
    try {
      _controllers = XLightsParser.parseNetworks(utf8.decode(bytes));
      _networksFileName = fileName;
      _error = null;
    } catch (e) {
      _error = 'Could not parse $fileName: $e';
    }
    notifyListeners();
  }

  /// Clears everything ("Start Over").
  void clear() {
    _controllers = [];
    _props = [];
    _rgbFileName = null;
    _networksFileName = null;
    _error = null;
    notifyListeners();
  }

  /// Props sorted by name for the Detailed table.
  List<XProp> get propsByName {
    final list = [..._props];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Builds the Condensed view structure: controller → port → props.
  ///
  /// Controllers are ordered to match the networks file when available, with
  /// any controllers referenced only by props appended after. The "not
  /// assigned" bucket (no controller / no port) is returned separately so the
  /// UI can render it first.
  ({List<ControllerGroup> groups, List<XProp> notAssigned}) get grouped {
    final groups = <String, ControllerGroup>{};
    final notAssigned = <XProp>[];

    // Seed group order from the networks file first.
    for (final c in _controllers) {
      groups[c.name] = ControllerGroup(c.name);
    }

    for (final p in _props) {
      final controller = p.controllerName;
      if (controller.isEmpty || controller == 'No Controller') {
        notAssigned.add(p);
        continue;
      }
      final group = groups.putIfAbsent(controller, () => ControllerGroup(controller));
      if (p.port <= 0) {
        group.unported.add(p);
      } else if (p.smartRemote > 0) {
        group.receivers
            .putIfAbsent(p.smartRemote, () => SmartReceiver(p.smartRemote))
            .ports
            .putIfAbsent(p.port, () => [])
            .add(p);
      } else {
        final bucket = switch (p.portKind) {
          PortKind.serial => group.serialPorts,
          PortKind.panelMatrix => group.panelPorts,
          PortKind.string || PortKind.generic => group.stringPorts,
        };
        bucket.putIfAbsent(p.port, () => []).add(p);
      }
    }

    // Sort props within each port by start channel (chain order).
    for (final g in groups.values) {
      final lists = [
        ...g.stringPorts.values,
        ...g.panelPorts.values,
        ...g.serialPorts.values,
        for (final r in g.receivers.values) ...r.ports.values,
      ];
      for (final list in lists) {
        list.sort((a, b) => a.startChannel.compareTo(b.startChannel));
      }
    }

    // Drop controllers that ended up with no props at all.
    final nonEmpty = groups.values.where((g) => !g.isEmpty).toList();

    return (groups: nonEmpty, notAssigned: notAssigned);
  }
}
