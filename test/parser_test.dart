import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlights_layout/models/node_calc.dart';
import 'package:xlights_layout/models/prop.dart';
import 'package:xlights_layout/services/layout_store.dart';
import 'package:xlights_layout/services/xlights_parser.dart';

void main() {
  final networksXml = File('test/fixtures/xlights_networks.xml').readAsStringSync();
  final rgbXml = File('test/fixtures/xlights_rgbeffects.xml').readAsStringSync();

  group('parseNetworks', () {
    final controllers = XLightsParser.parseNetworks(networksXml);

    test('parses all named controllers', () {
      expect(controllers.length, 9);
    });

    test('House Left has the right vendor/model/channels', () {
      final hl = controllers.firstWhere((c) => c.name == 'House Left');
      expect(hl.vendor, 'ScottNation');
      expect(hl.modelVariant, 'PB16 (Expansion)');
      expect(hl.ipProtocol, '192.168.1.205 (DDP)');
      expect(hl.channels, 7176);
      expect(hl.id, '64003');
    });
  });

  group('parseModels node/channel math', () {
    final props = XLightsParser.parseModels(rgbXml);
    XProp byName(String n) => props.firstWhere((p) => p.name == n);

    test('skips model groups and gridlines', () {
      expect(props.any((p) => p.displayAs == 'ModelGroup'), isFalse);
      expect(props.any((p) => p.displayAs == 'Gridlines'), isFalse);
    });

    test('Arches: NumArches * NodesPerArch', () {
      final arch1 = byName('Arch1');
      expect(arch1.nodeCount, 25);
      expect(arch1.channelCount, 75);
      expect(arch1.controllerName, 'Tree');
      expect(arch1.port, 17);
      expect(arch1.protocol, 'ws2811');
      expect(arch1.connectionLabel, 'ws2811:Port #17');
    });

    test('Single Line: Big Lights = 7 nodes / 21 channels', () {
      final big = byName('Big Lights');
      expect(big.nodeCount, 7);
      expect(big.channelCount, 21);
    });

    test('Custom: Bell PixelCount = 109', () {
      expect(byName('Bell').nodeCount, 109);
    });

    test('Custom: BabyBack_Left = 200 nodes (compressed max index)', () {
      expect(byName('BabyBack_Left').nodeCount, 200);
    });

    test('Window Frame: 2*Side + Top + Bottom', () {
      // Front Door WF: SideNodes=21, TopNodes=9, BottomNodes=0 -> 51
      expect(byName('Front Door WF').nodeCount, 51);
    });

    test('Tree: NumStrings * NodesPerString', () {
      expect(byName('PixelTree').nodeCount, 16 * 200);
      expect(byName('BigTree1').nodeCount, 136);
    });

    test('Matrix: NumStrings * NodesPerString', () {
      expect(byName('Matrix').nodeCount, 192 * 192);
    });

    test('Circle: Wreath = 72 nodes', () {
      expect(byName('Wreath').nodeCount, 72);
    });

    test('chained model exposes its ModelChain target', () {
      expect(byName('Arch1').modelChain, 'Arch2');
      expect(byName('Arch1').isChained, isTrue);
      expect(byName('Arch2').isChained, isFalse);
    });

    test('unassigned model (No Controller) is not assigned', () {
      final star = byName('OldStar');
      expect(star.controllerName, 'No Controller');
      expect(star.isAssigned, isFalse);
    });
  });

  group('LayoutStore grouping (Condensed view)', () {
    final store = LayoutStore()
      ..loadNetworks(networksXml.codeUnits, 'xlights_networks.xml')
      ..loadRgbEffects(rgbXml.codeUnits, 'xlights_rgbeffects.xml');
    final data = store.grouped;

    test('Arch1 lands under Tree -> String Port 17', () {
      final tree = data.groups.firstWhere((g) => g.name == 'Tree');
      expect(tree.stringPorts[17]!.any((p) => p.name == 'Arch1'), isTrue);
    });

    test('unassigned props captured separately', () {
      expect(data.notAssigned.any((p) => p.name == 'OldStar'), isTrue);
    });

    test('props on a port are sorted by start channel', () {
      for (final g in data.groups) {
        final lists = [
          ...g.stringPorts.values,
          ...g.panelPorts.values,
          ...g.serialPorts.values,
          for (final r in g.receivers.values) ...r.ports.values,
        ];
        for (final list in lists) {
          for (var i = 1; i < list.length; i++) {
            expect(list[i].startChannel >= list[i - 1].startChannel, isTrue);
          }
        }
      }
    });
  });

  group('smart receivers, multi-port & serial', () {
    final smartXml =
        File('test/fixtures/xlights_rgbeffects_smartremote.xml').readAsStringSync();
    final props = XLightsParser.parseModels(smartXml);
    XProp byName(String n) => props.firstWhere((p) => p.name == n);

    test('SmartRemote int maps to A/B letters', () {
      expect(byName('Train_Engine').smartRemote, 1);
      expect(byName('Train_Engine').smartRemoteLetter, 'A');
      expect(byName('Train_Smoke').smartRemoteLetter, 'B');
      expect(byName('Train_Matrix').smartRemoteLetter, 'B');
      expect(byName('WalkwayLeft').smartRemote, 0);
      expect(byName('WalkwayLeft').smartRemoteLetter, '');
    });

    test('NumStrings drives port span; panel matrices stay on one port', () {
      expect(byName('Train_Matrix').portSpan, 2); // ports 26-27
      expect(byName('Train_Matrix').portRange, '26-27');
      expect(byName('TuneTo').portSpan, 1); // panel matrix, NumStrings=16 ignored
    });

    test('CustomStrings is ignored for a Custom model on a Smart Remote', () {
      // Train_Engine: CustomStrings=5, but SmartRemote=1 -- cascades across
      // remote letters rather than consecutive physical ports, which isn't
      // modeled here, so it stays at a span of 1 rather than guess.
      expect(byName('Train_Engine').smartRemote, greaterThan(0));
      expect(byName('Train_Engine').portSpan, 1);
    });

    test('serial DMX channel is parsed', () {
      expect(byName('MovingHead').portKind, PortKind.serial);
      expect(byName('MovingHead').dmxChannel, 1);
      expect(byName('MovingHead2').dmxChannel, 7);
    });

    test('DMX fixture channel count comes from DmxChannelCount', () {
      // A DMX moving head occupies DmxChannelCount channels, not PixelCount×3.
      expect(byName('MovingHead').channelCount, 6);
      expect(byName('MovingHead').nodeCount, 6);
    });

    test('condensed port labels match xLights', () {
      expect(condensedPortLabel(byName('WalkwayLeft')), 'String Port #14');
      expect(condensedPortLabel(byName('Train_Engine')), 'Port #25A');
      expect(condensedPortLabel(byName('Train_Smoke')), 'Port #25B');
      expect(condensedPortLabel(byName('Train_Matrix')), 'Port #26-27B');
      expect(condensedPortLabel(byName('MovingHead')), 'Serial Port #2 Channel 1');
      expect(condensedPortLabel(byName('TuneTo')), 'LED Panel Matrix Port #1');
    });

    test('DMX channel is tied to each model, not the shared serial port', () {
      // First model on the port shows "Serial Port #2"; the second shares the
      // port but shows only its own channel — neither hides its channel.
      final mh1 = byName('MovingHead'); // channel 1, lower start channel
      final mh2 = byName('MovingHead2'); // channel 7
      expect(condensedPortLabel(mh1, firstOnPort: true), 'Serial Port #2 Channel 1');
      expect(condensedPortLabel(mh2, firstOnPort: false), 'Channel 7');
      // A non-serial 2nd-on-port prop stays blank (pixel daisy-chain).
      expect(condensedPortLabel(byName('Train_Engine'), firstOnPort: false), '');
    });

    test('Strings drives port span on a Cube model', () {
      // Real-world case: a Cube model ("Yard Stakes") uses Strings="6" --
      // yet another distinct attribute name from NumStrings/CustomStrings --
      // and spans 6 consecutive ports from its base port.
      const xml = '''
<xrgb>
  <models>
    <model name="Yard Stakes" DisplayAs="Cube" Controller="GreenZone"
           CubeWidth="15" CubeHeight="8" CubeDepth="12" Strings="6">
      <ControllerConnection Port="7" Protocol="ws2811"/>
    </model>
  </models>
</xrgb>
''';
      final props = XLightsParser.parseModels(xml);
      final prop = props.firstWhere((p) => p.name == 'Yard Stakes');
      expect(prop.portSpan, 6);
      expect(prop.portRange, '7-12');
      expect(prop.smartRemote, 0);
    });

    test('CustomStrings drives port span on a plain (non-Smart-Remote) port', () {
      // Real-world case: a Custom model with CustomStrings="2" wired straight
      // to a port (no SmartRemote attribute at all) spans two consecutive
      // ports, same as a multi-string Matrix would.
      const xml = '''
<xrgb>
  <models>
    <model name="PPD_Boscoyo_Mini Mes_2" DisplayAs="Custom" Controller="SilverZone"
           CustomHeight="97" CustomWidth="97" CustomStrings="2"
           NodeStart1="1" NodeStart2="201">
      <ControllerConnection Port="14" Protocol="ws2811"/>
    </model>
  </models>
</xrgb>
''';
      final props = XLightsParser.parseModels(xml);
      final prop = props.firstWhere((p) => p.name == 'PPD_Boscoyo_Mini Mes_2');
      expect(prop.portSpan, 2);
      expect(prop.portRange, '14-15');
      expect(prop.smartRemote, 0);
    });

    test('legacy parm1 drives port span on a smart-remote matrix', () {
      // Pre-2026.04 files use Horiz Matrix + parm1 (string count) instead of
      // NumStrings — the multi-port span must still resolve to 26-27.
      const legacy = '<xrgb><models>'
          '<model name="Train_Matrix" DisplayAs="Horiz Matrix" parm1="2" '
          'parm2="128" Controller="House Left" StartChannel="!House Left:1">'
          '<ControllerConnection SmartRemote="2" SmartRemoteType="fpp_v2" '
          'Port="26" Protocol="ws2811"/></model></models></xrgb>';
      final m = XLightsParser.parseModels(legacy).single;
      expect(m.portSpan, 2);
      expect(condensedPortLabel(m), 'Port #26-27B');
    });

    test('grouping splits ports by kind and builds receiver banks', () {
      final store = LayoutStore()
        ..loadRgbEffects(smartXml.codeUnits, 'smart.xml');
      final hl = store.grouped.groups.firstWhere((g) => g.name == 'House Left');

      expect(hl.stringPorts.keys, contains(14));
      expect(hl.serialPorts.keys, contains(2));
      expect(hl.panelPorts, isEmpty); // TuneTo is its own controller
      expect(hl.receivers.keys, containsAll(<int>[1, 2]));

      // Receiver A spans the 4-port fpp_v2 bank starting at the lowest used port.
      final recA = hl.receivers[1]!;
      expect(hl.smartReceiverLabel(recA), 'Smart Receiver 25-28A (fpp_v2)');
      final recB = hl.receivers[2]!;
      expect(hl.smartReceiverLabel(recB), 'Smart Receiver 25-28B (fpp_v2)');
      expect(recB.ports.keys, containsAll(<int>[25, 26]));

      final tuneTo = store.grouped.groups.firstWhere((g) => g.name == 'TuneTo');
      expect(tuneTo.panelPorts.keys, contains(1));
    });
  });

  group('pre-2026.04 (legacy parm) format', () {
    final legacyXml =
        File('test/fixtures/xlights_rgbeffects_pre2026.04.xml').readAsStringSync();
    final props = XLightsParser.parseModels(legacyXml);
    XProp byName(String n) => props.firstWhere((p) => p.name == n);

    test('parses legacy models', () {
      expect(props, isNotEmpty);
      expect(props.any((p) => p.name == 'BabyBack_Left'), isTrue);
    });

    test('Arches via parm1*parm2 (DrivewayArch4 = 37)', () {
      expect(byName('DrivewayArch4').nodeCount, 37);
      expect(byName('DrivewayArch4').shape, PropShape.arch);
    });

    test('Single Line via parm1*parm2 (Ridge = 67)', () {
      expect(byName('Ridge').nodeCount, 67);
    });

    test('Window Frame via parm1/2/3 (Living Room WF = 2*15+13+13 = 56)', () {
      expect(byName('Living Room WF').nodeCount, 56);
    });

    test('Tree variant DisplayAs normalised (Glow1 "Tree 360" -> 20 nodes)', () {
      expect(byName('Glow1').nodeCount, 20);
      expect(byName('Glow1').shape, PropShape.tree);
    });

    test('Star via parm1*parm2 (PixelTreeStar = 180)', () {
      expect(byName('PixelTreeStar').nodeCount, 180);
    });

    test('Custom via CustomModel grid (BabyBack_Left = 200)', () {
      expect(byName('BabyBack_Left').nodeCount, 200);
    });

    test('Horiz Matrix normalises to Matrix shape', () {
      final matrix = props.where((p) => p.shape == PropShape.matrix);
      expect(matrix, isNotEmpty);
    });

    test('no DisplayAs leaks the legacy "Tree NNN"/"Horiz" variants', () {
      expect(props.any((p) => p.displayAs.contains('Tree 3')), isFalse);
      expect(props.any((p) => p.displayAs == 'Horiz Matrix'), isFalse);
    });
  });

  group('portKindFor', () {
    test('all xLights serial protocols classify as serial', () {
      for (final p in const [
        'dmx', 'dmx512', 'dmx-open', 'opendmx', 'dmx-pro', 'lor', 'renard',
        'genericserial', 'pixelnet', 'pixelnet-lynx', 'pixelnet-open',
        'DMX', 'Renard', // case-insensitive
      ]) {
        expect(portKindFor(p), PortKind.serial, reason: p);
      }
    });

    test('pixel, panel, and empty protocols are not serial', () {
      expect(portKindFor('ws2811'), PortKind.string);
      expect(portKindFor('LED Panel Matrix'), PortKind.panelMatrix);
      expect(portKindFor('Virtual Matrix'), PortKind.panelMatrix);
      expect(portKindFor(''), PortKind.generic);
    });

    test('pixel chip protocols default to a String port', () {
      for (final p in const [
        'sk6812', 'ucs512', 'ws2822', 'dmx512p', 'ucs512c4', 'sm16825',
        'apa102', 'gece', 'tm1814', 'ws2801',
      ]) {
        expect(portKindFor(p), PortKind.string, reason: p);
      }
    });

    test('bare dmx512 is serial, dmx512p pixel variant is a String port', () {
      expect(portKindFor('dmx512'), PortKind.serial);
      expect(portKindFor('dmx512p'), PortKind.string);
    });
  });

  group('channelsPerNode', () {
    test('RGB -> 3, RGBW -> 4, single -> 1', () {
      expect(channelsPerNode('RGB Nodes'), 3);
      expect(channelsPerNode('RGBW Nodes'), 4);
      expect(channelsPerNode('Single Color Red'), 1);
    });
  });
}
