import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onestep/family.dart';
import 'package:onestep/model.dart';
import 'package:onestep/session_rules.dart';

Json savedSession({String refresh = 'synthetic-old-refresh', String id = 'synthetic-child', int expiry = 1}) => {
  'access_token':'synthetic-access','refresh_token':refresh,'expires_at':expiry,
  'user':{'id':id,'email':'child@example.invalid'},
};
Json newSession({String refresh = 'synthetic-new-refresh',String id = 'synthetic-child'}) => {
  'access_token':'synthetic-new-access','refresh_token':refresh,'expires_in':3600,
  'user':{'id':id,'email':'child@example.invalid'},
};
Future<FamilyClient> fixture(Json saved, FutureOr<dynamic> Function(HttpRequest,Json) handler) async {
  final previous = HttpOverrides.current;HttpOverrides.global = null;
  addTearDown(()=>HttpOverrides.global=previous);
  FlutterSecureStorage.setMockInitialValues({
    'family.session':jsonEncode(saved),'family.kind':'kids',
    'family.childVerifier.synthetic-child':'saved-parent-verifier',
  });
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4,0);
  final serving=server.listen((r) async {
    final text=await utf8.decoder.bind(r).join();
    final body=text.isEmpty?<String,dynamic>{}:jsonDecode(text) as Json;
    final result=await handler(r,body);
    r.response.headers.contentType=ContentType.json;
    r.response.write(jsonEncode(result));await r.response.close();
  });
  addTearDown(()async{await serving.cancel();await server.close(force:true);});
  final client=FamilyClient();await client.load();
  client.project='http://127.0.0.1:${server.port}';client.publicKey='synthetic-public-key';return client;
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Incomplete authentication responses cannot replace the saved child account',()async{
    FlutterSecureStorage.setMockInitialValues({});final c=FamilyClient();
    await c.acceptSession(newSession());c.accountKind='kids';
    final before=await FamilyClient.vault.read(key:'family.session');
    for(final refresh in [null,'','   ']){
      await expectLater(c.acceptSession({...newSession(), 'refresh_token':refresh}),throwsA(isA<ReconnectRequired>()));
    }
    expect(c.userID,'synthetic-child');expect(c.accountKind,'kids');
    expect(await FamilyClient.vault.read(key:'family.session'),before);
    await expectLater(c.signOut(),throwsFormatException);
  });
  test('Legacy JWT identity and expiry are hints, with no derived account privileges',(){
    final payload=base64Url.encode(utf8.encode(jsonEncode({'sub':'synthetic-child','email':'child@example.invalid','exp':4102444800,'role':'service_role'}))).replaceAll('=','');
    final c=FamilyClient()..session={'access_token':'synthetic.$payload.synthetic'};
    expect(c.userID,'synthetic-child');expect(c.accountEmail,'child@example.invalid');
    expect(c.needsReconnect,false);expect(c.accountKind,isNull);
  });
  test('An empty refresh token never reaches the server and keeps guardian state',()async{
    var calls=0;final c=await fixture(savedSession(refresh:''),(r,b){calls++;return [];});
    await expectLater(c.list('probe'),throwsA(isA<ReconnectRequired>()));
    expect(calls,0);expect(c.needsReconnect,true);expect(c.userID,'synthetic-child');
    expect(c.accountKind,'kids');expect(await FamilyClient.vault.read(key:'family.childVerifier.synthetic-child'),'saved-parent-verifier');
    await expectLater(c.signOut(),throwsFormatException);
  });
  test('Permanent refresh rejection pauses retries and password reconnect restores the same account',()async{
    var rotations=0,protected=0;
    final c=await fixture(savedSession(),(r,b){
      if(r.uri.queryParameters['grant_type']=='refresh_token'){rotations++;r.response.statusCode=400;return {'error_description':'no refresh token','error':'invalid_grant'};}
      if(r.uri.queryParameters['grant_type']=='password'){expect(b['password'],'synthetic-password');return newSession();}
      protected++;return [];
    });
    await expectLater(c.list('probe'),throwsA(isA<ReconnectRequired>()));
    await expectLater(c.list('probe'),throwsA(isA<ReconnectRequired>()));
    expect(rotations,1);expect(protected,0);expect(c.accountKind,'kids');
    await c.signIn('child@example.invalid','synthetic-password');
    expect(c.needsReconnect,false);expect(c.userID,'synthetic-child');expect(c.accountKind,'kids');
    await c.list('probe');expect(protected,1);
    expect(await FamilyClient.vault.read(key:'family.childVerifier.synthetic-child'),'saved-parent-verifier');
    await expectLater(c.signOut(),throwsFormatException);
  });
  test('Temporary server failure retains refresh credentials and permits a later retry',()async{
    var rotations=0;final c=await fixture(savedSession(),(r,b){
      if(r.uri.queryParameters['grant_type']=='refresh_token'){
        rotations++;if(rotations==1){r.response.statusCode=503;return {'message':'Temporarily unavailable'};}return newSession();
      }return [];
    });
    await expectLater(c.list('probe'),throwsA(isA<AccountServiceFailure>()));
    expect(c.needsReconnect,false);expect(c.session!['refresh_token'],'synthetic-old-refresh');
    await c.list('probe');expect(rotations,2);expect(c.session!['refresh_token'],'synthetic-new-refresh');
  });
  test('A delayed old refresh cannot overwrite a successful password reconnect',()async{
    final started=Completer<void>(),release=Completer<void>();
    addTearDown((){if(!release.isCompleted)release.complete();});
    final c=await fixture(savedSession(),(r,b)async{
      if(r.uri.queryParameters['grant_type']=='refresh_token'){
        started.complete();await release.future;return newSession(refresh:'synthetic-stale-response');
      }
      if(r.uri.queryParameters['grant_type']=='password')return newSession(refresh:'synthetic-password-session');
      return [];
    });
    final pending=c.list('probe');await started.future;
    await c.signIn('child@example.invalid','synthetic-password');
    final rejected=expectLater(pending,throwsFormatException);release.complete();await rejected;
    expect(c.session!['refresh_token'],'synthetic-password-session');expect(c.needsReconnect,false);
    expect(jsonDecode((await FamilyClient.vault.read(key:'family.session'))!)['refresh_token'],'synthetic-password-session');
  });
  test('Recovery cannot switch a saved child to a different account or create a new account',()async{
    final c=await fixture(savedSession(refresh:''),(r,b)=>newSession(id:'another-account'));
    await expectLater(c.signIn('another@example.invalid','synthetic-password'),throwsFormatException);
    await expectLater(c.signUp('another@example.invalid','synthetic-password','synthetic-invite','another'),throwsFormatException);
    expect(c.userID,'synthetic-child');expect(c.accountKind,'kids');expect(c.needsReconnect,true);
  });
}
