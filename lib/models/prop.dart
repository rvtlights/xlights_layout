import 'package:xml/xml.dart';

import 'node_calc.dart' as calc;

/// Visual category for a prop, used to pick its little shape icon.
enum PropShape {
  arch,
  tree,
  matrix,
  star,
  circle,
  windowFrame,
  line,
  polyLine,
  custom,
  movingHead,
  sphere,
  cube,
  other,
}

/// How a controller output port is categorised for the report. xLights numbers
/// serial and string ports independently and treats LED/virtual panel matrices
/// as their own kind of output.
enum PortKind { string, serial, panelMatrix, generic }

/// Serial / DMX output protocols, as xLights identifies them. These ports are
/// numbered independently of pixel string ports.
const _serialProtocols = <String>{
  'dmx', 'dmx512',
  'dmx-open', 'opendmx',
  'dmx-pro',
  'lor',
  'renard',
  'genericserial',
  'pixelnet', 'pixelnet-lynx', 'pixelnet-open',
};

/// Classifies a `<ControllerConnection Protocol="…">` value into a [PortKind].
///
/// Serial protocols are matched exactly against [_serialProtocols]; panel
/// matrices by their `matrix` keyword. Everything else — the long list of pixel
/// chip protocols (ws2811, ucs512, ws2822, dmx512p, sk6812, …) — is a pixel
/// String port by default, so new chip types need no maintenance here. Note
/// xLights overloads bare `dmx512` as serial DMX (the pixel variant is
/// `dmx512p`), so it is intentionally in the serial set.
PortKind portKindFor(String protocol) {
  final p = protocol.toLowerCase().trim();
  if (p.isEmpty) return PortKind.generic;
  if (_serialProtocols.contains(p)) return PortKind.serial;
  // "LED Panel Matrix", "Virtual Matrix", … — the whole panel is one output.
  if (p.contains('matrix')) return PortKind.panelMatrix;
  return PortKind.string;
}

/// Controller ports a single smart receiver of [type] occupies, used to render
/// the "Smart Receiver 25-28A" range. Differential smart receivers (FPP/Falcon)
/// are 4-port boards — the only width seen in real files — so this is a lookup
/// with a 4-port default. Add an entry here if a type with a different port
/// count turns up.
const _smartReceiverPortCounts = <String, int>{
  // e.g. 'some_2port_type': 2,
};

int smartReceiverPortCount(String type) =>
    _smartReceiverPortCounts[type.toLowerCase()] ?? 4;

/// Port label for a prop in the Condensed report, e.g. `String Port #14`,
/// `Port #26-27B` (smart receiver), `LED Panel Matrix Port #1`, or
/// `Serial Port #2 Channel 7`.
///
/// [firstOnPort] is false for the 2nd+ prop sharing a port. The port number is
/// only emitted once per port, but a DMX/serial `Channel` is tied to each model
/// (several models share a serial bus at different channels), so it is shown on
/// every row.
String condensedPortLabel(XProp p, {bool firstOnPort = true}) {
  if (p.smartRemote > 0) {
    return firstOnPort ? 'Port #${p.portRange}${p.smartRemoteLetter}' : '';
  }
  switch (p.portKind) {
    case PortKind.serial:
      final parts = [
        if (firstOnPort) 'Serial Port #${p.port}',
        if (p.dmxChannel > 0) 'Channel ${p.dmxChannel}',
      ];
      return parts.join(' ');
    case PortKind.panelMatrix:
      return firstOnPort ? '${p.protocol} Port #${p.port}' : '';
    case PortKind.generic:
      return firstOnPort ? 'generic Port #${p.port}' : '';
    case PortKind.string:
      return firstOnPort ? 'String Port #${p.portRange}' : '';
  }
}

