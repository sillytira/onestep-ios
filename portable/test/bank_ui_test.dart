import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onestep/bank_ui.dart';

void main(){
  test('Bank destinations keep profile and family controls out of Home',(){
    expect(bankSectionVisible('Public profile',0),false);
    expect(bankSectionVisible('Transactions',1),true);
    expect(bankSectionVisible('Public profile',4),true);
    expect(bankSectionVisible('Offline parent authorization',2),true);
    expect(bankSectionVisible('This week: opt-in rankings',0),false);
  });
  for(final width in [320.0,1080.0]){
    testWidgets('Points overview fits width $width with large text and working actions',(tester)async{
      tester.view.physicalSize=Size(width,1000);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      var activity=false;
      await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:Scaffold(body:MediaQuery(data:MediaQueryData(size:Size(width,1000),textScaler:TextScaler.linear(1.6)),child:SingleChildScrollView(child:Padding(padding:const EdgeInsets.all(16),child:BankOverview(balance:123,name:'@member',ledger:const [],familyAccount:false,onActivity:()=>activity=true,onAccount:(){},onFamily:(){})))))));
      expect(find.text('123'),findsOneWidget);
      expect(find.textContaining('NO CASH VALUE'),findsOneWidget);
      await tester.tap(find.byTooltip('Activity'));await tester.pump();
      expect(activity,true);expect(tester.takeException(),isNull);
    });
  }
}
