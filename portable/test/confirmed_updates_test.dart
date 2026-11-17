import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/model.dart';
import 'package:onestep/backup_crypto.dart';
import 'package:onestep/planner_merge.dart';
import 'package:onestep/recurrence.dart';
import 'package:onestep/calendar_page.dart';
import 'package:onestep/cloud_sync.dart';
import 'package:onestep/family.dart';
import 'package:onestep/services.dart';

Json task(String name,{String? id})=>{'id':id??uuid.v4(),'title':name,'notes':'','createdAt':stamp(),'reminderEnabled':false};
class SyncClient extends FamilyClient {
  String? envelope;int revision=0;Future<void> Function()? beforePublish;
  @override Future<void> load()async {session={'access_token':'synthetic','user':{'id':'66666666-6666-4666-8666-666666666666'}};accountKind='normal';}
  @override Future<dynamic> rpc(String name,Json args)async {
    if(name=='onestep_sync_read')return {'revision':revision,'envelope':envelope};
    if(beforePublish!=null){final f=beforePublish;beforePublish=null;await f!();}
    if(args['expected_revision']!=revision)return {'status':'conflict','revision':revision};
    envelope=args['payload'] as String;return {'status':'saved','revision':++revision};
  }
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>FlutterSecureStorage.setMockInitialValues({}));
  test('Encrypted backup authenticates the password and all encrypted bytes',()async{
    final original=encodeTransfer(emptyState()..['tasks']=[task('Private title')]);
    final encrypted=await BackupCrypto.seal(original,'Synthetic passphrase 2026!');
    expect(encrypted.contains('Private title'),false);
    expect(await BackupCrypto.open(encrypted,'Synthetic passphrase 2026!'),original);
    await expectLater(BackupCrypto.open(encrypted,'Wrong synthetic password'),throwsFormatException);
    final altered=jsonDecode(encrypted) as Json;final bytes=base64Decode(altered['data'] as String);bytes[0]^=1;altered['data']=base64Encode(bytes);
    await expectLater(BackupCrypto.open(jsonEncode(altered),'Synthetic passphrase 2026!'),throwsFormatException);
  },timeout:const Timeout(Duration(minutes:3)));
  test('Independent edits merge and concurrent edit/delete requires an explicit choice',(){
    final a=task('Original'),b=task('Added here'),c=task('Added there');
    final base=emptyState()..['tasks']=[a];
    final local=clone(base)..['tasks']=[a,b];final remote=clone(base)..['tasks']=[a,c];
    final merged=mergePlanner(base,local,remote);expect(merged.conflicts,isEmpty);expect(rows(merged.state,'tasks').length,3);
    final deleted=clone(base)..['tasks']=[];final edited=clone(base)..['tasks']=[clone(a)..['title']='Remote edit'];
    final conflict=mergePlanner(base,deleted,edited);expect(conflict.conflicts.length,1);
    expect(rows(conflict.resolve({0:false}),'tasks'),isEmpty);
    expect(rows(conflict.resolve({0:true}),'tasks').single['title'],'Remote edit');
  });
  test('Monthly recurrence keeps the intended 31st across a short month and skips backlog',(){
    final t=task('Monthly')..addAll({'dueAt':stamp(DateTime(2027,1,31,9)),'repeatRule':'monthly','repeatMonthDay':31,'repeatAnchor':stamp(DateTime(2027,1,31,9))});
    expect(nextRepeat(t,DateTime(2027,1,31,10)),DateTime(2027,2,28,9));
    t['dueAt']=stamp(DateTime(2027,2,28,9));expect(nextRepeat(t,DateTime(2027,2,28,10)),DateTime(2027,3,31,9));
    expect(nextRepeat(t,DateTime(2030,5,15)),DateTime(2030,5,31,9));
  });
  test('Selected weekdays and multi-week intervals retain local wall time',(){
    final t=task('Monday Wednesday')..addAll({'dueAt':stamp(DateTime(2026,11,16,8,30)),'repeatRule':'weekdays','repeatEvery':2,'repeatWeekdays':[1,3]});
    expect(nextRepeat(t,DateTime(2026,11,18,9)),DateTime(2026,11,30,8,30));
    expect(validRecurrence(clone(t)..['repeatWeekdays']=[0]),false);
  });
  test('Calendar uses due dates and includes completion without duplicating unscheduled items',(){
    final state=emptyState()..['tasks']=[task('Due')..['dueAt']=stamp(DateTime(2026,11,17,23,30)),task('No date'),task('Archived')..addAll({'dueAt':stamp(DateTime(2026,11,17)),'archived':true})];
    expect(calendarTasks(state,DateTime(2026,11,17)).map((t)=>t['title']),['Due']);
    expect(calendarTasks(state,DateTime(2026,11,17),archived:true).length,2);
  });
  test('Cloud publication never overwrites a local edit made during the network request',()async{
    final dir=await Directory.systemTemp.createTemp('onestep-cloud-');addTearDown(()=>dir.delete(recursive:true));
    final p=Planner(emptyState()..['tasks']=[task('Existing')],dir,Alerts());final client=SyncClient();
    final sync=CloudPlannerSync(p,client:client);addTearDown(sync.dispose);
    client.beforePublish=()async{await p.save(clone(p.state)..['tasks']=[...rows(p.state,'tasks'),task('Arrived during sync')]);};
    await sync.enable('Synthetic sync password!');
    expect(rows(p.state,'tasks').map((t)=>t['title']),contains('Arrived during sync'));
    expect(client.revision,1);
    await sync.tick();expect(client.revision,2);
    final remote=decodeTransfer(await BackupCrypto.open(client.envelope!,'Synthetic sync password!'));
    expect(rows(remote,'tasks').map((t)=>t['title']),contains('Arrived during sync'));
  },timeout:const Timeout(Duration(minutes:3)));
}
