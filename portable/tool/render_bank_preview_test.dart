import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onestep/bank_ui.dart';

void main(){
  testWidgets('Capture banking design with clearly labeled synthetic data',(tester)async{
    tester.view.physicalSize=const Size(430,1150);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final font=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if(font.existsSync()){
      final loader=FontLoader('OneStepPreview')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    final today=DateTime.now().toUtc().toIso8601String();
    await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(useMaterial3:true).copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'OneStepPreview')),home:RepaintBoundary(key:const ValueKey('capture'),child:Scaffold(backgroundColor:const Color(0xff090a0c),appBar:AppBar(title:const Text('OneStep Bank'),backgroundColor:const Color(0xff090a0c)),body:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(22),child:Column(children:[const Text('DESIGN PREVIEW · SAMPLE POINTS',style:TextStyle(fontSize:10,color:Colors.white54,letterSpacing:1)),BankOverview(balance:250,name:'@preview',ledger:[{'delta':25,'reason':'Morning routine','created_at':today},{'delta':-15,'reason':'15 minutes of app time','created_at':today},{'delta':10,'reason':'A completed task','created_at':today}],onActivity:(){},onAccount:(){},onFamily:(){},familyAccount:false)]))),bottomNavigationBar:NavigationBar(destinations:const[NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),label:'Home'),NavigationDestination(icon:Icon(Icons.receipt_long_outlined),label:'Activity'),NavigationDestination(icon:Icon(Icons.leaderboard_outlined),label:'Rankings'),NavigationDestination(icon:Icon(Icons.person_outline),label:'Account')])))));
    await tester.pumpAndSettle();
    final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('capture')));
    await tester.runAsync(()async{
      final image=await boundary.toImage(pixelRatio:1);
      final data=await image.toByteData(format:ui.ImageByteFormat.png);
      final dir=Directory('../release');await dir.create(recursive:true);
      await File('${dir.path}/OneStep-Bank-preview.png').writeAsBytes(data!.buffer.asUint8List());image.dispose();
    });
    expect(tester.takeException(),isNull);
  });
}
