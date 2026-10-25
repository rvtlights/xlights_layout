/// Pure helpers that reproduce xLights' node/channel math for the common
/// `DisplayAs` model types found in `xlights_rgbeffects.xml`.
///
/// xLights computes node counts differently per model type. These functions
/// cover the types present in real show files (validated against fixtures);
/// anything unrecognised falls back to `NumStrings * NodesPerString`, then to
/// the sum of `LayerSizes`, then 0.
library;

/// Normalises a raw `DisplayAs` value so pre- and post-2026.04 files share one
/// set of type names. Pre-2026.04 files use variants like `Horiz Matrix`,
/// `Vert Matrix` and `Tree 180/270/360`.
String normalizeDisplayAs(String displayAs) {
  final d = displayAs.trim();
  if (d.startsWith('Tree')) return 'Tree';
  if (d.endsWith('Matrix')) return 'Matrix';
  return d;
}

/// Whether a model is a DMX fixture (`DmxMovingHead`, `DmxMovingHeadAdv`,
/// `DmxFloodlight`, `DmxServo`, `DmxSkull`, …). These don't have pixel nodes;
/// they occupy a fixed block of DMX channels given by `DmxChannelCount`.
bool isDmxModel(String displayAs) => displayAs.trim().startsWith('Dmx');

/// DMX channel footprint from `DmxChannelCount`; 0 when absent.
int _dmxChannelCount(Map<String, String> attrs) =>
    int.tryParse(attrs['DmxChannelCount']?.trim() ?? '') ?? 0;

/// Number of consecutive controller ports a model occupies when wired
/// one-string-per-port (string N lands on basePort + N-1 -- confirmed against
/// xLights' own GetPortSR/GetControllerPort logic). Mirrors the same
/// per-type string-count attribute [nodeCount] already uses, since "how many
/// strings" is the same question either way:
///   - Custom: `CustomStrings` (NOT `NumStrings` -- a Custom-specific attribute).
///   - Arches: `NumArches` / legacy `parm1`.
///   - Poly Line: `PolyStrings` / legacy `parm1`.
///   - Window Frame: always 1 -- a perimeter trace, not string-based.
///   - Everything else (Matrix, Tree, Single Line, Circle, Star, …):
///     `NumStrings` / legacy `parm1`.
///
/// [smartRemote] (from the model's `ControllerConnection SmartRemote=`,
/// 0 = none) matters only for the types newly covered here (Custom/Arches/
/// Poly Line): a model behind a Smart Remote cascades across remote letters
/// (A/B/C…) rather than consecutive physical ports, which is a different and
/// more involved calculation this helper doesn't attempt -- such models stay
/// at a span of 1 for those types. Matrix/Tree/the default case are left
/// ungated on purpose: that combination was already exercised by a real
/// Smart-Remote-plus-multi-string fixture (Train_Matrix) before this change,
/// and changing it now without re-verifying against real xLights output
/// would trade a confirmed-correct answer for an unconfirmed guess.
int portStringCount(String displayAs, Map<String, String> attrs, {int smartRemote = 0}) {
  int attrInt(String name, [int fallback = 0]) =>
      int.tryParse(attrs[name]?.trim() ?? '') ?? fallback;
  int withLegacyFallback(String named, String parm, int fallback) {
    final n = attrInt(named, -1);
    if (n >= 1) return n;
    final p = attrInt(parm, -1);
    if (p >= 1) return p;
    return fallback;
  }

  switch (normalizeDisplayAs(displayAs)) {
    case 'Window Frame':
      return 1;
    case 'Custom':
      if (smartRemote > 0) return 1;
      final n = attrInt('CustomStrings', 1);
      return n < 1 ? 1 : n;
    case 'Arches':
      if (smartRemote > 0) return 1;
      return withLegacyFallback('NumArches', 'parm1', 1);
    case 'Poly Line':
      if (smartRemote > 0) return 1;
      return withLegacyFallback('PolyStrings', 'parm1', 1);
    default:
      return withLegacyFallback('NumStrings', 'parm1', 1);
  }
}

/// Channels driven per node, derived from the model's `StringType`.
///
/// RGBW/4-channel nodes → 4, single colour → 1, otherwise RGB → 3.
int channelsPerNode(String? stringType) {
  final s = (stringType ?? '').toUpperCase();
  if (s.contains('RGBW') || s.contains('GRBW') || s.contains('WRGB')) return 4;
  if (s.contains('SINGLE')) return 1;
  return 3;
}

