import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlights_layout/models/prop.dart';
import 'package:xlights_layout/services/layout_map.dart';
import 'package:xlights_layout/services/layout_store.dart';
import 'package:xlights_layout/services/xlights_parser.dart';
import 'package:xlights_layout/ui/condensed_tab.dart';
import 'package:xlights_layout/ui/controller_map.dart';

void main() {
  final networksXml = File('test/fixtures/xlights_networks.xml').readAsStringSync();
  final rgbXml = File('test/fixtures/xlights_rgbeffects.xml').readAsStringSync();

  testWidgets(
    'Controller Wiring tab renders a map per controller and syncs selection with the port list',
    (tester) async {
      final store = LayoutStore();
      store.loadRgbEffects(utf8.encode(rgbXml), 'xlights_rgbeffects.xml');
      store.loadNetworks(utf8.encode(networksXml), 'xlights_networks.xml');

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CondensedTab(store: store)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ControllerMapView), findsWidgets);

      // Arch1 is a real fixture prop wired to controller "Tree" on String Port
      // 17, several groups down the list -- ListView only builds what's near
      // the viewport, so scroll it into view first.
      final archRow = find.text('Arch1');
      await tester.scrollUntilVisible(archRow, 500.0, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(archRow, findsOneWidget);

      await tester.tap(archRow);
      await tester.pumpAndSettle();

      final afterTap = tester.widgetList<ControllerMapView>(find.byType(ControllerMapView));
      final selectedSomewhere = afterTap.any((m) => m.selected?.name == 'Arch1');
      expect(
        selectedSomewhere,
        isTrue,
        reason: 'Tapping the Arch1 row should select it and the selection should reach its controller map',
      );

      // Tapping the same row again should toggle the selection back off.
      await tester.tap(find.text('Arch1'));
      await tester.pumpAndSettle();
      final afterSecondTap = tester.widgetList<ControllerMapView>(find.byType(ControllerMapView));
      expect(afterSecondTap.every((m) => m.selected == null), isTrue);
    },
  );

  testWidgets('ControllerMapView selects the tapped prop directly on its dot cloud', (tester) async {
    // Two Single Line models far apart so their canvas regions can't overlap.
    const xml = '''
<xrgb>
  <models>
    <model name="LineA" DisplayAs="Single Line" Controller="C1"
           WorldPosX="0" WorldPosY="0" X2="100" Y2="0"
           parm1="1" parm2="10">
      <ControllerConnection Port="1" Protocol="ws2811"/>
    </model>
    <model name="LineB" DisplayAs="Single Line" Controller="C1"
           WorldPosX="1000" WorldPosY="1000" X2="100" Y2="0"
           parm1="1" parm2="10">
      <ControllerConnection Port="2" Protocol="ws2811"/>
    </model>
  </models>
</xrgb>
''';
    final props = XLightsParser.parseModels(xml);
    expect(props.length, 2);

    XProp? selected;
    final map = buildLayoutMap(props);
    final lineA = map.placed.firstWhere((g) => g.prop.name == 'LineA');
    final tapCanvasPoint = Offset((lineA.canvasLeft + lineA.canvasRight) / 2, (lineA.canvasTop + lineA.canvasBottom) / 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 500,
            child: ControllerMapView(
              props: props,
              selected: selected,
              onSelect: (p) => selected = p,
              height: 500,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ControllerMapView fits+centers the map inside its box; recompute that
    // same fit transform here so the tap lands on LineA's actual dots rather
    // than guessing a screen coordinate.
    final box = tester.getSize(find.byType(ControllerMapView));
    final scaleX = box.width / map.canvasWidth;
    final scaleY = box.height / map.canvasHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (box.width - map.canvasWidth * scale) / 2;
    final offsetY = (box.height - map.canvasHeight * scale) / 2;
    final widgetTopLeft = tester.getTopLeft(find.byType(ControllerMapView));
    final tapAt = widgetTopLeft +
        Offset(offsetX + tapCanvasPoint.dx * scale, offsetY + tapCanvasPoint.dy * scale);

    await tester.tapAt(tapAt);
    await tester.pumpAndSettle();

    expect(selected?.name, 'LineA', reason: 'Tapping LineA\'s dot cloud in the map should select it');
  });
}
