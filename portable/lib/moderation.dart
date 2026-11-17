import 'localization.dart';
import 'package:flutter/material.dart';
import 'family.dart';
import 'model.dart';

const moderatorCapabilities=['accounts.read','accounts.ban','points.adjust','invites.issue'];
class ModerationPage extends StatefulWidget {
  final FamilyClient? client;const ModerationPage({super.key,this.client});
  @override State<ModerationPage> createState()=>_ModerationPageState();
}
class _ModerationPageState extends State<ModerationPage>{
  late final client=widget.client??FamilyClient.shared;
  final target=TextEditingController(),reason=TextEditingController(),email=TextEditingController(),amount=TextEditingController(text:'10');
  Json status={};List<Json> users=[],audit=[];final permissions=<String>{};bool busy=false;String message='',invitation='';String? adjustmentID;String adjustmentFingerprint='';int days=7;String kind='normal';
  bool get owner=>status['owner']==true;
  bool allowed(String cap)=>owner||(status['permissions'] as List? ??[]).contains(cap);
  @override void initState(){super.initState();run(load);}
  @override void dispose(){for(final c in [target,reason,email,amount]){c.dispose();}super.dispose();}
  Future<void> run(Future<void> Function() work)async{if(busy)return;setState(()=>busy=true);try{await work();}catch(e){message='$e';}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> load()async{
    await client.load();status=Map<String,dynamic>.from(await client.rpc('onestep_moderation_status',{}) as Map);
    if(allowed('accounts.read'))users=(await client.rpc('onestep_moderation_users',{}) as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
    if(owner)audit=(await client.rpc('onestep_moderation_audit_read',{}) as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
  }
  Widget panel(String title,List<Widget> children)=>Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[LText(title,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),...children])));
  Future<bool> confirm(String action)=>showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(action),content:Text('Account: ${target.text}\nReason: ${reason.text}'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const LText('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const LText('Confirm'))])).then((v)=>v??false);
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const LText('Service administration'),actions:[IconButton(tooltip:'Refresh',onPressed:busy?null:()=>run(load),icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(20),children:[
    if(busy)const LinearProgressIndicator(),if(message.isNotEmpty)Text(message),
    Text(owner?'Owner console':'Assigned moderator permissions',style:Theme.of(context).textTheme.headlineSmall),
    const LText('Permissions are enforced by the service. Moderators cannot grant themselves rights or suspend an owner. Bans stop online service access; local offline files and Apple authorization are separate.'),
    if(!owner&&(status['permissions'] as List? ??[]).isEmpty)const LText('Owner or assigned moderator access required. Service migration 007 must be active.'),
    if(allowed('accounts.read'))panel('Accounts',[
      for(final user in users)ListTile(title:Text('${user['name']}'),subtitle:Text('${user['kind']} · ${user['banned']==true?'Suspended':'Active'}'),selected:target.text==user['id'],onTap:()=>setState((){target.text=user['id'] as String;permissions..clear()..addAll((user['permissions'] as List? ??[]).cast<String>());}),trailing:user['kind']=='owner'?const Icon(Icons.verified_user_outlined):null),
    ]),
    if(owner||(status['permissions'] as List? ??[]).isNotEmpty)TextField(controller:target,decoration:const LDecoration(labelText:'Target account UUID')),
    if(owner)panel('Moderator permissions',[
      const LText('Only the owner can grant or revoke these capabilities. Children cannot become moderators.'),
      for(final cap in moderatorCapabilities)CheckboxListTile(title:LText(cap),value:permissions.contains(cap),onChanged:busy?null:(v)=>setState((){if(v==true){permissions.add(cap);}else{permissions.remove(cap);}})),
      FilledButton(onPressed:busy?null:()=>run(()async{if(!await confirm('Save moderator permissions?'))return;await client.rpc('onestep_grant_moderator',{'target':target.text.trim(),'permissions':permissions.toList()});await load();message='Permissions saved and audited.';}),child:const LText('Save permissions')),
    ]),
    if(allowed('accounts.ban')||allowed('points.adjust'))TextField(controller:reason,decoration:const LDecoration(labelText:'Reason (required)')),
    if(allowed('accounts.ban'))panel('Suspend online access',[
      DropdownButtonFormField<int>(initialValue:days,decoration:const LDecoration(labelText:'Duration'),items:const[DropdownMenuItem(value:0,child:LText('Remove suspension')),DropdownMenuItem(value:1,child:LText('1 day')),DropdownMenuItem(value:7,child:LText('7 days')),DropdownMenuItem(value:30,child:LText('30 days')),DropdownMenuItem(value:3650,child:LText('10 years'))],onChanged:busy?null:(v)=>setState(()=>days=v??7)),
      FilledButton(onPressed:busy?null:()=>run(()async{if(!await confirm(days==0?'Restore online access?':'Suspend online access?'))return;await client.rpc('onestep_set_ban',{'target':target.text.trim(),'days':days,'explanation':reason.text.trim()});await load();message='Access change saved and audited.';}),child:const LText('Apply access change')),
    ]),
    if(allowed('points.adjust'))panel('Audited points adjustment',[
      TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(signed:true),decoration:const LDecoration(labelText:'Points (-1,000 to 1,000)')),
      FilledButton(onPressed:busy?null:()=>run(()async{if(!await confirm('Adjust virtual points?'))return;final fingerprint='${target.text}|${amount.text}|${reason.text}';if(adjustmentID==null||adjustmentFingerprint!=fingerprint){adjustmentID=uuid.v4();adjustmentFingerprint=fingerprint;}await client.rpc('onestep_moderator_adjust',{'target':target.text.trim(),'amount':int.parse(amount.text),'explanation':reason.text.trim(),'event':adjustmentID});adjustmentID=null;message='Adjustment saved. This does not award leaderboard XP.';}),child:const LText('Record adjustment')),
    ]),
    if(allowed('invites.issue'))panel('Single-use beta invitation',[
      TextField(controller:email,decoration:const LDecoration(labelText:'Bound email (optional)')),
      DropdownButtonFormField<String>(initialValue:kind,items:[for(final k in ['normal','parent','kids'])DropdownMenuItem(value:k,child:Text(k))],onChanged:busy?null:(v)=>setState(()=>kind=v??'normal')),
      FilledButton(onPressed:busy?null:()=>run(()async{invitation=await client.rpc('onestep_moderator_invite',{'account_kind':kind,'bound_email':email.text.trim()}) as String;}),child:const LText('Generate invitation')),
      if(invitation.isNotEmpty)SelectableText(invitation),const LText('Share privately. This code is not saved in analytics or planner backups.'),
    ]),
    if(owner)panel('Audit trail',[
      for(final entry in audit)ListTile(title:Text('${entry['action']}'),subtitle:Text('${entry['created_at']}\n${entry['actor']} → ${entry['target']??''}\n${entry['details']}')),
    ]),
  ]));
}
