import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/main.dart';
import 'package:onestep/model.dart';
import 'package:onestep/services.dart';

void main(){
  testWidgets('Render Android Now and More at phone and large text sizes',(tester)async{
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize=const Size(430,960); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final icons=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')); await icons.load();
    final font=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    final fonts=FontLoader('Preview')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync()))); await fonts.load();
    final state=emptyState()..['contentAutoUpdate']=false..['tasks']=[{'id':uuid.v4(),'title':'Make a little room for your next idea','createdAt':stamp(),'notes':'Open your notebook. One small step is enough.','colorName':'violet'}];
    final p=Planner(state,Directory.systemTemp,Alerts());
    Future<void> capture(String name)async{
      final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('preview')));
      await tester.runAsync(()async{final image=await boundary.toImage(); final bytes=await image.toByteData(format:ui.ImageByteFormat.png); await Directory('../release').create(recursive:true); await File('../release/$name-preview.png').writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();});
      expect(tester.takeException(),isNull);
    }
    await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(useMaterial3:true).copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'Preview')),home:RepaintBoundary(key:const ValueKey('preview'),child:Home(initialPlanner:p,androidLayout:true))));
    await tester.pumpAndSettle(); await capture('Android-Now');
    await tester.tap(find.byType(NavigationDestination).last); await tester.pumpAndSettle(); await capture('Android-More');
    await tester.pumpWidget(const SizedBox()); await tester.pump();
  });
}