PropShape _shapeFor(String displayAs) {
  // DMX moving heads (DmxMovingHead, DmxMovingHeadAdv) get a fixture glyph.
  if (displayAs.contains('MovingHead')) return PropShape.movingHead;
  switch (displayAs) {
    case 'Arches':
      return PropShape.arch;
    case 'Tree':
      return PropShape.tree;
    case 'Matrix':
      return PropShape.matrix;
    case 'Star':
      return PropShape.star;
    case 'Circle':
      return PropShape.circle;
    case 'Window Frame':
      return PropShape.windowFrame;
    case 'Single Line':
      return PropShape.line;
    case 'Poly Line':
      return PropShape.polyLine;
    case 'Custom':
      return PropShape.custom;
    case 'Sphere':
      return PropShape.sphere;
    case 'Cube':
      return PropShape.cube;
    default:
      return PropShape.other;
  }
}

/// A prop/model parsed from `xlights_rgbeffects.xml` (`<model>` element).
class XProp {
  XProp({
    required this.name,
    required this.displayAs,
    required this.controllerName,
    required this.port,
    required this.protocol,
    required this.startChannel,
    required this.universe,
    required this.modelChain,
    required this.nodeCount,
    required this.channelCount,
    required this.portSpan,
    required this.smartRemote,
    required this.smartRemoteType,
    required this.dmxChannel,
    required this.element,
  });

  final String name;
  final String displayAs;

  /// Controller name as referenced by the model's `Controller` attribute.
  /// Empty / `"No Controller"` means unassigned.
  final String controllerName;

  /// Output port number from `<ControllerConnection Port="…">`; 0 if unassigned.
  final int port;

  /// Connection protocol from `<ControllerConnection Protocol="…">`, e.g. `ws2811`.
  final String protocol;

  /// Controller-relative start channel (the number after `!ctrl:` or an
  /// absolute channel), as displayed in the report.
  final int startChannel;

  /// Universe number when the model uses a `#universe:channel` start channel,
  /// else 0.
  final int universe;

  /// Name of the model this one is daisy-chained after (from `ModelChain`),
  /// without the leading `>`; empty if it starts a port.
  final String modelChain;

  final int nodeCount;
  final int channelCount;

  /// Number of consecutive controller ports this model occupies. A matrix wired
  /// one-string-per-port spans `NumStrings` ports; everything else is 1.
  final int portSpan;

  /// Smart-remote index from `<ControllerConnection SmartRemote="…">`: 0 = none,
  /// 1 = A, 2 = B, … (see [smartRemoteLetter]).
  final int smartRemote;

  /// Smart receiver hardware type, e.g. `fpp_v2` (drives the port-range width).
  final String smartRemoteType;

  /// Channel within a DMX/serial universe from `<ControllerConnection channel="…">`;
  /// 0 when not a serial/DMX connection.
  final int dmxChannel;

  /// The raw `<model>` XML element, kept so a shape preview can be built
  /// on demand from its geometry attributes (parm1/parm2/parm3, CustomModel
  /// grid data, ...) without re-parsing the whole file.
  final XmlElement element;

  PropShape get shape => _shapeFor(displayAs);

  PortKind get portKind => portKindFor(protocol);

  /// Position within its preview's 2D layout canvas (xLights world units,
  /// Y-up), read lazily from [element] since only the Layout Preview tab
  /// needs it.
  double get worldPosX => double.tryParse(element.getAttribute('WorldPosX') ?? '') ?? 0;
  double get worldPosY => double.tryParse(element.getAttribute('WorldPosY') ?? '') ?? 0;

  /// Which named preview/layout this model is placed in (e.g. "Default",
  /// "Yard"). Models in different groups share no common coordinate space.
  String get layoutGroup => element.getAttribute('LayoutGroup')?.trim() ?? '';

  /// Last controller port this model occupies (`port` when [portSpan] is 1).
  int get endPort => port + portSpan - 1;

  /// `"25"` or `"26-27"` — the numeric part of the port label.
  String get portRange => portSpan > 1 ? '$port-$endPort' : '$port';

  /// Smart-remote letter (`A`–`F` …) or empty when not on a smart receiver.
  String get smartRemoteLetter =>
      smartRemote > 0 ? String.fromCharCode(0x40 + smartRemote) : '';

  bool get isAssigned =>
      controllerName.isNotEmpty &&
      controllerName != 'No Controller' &&
      port > 0;

