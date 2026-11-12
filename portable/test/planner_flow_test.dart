import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/main.dart';
import 'package:onestep/model.dart';
import 'package:onestep/services.dart';

void main(){
  testWidgets('Desktop add, save, complete and reopen preserve a task',(tester)async{
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize=const Size(1280,900);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final dir=Directory.systemTemp.createTempSync('onestep-flow-');
    addTearDown(()=>dir.delete(recursive:true));
    final initial=emptyState()..['contentAutoUpdate']=false;
    final planner=Planner(initial,dir,Alerts());
    await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(useMaterial3:true),home:Home(initialPlanner:planner)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a task'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,'One thing to remember'),'Walk outside');
    await tester.runAsync(() async {
      await tester.tap(find.descendant(of:find.byType(AppBar).last,matching:find.text('Save')));
      await Future<void>.delayed(const Duration(milliseconds:200));
    });
    await tester.pumpAndSettle();
    expect(rows(planner.state,'tasks').single['title'],'Walk outside');
    final restored=decodeTransfer(File('${dir.path}/planner.json').readAsStringSync());
    expect(rows(restored,'tasks').single['title'],'Walk outside');
    await tester.runAsync(() async {
      await tester.tap(find.text('Done').first);
      await Future<void>.delayed(const Duration(milliseconds:200));
    });
    await tester.pumpAndSettle();
    expect(rows(planner.state,'tasks').single['completedAt'],isNotNull);
    final reopened=decodeTransfer(File('${dir.path}/planner.json').readAsStringSync());
    expect(rows(reopened,'tasks').single['completedAt'],isNotNull);
    await tester.pumpWidget(const SizedBox());await tester.pump();
    expect(tester.takeException(),isNull);
  });
}
