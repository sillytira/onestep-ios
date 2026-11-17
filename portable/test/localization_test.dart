import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onestep/localization.dart';
import 'package:onestep/translations.dart';

void main(){
  tearDown(()=>AppLanguage.locale.value=null);
  test('All five requested languages have the same complete core-copy catalogue',(){
    expect(translations.keys.toSet(),{'de','uk','ru','pl','bg'});
    final keys=translations['de']!.keys.toSet();expect(keys.length,greaterThan(100));
    for(final values in translations.values){expect(values.keys.toSet(),keys);expect(values.values.every((s)=>s.trim().isNotEmpty),true);}
  });
  testWidgets('German application labels translate but private task text does not',(tester)async{
    AppLanguage.locale.value=const Locale('de');
    await tester.pumpWidget(const MaterialApp(locale:Locale('de'),supportedLocales:[Locale('en'),Locale('de')],localizationsDelegates:GlobalMaterialLocalizations.delegates,home:Scaffold(body:Column(children:[LText('Tasks'),Text('Tasks')]))));
    await tester.pumpAndSettle();expect(find.text('Aufgaben'),findsOneWidget);expect(find.text('Tasks'),findsOneWidget);
    expect(const LDecoration(labelText:'Passphrase').labelText,'Passphrase');
  });
}