  /// `"ws2811:Port #17"` (or `"ws2811:Port #26-27B"`) for the Detailed table.
  String get connectionLabel => port > 0
      ? '${protocol.isEmpty ? 'Port' : protocol}:Port #$portRange$smartRemoteLetter'
      : '';

  /// Whether this prop is chained onto a previous model (so the Condensed
  /// view shows it under the same port with a blank port label).
  bool get isChained => modelChain.isNotEmpty;

  factory XProp.fromXml(XmlElement e) {
    final attrs = <String, String>{
      for (final a in e.attributes) a.name.local: a.value,
    };
    String attr(String name) => attrs[name]?.trim() ?? '';

    // Normalise so pre-2026.04 variants (Horiz Matrix, Tree 360, …) collapse
    // onto the canonical type names used for shapes and node math.
    final displayAs = calc.normalizeDisplayAs(attr('DisplayAs'));

    // Controller connection child holds the physical port + protocol, plus
    // smart-remote and serial-channel details when present.
    var port = 0;
    var protocol = '';
    var smartRemote = 0;
    var smartRemoteType = '';
    var dmxChannel = 0;
    final conn = e.findElements('ControllerConnection').firstOrNull;
    if (conn != null) {
      port = int.tryParse(conn.getAttribute('Port')?.trim() ?? '') ?? 0;
      protocol = conn.getAttribute('Protocol')?.trim() ?? '';
      smartRemote = int.tryParse(conn.getAttribute('SmartRemote')?.trim() ?? '') ?? 0;
      smartRemoteType = conn.getAttribute('SmartRemoteType')?.trim() ?? '';
      dmxChannel = int.tryParse(conn.getAttribute('channel')?.trim() ?? '') ?? 0;
    }

    // A model occupies one port per physical string (confirmed against
    // xLights' own port-cascade logic, not just Matrix/Tree -- see
    // node_calc.dart's portStringCount). Panel matrices are a single output
    // regardless of string count.
    final portSpan = portKindFor(protocol) == PortKind.panelMatrix
        ? 1
        : calc.portStringCount(displayAs, attrs, smartRemote: smartRemote);

    final (startChannel, universe) = _parseStartChannel(attr('StartChannel'));

    var chain = attr('ModelChain');
    if (chain.startsWith('>')) chain = chain.substring(1).trim();

    return XProp(
      name: attr('name'),
      displayAs: displayAs,
      controllerName: attr('Controller'),
      port: port,
      protocol: protocol,
      startChannel: startChannel,
      universe: universe,
      modelChain: chain,
      nodeCount: calc.nodeCount(displayAs, attrs),
      channelCount: calc.channelCount(displayAs, attrs),
      portSpan: portSpan,
      smartRemote: smartRemote,
      smartRemoteType: smartRemoteType,
      dmxChannel: dmxChannel,
      element: e,
    );
  }
}

/// Parses an xLights `StartChannel` string into a (channel, universe) pair.
///
/// Supported forms:
///  - `!Controller:1234` → controller-relative channel 1234, universe 0
///  - `1234`             → absolute channel 1234, universe 0
///  - `#5:101`           → universe 5, channel 101
///  - `#192.168.1.5:5:101` → universe 5, channel 101 (leading IP ignored)
///  - `>Model:1`         → chained; channel 1 (best effort)
(int, int) _parseStartChannel(String raw) {
  if (raw.isEmpty) return (0, 0);

  if (raw.startsWith('#')) {
    final parts = raw.substring(1).split(':');
    // Last field is channel, the one before it is universe.
    if (parts.length >= 2) {
      final channel = int.tryParse(parts.last.trim()) ?? 0;
      final universe = int.tryParse(parts[parts.length - 2].trim()) ?? 0;
      return (channel, universe);
    }
    return (int.tryParse(parts.first.trim()) ?? 0, 0);
  }

  if (raw.startsWith('!') || raw.startsWith('>') || raw.startsWith('@')) {
    final colon = raw.lastIndexOf(':');
    if (colon >= 0) {
      return (int.tryParse(raw.substring(colon + 1).trim()) ?? 0, 0);
    }
    return (0, 0);
  }

  return (int.tryParse(raw.trim()) ?? 0, 0);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
