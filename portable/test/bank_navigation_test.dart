import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/family.dart';

class OfflineClient extends FamilyClient {
  @override Future<dynamic> request(String path,{Map<String,dynamic>? body,bool authenticated=true}) async {
    throw const FormatException('Simulated service outage');
  }
}

void main(){
  testWidgets('Cached account remains usable when service fails; destinations expose real controls',(tester)async{
    const user='synthetic-user';
    FlutterSecureStorage.setMockInitialValues({
      'family.session':jsonEncode({'access_token':'synthetic-access','expires_at':4102444800,'user':{'id':user,'email':'test@example.invalid'}}),
      'family.kind':'normal',
      'family.snapshot.$user':jsonEncode({'balance':123,'ledger':[{'event_id':'test-event','delta':12,'reason':'A completed task','created_at':'2026-11-12T12:00:00Z'}],'tasks':[],'children':[],'families':[],'rankings':[],'publicName':'Member','handle':'member','optIn':false,'lastSync':'Saved earlier'})
    });
    await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(useMaterial3:true),home:RewardsPage(client:OfflineClient())));
    await tester.pumpAndSettle();
    expect(find.text('123'),findsOneWidget);
    await tester.tap(find.byType(NavigationDestination).at(1));await tester.pumpAndSettle();
    expect(find.text('Transactions'),findsOneWidget);
    expect(find.text('A completed task'),findsOneWidget);
    await tester.tap(find.byType(NavigationDestination).last);await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save public profile'),200,scrollable:find.byType(Scrollable).first);
    expect(find.text('Save public profile'),findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign out of this device'),200,scrollable:find.byType(Scrollable).first);
    expect(find.text('Sign out of this device'),findsOneWidget);
    expect(find.text('Transactions'),findsNothing);
    await tester.pumpWidget(const SizedBox());await tester.pump();
    expect(tester.takeException(),isNull);
  });
}
