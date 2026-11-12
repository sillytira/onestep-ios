import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/main.dart';
import 'package:onestep/model.dart';
import 'package:onestep/services.dart';

class MemoryPlanner extends Planner {
  MemoryPlanner(super.state,super.directory,super.alerts);
  @override Future<void> save(Json next) async {
    validateState(next);state=clone(next);notifyListeners();
  }
}

void main(){
  test('Real planner writes and completion survive reopening',()async{
    FlutterSecureStorage.setMockInitialValues({});
    final dir=await Directory.systemTemp.createTemp('onestep-persistence-');
    addTearDown(()=>dir.delete(recursive:true));
    final planner=Planner(emptyState(),dir,Alerts());
    final next=clone(planner.state)..['tasks']=[{'id':uuid.v4().toUpperCase(),'title':'Walk outside','notes':'','createdAt':stamp(),'reminderEnabled':false}];
    await planner.save(next);
    final loaded=decodeTransfer(await File('${dir.path}/planner.json').readAsString());
    expect(rows(loaded,'tasks').single['title'],'Walk outside');
    await planner.save(complete(loaded,action(rows(loaded,'tasks').single)));
    final reopened=decodeTransfer(await File('${dir.path}/planner.json').readAsString());
    expect(rows(reopened,'tasks').single['completedAt'],isNotNull);
  });
  testWidgets('Desktop controls add and complete a task',(tester)async{
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize=const Size(1280,900);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final dir=Directory.systemTemp.createTempSync('onestep-flow-');
    addTearDown(()=>dir.delete(recursive:true));
    final initial=emptyState()..['contentAutoUpdate']=false;
    final planner=MemoryPlanner(initial,dir,Alerts());
    await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(useMaterial3:true),home:Home(initialPlanner:planner)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a task'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,'One thing to remember'),'Walk outside');
    await tester.tap(find.descendant(of:find.byType(AppBar).last,matching:find.text('Save')));
    await tester.pumpAndSettle();
    expect(rows(planner.state,'tasks'),isNotEmpty,reason:find.byType(Text).evaluate().map((e)=>(e.widget as Text).data).join(' | '));
    expect(rows(planner.state,'tasks').single['title'],'Walk outside');
    await tester.tap(find.text('Done').first);
    await tester.pumpAndSettle();
    expect(rows(planner.state,'tasks').single['completedAt'],isNotNull);
    await tester.pumpWidget(const SizedBox());await tester.pump();
    expect(tester.takeException(),isNull);
  });
}
