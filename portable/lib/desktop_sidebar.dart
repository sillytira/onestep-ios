import 'package:flutter/material.dart';

class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({super.key,required this.selected,required this.names,required this.icons,required this.onSelect,required this.onAdd,required this.onBank,required this.onSettings,required this.expanded});
  final int selected;
  final List<String> names;
  final List<IconData> icons;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd,onBank,onSettings;
  final bool expanded;
  @override Widget build(BuildContext context)=>Container(
    width:expanded?232:84,
    decoration:const BoxDecoration(color:Color(0xff13141b),border:Border(right:BorderSide(color:Color(0xff262832)))),
    child:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.symmetric(vertical:28,horizontal:18),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        Container(padding:const EdgeInsets.all(9),decoration:BoxDecoration(color:const Color(0xffa49aff),borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.auto_awesome_rounded,color:Color(0xff19142d))),
        if(expanded)...[const SizedBox(width:12),const Expanded(child:Text('OneStep',style:TextStyle(fontSize:23,fontWeight:FontWeight.w700,letterSpacing:-.6)))],
      ])),
      Padding(padding:EdgeInsets.symmetric(horizontal:expanded?16:12),child:expanded?FilledButton.icon(onPressed:onAdd,icon:const Icon(Icons.add),label:const Text('Add a task'),style:FilledButton.styleFrom(minimumSize:const Size(double.infinity,48))):IconButton.filled(onPressed:onAdd,tooltip:'Add a task',icon:const Icon(Icons.add))),
      const SizedBox(height:26),
      for(var i=0;i<names.length;i++) _item(icons[i],names[i],()=>onSelect(i),selected==i),
      const Spacer(),
      _item(Icons.account_balance_wallet_outlined,'OneStep Bank',onBank,false),
      _item(Icons.settings_outlined,'Settings',onSettings,false),
      if(expanded) const Padding(padding:EdgeInsets.fromLTRB(24,20,24,24),child:Text('A little progress is still progress.',style:TextStyle(color:Color(0xff9194a6),fontSize:12))),
      const SizedBox(height:12),
    ])));
  Widget _item(IconData icon,String label,VoidCallback action,bool active)=>Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:3),child:Tooltip(message:expanded?'':label,child:Material(color:active?const Color(0xff292640):Colors.transparent,borderRadius:BorderRadius.circular(12),child:InkWell(onTap:action,borderRadius:BorderRadius.circular(12),child:Padding(padding:EdgeInsets.symmetric(horizontal:expanded?14:10,vertical:14),child:Row(mainAxisAlignment:expanded?MainAxisAlignment.start:MainAxisAlignment.center,children:[Icon(icon,color:active?const Color(0xffc5baff):const Color(0xffa5a9bc)),if(expanded)...[const SizedBox(width:12),Expanded(child:Text(label,style:TextStyle(color:active?Colors.white:const Color(0xffc3c6d3),fontWeight:active?FontWeight.w600:FontWeight.w400)))]]))))));
}
