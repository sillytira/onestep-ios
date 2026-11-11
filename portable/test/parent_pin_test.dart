import 'package:flutter_test/flutter_test.dart';
import 'package:onestep/parent_pin.dart';
import 'package:onestep/family.dart';

void main(){
  test('Offline parent verifier rejects a wrong code and malformed parameters',()async{
    final verifier=await ParentPin.verifier('0123456789',salt:List.generate(16,(i)=>i));
    expect(verifier['hash'],'nVox1uAswwfkowNdrWPmBt5pBK77mZIbAAxTqHkqG9U=');
    expect(await ParentPin.matches('0123456789',verifier),true);
    expect(await ParentPin.matches('9876543210',verifier),false);
    expect(await ParentPin.matches('0123456789',{...verifier,'iterations':1}),false);
    expect(ParentPin.generate(),matches(RegExp(r'^\d{10}$')));
  });
  test('A child cannot use the ordinary logout method',()async{
    final client=FamilyClient()..accountKind='kids'..session={'access_token':'synthetic-test-session'};
    await expectLater(client.signOut(),throwsA(isA<FormatException>()));
    expect(client.signedIn,true);
  });
}
