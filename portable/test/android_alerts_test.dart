import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:onestep/model.dart';
import 'package:onestep/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;
  bool allowed = true, exact = false, revoke = false;
  Json plan(String title) => emptyState()..['preferences']={'followup':false}..['tasks']=[{
    'id':uuid.v4(), 'title':title, 'createdAt':stamp(), 'dueAt':stamp(DateTime.now().add(const Duration(hours:1))), 'reminderEnabled':true,
  }];
  setUp(() {
    debugDefaultTargetPlatformOverride=TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance=AndroidFlutterLocalNotificationsPlugin();
    calls=[]; allowed=true; exact=false; revoke=false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
      calls.add(call);
      if(call.method=='areNotificationsEnabled')return allowed;
      if(call.method=='canScheduleExactNotifications')return exact;
      if(call.method=='zonedSchedule' && revoke) { revoke=false; throw PlatformException(code:'exact_alarms_not_permitted'); }
      return true;
    });
  });
  tearDown(() {debugDefaultTargetPlatformOverride=null; TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);});
  test('Denied notifications give actionable status without scheduling',()async{
    allowed=false; final alerts=Alerts(android:true); await alerts.initialize(); await alerts.apply(plan('Walk'));
    expect(alerts.issue, contains('Notifications are off')); expect(calls.where((c)=>c.method=='zonedSchedule'),isEmpty);
  });
  test('Missing precise access schedules standard alarms without asking for it',()async{
    final alerts=Alerts(android:true); await alerts.initialize(); await alerts.apply(plan('Walk'));
    expect(alerts.scheduledCount,1); expect(alerts.exactEnabled,false);
    expect(calls.where((c)=>c.method=='requestExactAlarmsPermission'),isEmpty);
  });
  test('Exact permission revoked during scheduling falls back, keeping reminders',()async{
    exact=true; revoke=true; final alerts=Alerts(android:true); await alerts.initialize(); await alerts.apply(plan('Walk'));
    expect(calls.where((c)=>c.method=='zonedSchedule').length,2); expect(alerts.scheduledCount,1); expect(alerts.exactEnabled,false);
  });
  test('Concurrent updates finish with the newest reminder plan',()async{
    final alerts=Alerts(android:true); await alerts.initialize();
    await Future.wait([alerts.apply(plan('First')),alerts.apply(plan('Latest'))]);
    final schedule=calls.where((c)=>c.method=='zonedSchedule').toList();
    expect(schedule.map((c)=>(c.arguments as Map)['title']),['First','Latest']);
    final actions=calls.where((c)=>c.method=='cancelAll'||c.method=='zonedSchedule').map((c)=>c.method).toList();
    expect(actions,['cancelAll','zonedSchedule','cancelAll','zonedSchedule']);
  });
}