/// Total node count for a model, given its `DisplayAs` and raw attributes.
///
/// Handles both the post-2026.04 named attributes (`NodesPerArch`,
/// `NodesPerString`, …) and the legacy `parm1/parm2/parm3` form, falling back
/// to the legacy parm when a named attribute is absent.
int nodeCount(String displayAs, Map<String, String> attrs) {
  int attrInt(String name, [int fallback = 0]) =>
      int.tryParse(attrs[name]?.trim() ?? '') ?? fallback;

  /// Named attribute if present (>0), otherwise the legacy parm, otherwise [fallback].
  int dim(String named, String parm, [int fallback = 0]) {
    final n = attrInt(named, -1);
    if (n >= 0) return n;
    final p = attrInt(parm, -1);
    if (p >= 0) return p;
    return fallback;
  }

  // DMX fixtures occupy DmxChannelCount channels; xLights treats each DMX slot
  // as one node. Checked before PixelCount because DMX models carry a vestigial
  // PixelCount="1" that does not reflect their channel footprint.
  if (isDmxModel(displayAs)) {
    final dmx = _dmxChannelCount(attrs);
    if (dmx > 0) return dmx;
  }

  // An explicit pixel count (some Custom/Bell-style models) always wins.
  final pixelCount = attrInt('PixelCount');
  if (pixelCount > 0) return pixelCount;

  switch (normalizeDisplayAs(displayAs)) {
    case 'Arches':
      // parm1 = arches, parm2 = nodes per arch.
      return dim('NumArches', 'parm1', 1) * dim('NodesPerArch', 'parm2');
    case 'Window Frame':
      // parm1 = top, parm2 = sides (each), parm3 = bottom.
      final top = dim('TopNodes', 'parm1');
      final side = dim('SideNodes', 'parm2');
      final bottom = dim('BottomNodes', 'parm3');
      return 2 * side + top + bottom;
    case 'Custom':
      return _customNodeCount(attrs);
    case 'Poly Line':
      final strings = dim('PolyStrings', 'parm1', 1);
      return strings * dim('NodesPerString', 'parm2');
    default:
      // Strings × nodes-per-string covers Tree, Matrix, Single Line, Circle,
      // Star, etc. parm1 = strings, parm2 = nodes per string.
      final strings = dim('NumStrings', 'parm1', 1);
      final perString = dim('NodesPerString', 'parm2');
      if (perString > 0) return strings * perString;
      return _sumLayerSizes(attrs['LayerSizes']);
  }
}

/// Total channel count = nodes × channels-per-node, except DMX fixtures whose
/// footprint is one channel per DMX slot (`DmxChannelCount` directly).
int channelCount(String displayAs, Map<String, String> attrs) {
  if (isDmxModel(displayAs)) {
    final dmx = _dmxChannelCount(attrs);
    if (dmx > 0) return dmx;
  }
  return nodeCount(displayAs, attrs) * channelsPerNode(attrs['StringType']);
}

/// Custom models store geometry in `CustomModelCompressed` as
/// `"node,col,row;node,col,row;..."`. The node count is the highest node
/// index referenced. Falls back to the `CustomModel` grid if needed.
int _customNodeCount(Map<String, String> attrs) {
  final compressed = attrs['CustomModelCompressed'];
  if (compressed != null && compressed.isNotEmpty) {
    var maxNode = 0;
    for (final entry in compressed.split(';')) {
      final firstField = entry.split(',').first.trim();
      final n = int.tryParse(firstField);
      if (n != null && n > maxNode) maxNode = n;
    }
    if (maxNode > 0) return maxNode;
  }
  // Older uncompressed grid: count non-empty cells.
  final grid = attrs['CustomModel'];
  if (grid != null && grid.isNotEmpty) {
    var maxNode = 0;
    for (final cell in grid.split(RegExp('[;,|]'))) {
      final n = int.tryParse(cell.trim());
      if (n != null && n > maxNode) maxNode = n;
    }
    return maxNode;
  }
  return 0;
}

/// `LayerSizes` is a comma-separated list of per-layer node counts (Star,
/// Circle); their sum is the total node count.
int _sumLayerSizes(String? layerSizes) {
  if (layerSizes == null || layerSizes.isEmpty) return 0;
  var total = 0;
  for (final part in layerSizes.split(',')) {
    total += int.tryParse(part.trim()) ?? 0;
  }
  return total;
}
