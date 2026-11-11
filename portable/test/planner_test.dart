import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onestep/model.dart';
import 'package:onestep/services.dart';

void main() {
  final now = DateTime(2026,11,11,8);
  Json task() => {'id':uuid.v4().toUpperCase(),'title':'Water','notes':'','createdAt':stamp(now),'dueAt':stamp(now.add(const Duration(hours:1))),'reminderEnabled':true,'repeatRule':'daily'};
  test('Swift date epoch and versioned interchange round trip',(){
    expect(stamp(DateTime.utc(2001)),0);
    final state=emptyState();state['tasks']=[task()];
    expect(decodeTransfer(encodeTransfer(state)),state);
    expect(()=>decodeTransfer(jsonEncode({'format':'OneStep','formatVersion':99,'state':state})),throwsFormatException);
  });
  test('Repeat advances past missed days and keeps completed history',(){
    final state=emptyState();final t=task();state['tasks']=[t];
    final next=complete(state,action(t),at:DateTime(2026,11,15,10));
    expect(rows(next,'tasks'),hasLength(2));expect(rows(next,'tasks').first['completedAt'],isNotNull);
    expect(dateOf(rows(next,'tasks').last['dueAt'])!.isAfter(DateTime(2026,11,15,10)),true);
    expect(complete(next,action(t),at:DateTime(2026,11,15,11))['tasks'],hasLength(2));
  });
  test('Routine completion cancels today, keeps history, resets tomorrow',(){
    final state=emptyState();final step={'id':uuid.v4().toUpperCase(),'title':'Water','hour':9,'minute':0,'position':0};state['routines']=[step];
    final next=complete(state,action(step,day:now,state:state),at:now);
    expect(reminders(next,now).where((r)=>dayKey(r.at)==dayKey(now)),isEmpty);
    expect(reminders(next,now).where((r)=>dayKey(r.at)==dayKey(now.add(const Duration(days:1)))),hasLength(2));
    expect(rows(next,'days'),hasLength(1));
  });
  test('Paused timer has no expiry notification and quiet hours omit alerts',(){
    final state=emptyState();final t=task();state['tasks']=[t];state['focusSession']={'id':uuid.v4(),'action':action(t),'startedAt':stamp(now),'endsAt':stamp(now.add(const Duration(minutes:15))),'durationBased':true,'pausedRemaining':300};
    state['preferences']={'snoozeMinutes':20,'followup':false,'quietStart':8,'quietEnd':10};
    expect(reminders(state,now),isEmpty);
  });
  test('Reject duplicate identities and non-private pairing endpoints',(){
    final state=emptyState();final t=task();state['tasks']=[t,t];expect(()=>decodeTransfer(encodeTransfer(state)),throwsFormatException);
    expect(privateIPv4('127.0.0.1'),false);expect(privateIPv4('8.8.8.8'),false);expect(privateIPv4('192.168.0.3'),true);expect(privateIPv4('172.32.1.2'),false);
  });
  test('AES-GCM wire format is nonce12 + ciphertext + tag16',()async{
    final key=SecretKey(List<int>.generate(32,(i)=>i));final nonce=List<int>.generate(12,(i)=>i);
    final box=await AesGcm.with256bits().encrypt(utf8.encode('OneStep transfer'),secretKey:key,nonce:nonce);
    final wire=[...box.nonce,...box.cipherText,...box.mac.bytes];
    expect(base64Encode(wire),'AAECAwQFBgcICQoLCGyzSLGAsjv5M/blwo8dH+zM+Qx4xwiOhXAxOFLt8mY=');
    final opened=await AesGcm.with256bits().decrypt(SecretBox(wire.sublist(12,wire.length-16),nonce:wire.sublist(0,12),mac:Mac(wire.sublist(wire.length-16))),secretKey:key);
    expect(utf8.decode(opened),'OneStep transfer');
    await expectLater(LanTransfer.receive('onestep-transfer://8.8.8.8:80/#${base64Encode(List.filled(32,0))}'),throwsA(isA<FormatException>()));
  });
}
