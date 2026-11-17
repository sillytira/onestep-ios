import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'translations.dart';

class AppLanguage {
  static const codes=['en','de','uk','ru','pl','bg'];
  static final locale=ValueNotifier<Locale?>(null);
  static Future<void> load()async{try{final value=await const FlutterSecureStorage().read(key:'ui.language');if(codes.contains(value))locale.value=Locale(value!);}catch(_){/* Keep the system language when secure storage is unavailable. */}}
  static Future<void> set(String code)async{await const FlutterSecureStorage().write(key:'ui.language',value:code);locale.value=codes.contains(code)?Locale(code):null;}
}
String translate(String value,{String? language}) {
  final code=language??AppLanguage.locale.value?.languageCode??PlatformDispatcher.instance.locale.languageCode;
  return translations[code]?[value]??value;
}
class LText extends StatelessWidget {
  final String data;final TextStyle? style;final TextAlign? textAlign;final TextDirection? textDirection;final Locale? locale;
  final bool? softWrap;final TextOverflow? overflow;final int? maxLines;final String? semanticsLabel;final TextScaler? textScaler;
  final StrutStyle? strutStyle;final TextWidthBasis? textWidthBasis;final TextHeightBehavior? textHeightBehavior;
  const LText(this.data,{super.key,this.style,this.textAlign,this.textDirection,this.locale,this.softWrap,this.overflow,this.maxLines,this.semanticsLabel,this.textScaler,this.strutStyle,this.textWidthBasis,this.textHeightBehavior});
  @override Widget build(BuildContext context)=>Text(translate(data,language:Localizations.localeOf(context).languageCode),style:style,textAlign:textAlign,textDirection:textDirection,locale:locale,softWrap:softWrap,overflow:overflow,maxLines:maxLines,semanticsLabel:semanticsLabel==null?null:translate(semanticsLabel!),textScaler:textScaler,strutStyle:strutStyle,textWidthBasis:textWidthBasis??TextWidthBasis.parent,textHeightBehavior:textHeightBehavior);
}
class LDecoration extends InputDecoration {
  const LDecoration({super.labelText,super.hintText,super.prefixIcon,super.suffixIcon,super.border,super.errorText,super.helperText,super.contentPadding,super.filled,super.fillColor,super.alignLabelWithHint});
  @override String? get labelText=>super.labelText==null?null:translate(super.labelText!);
  @override String? get hintText=>super.hintText==null?null:translate(super.hintText!);
}
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const LText('Language')),body:ValueListenableBuilder<Locale?>(valueListenable:AppLanguage.locale,builder:(context,locale,_)=>ListView(padding:const EdgeInsets.all(20),children:[
    for(final entry in {'':'System language','en':'English','de':'Deutsch','uk':'Українська','ru':'Русский','pl':'Polski','bg':'Български'}.entries)
      RadioListTile<String>(title:LText(entry.value),value:entry.key,groupValue:locale?.languageCode??'',onChanged:(v)=>AppLanguage.set(v??'')),
    const Padding(padding:EdgeInsets.all(16),child:Text('Beta translations cover core planner/navigation/settings. Some detailed service messages remain in English. Your task titles, notes and other private content are never sent to a translation service.')),
  ])));
}
