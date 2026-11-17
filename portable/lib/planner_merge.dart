import 'dart:convert';
import 'model.dart';

String canonical(dynamic value) {
  dynamic sort(dynamic v) => v is Map ? {for(final k in (v.keys.cast<String>().toList()..sort()))k:sort(v[k])} : v is List ? v.map(sort).toList() : v;
  return jsonEncode(sort(value));
}
const sharedLists=['tasks','routines','days','notes','xpCompletions'];
Json sharedPlanner(Json state) {
  final s=clone(state)..remove('focusSession')..remove('contentAutoUpdate');
  for(final key in sharedLists){s[key]=rows(s,key);}
  // UUID spelling must not produce duplicate rows between Swift and Dart.
  for(final key in sharedLists){for(final row in rows(s,key)){
    if(row['id'] is String)row['id']=(row['id'] as String).toLowerCase();
  }}
  dynamic normalize(dynamic v) {
    if(v is Map)return {for(final e in v.entries)e.key: (['id','stepID','sourceID','repeatParentID','accountID','rewardAccountID'].contains(e.key)&&e.value is String)?(e.value as String).toLowerCase():normalize(e.value)};
    if(v is List)return v.map(normalize).toList();return v;
  }
  return Map<String,dynamic>.from(normalize(s) as Map);
}
String mergeID(String collection,Json row) => collection=='days' ? '${row['stepID']}'.toLowerCase()+'.${row['day']}' : collection=='xpCompletions' ? '${row['accountID']}.${row['eventKey']}'.toLowerCase() : '${row['id']}'.toLowerCase();
class PlannerConflict {
  final String collection,key;
  final dynamic local,remote;
  PlannerConflict(this.collection,this.key,this.local,this.remote);
  String get label => local is Map ? (local['title'] ?? collection).toString() : remote is Map ? (remote['title'] ?? collection).toString() : collection;
}
class PlannerMerge {
  final Json state;
  final List<PlannerConflict> conflicts;
  PlannerMerge(this.state,this.conflicts);
  Json resolve(Map<int,bool> useRemote) {
    if(useRemote.length!=conflicts.length)throw const FormatException('Choose a version for every conflict.');
    final result=clone(state);
    for(var i=0;i<conflicts.length;i++){
      final c=conflicts[i], value=useRemote[i]==true?c.remote:c.local;
      if(sharedLists.contains(c.collection)){
        final list=rows(result,c.collection)..removeWhere((r)=>mergeID(c.collection,r)==c.key);
        if(value!=null)list.add(Map<String,dynamic>.from(value as Map));
        result[c.collection]=list;
      } else {if(value==null){result.remove(c.key);}else{result[c.key]=value;}}
    }
    validateState(result);return result;
  }
}
PlannerMerge mergePlanner(Json base,Json local,Json remote) {
  base=sharedPlanner(base);local=sharedPlanner(local);remote=sharedPlanner(remote);
  final result=clone(local),conflicts=<PlannerConflict>[];
  dynamic choose(String collection,String key,dynamic b,dynamic l,dynamic r){
    if(canonical(l)==canonical(r)||canonical(r)==canonical(b))return l;
    if(canonical(l)==canonical(b))return r;
    conflicts.add(PlannerConflict(collection,key,l,r));return l;
  }
  for(final collection in sharedLists){
    Map<String,Json> keyed(Json s)=>{for(final r in rows(s,collection))mergeID(collection,r):r};
    final b=keyed(base),l=keyed(local),r=keyed(remote);
    result[collection]=<Json>[];
    for(final id in {...b.keys,...l.keys,...r.keys}.toList()..sort()){
      final dynamic row;
      if(collection=='xpCompletions' && (l[id]==null||r[id]==null)) {row=l[id]??r[id];}else{row=choose(collection,id,b[id],l[id],r[id]);}
      if(row!=null)(result[collection] as List).add(row);
    }
  }
  for(final key in {...base.keys,...local.keys,...remote.keys}.where((k)=>!sharedLists.contains(k))){
    final value=choose('settings',key,base[key],local[key],remote[key]);
    if(value==null){result.remove(key);}else{result[key]=value;}
  }
  validateState(result);return PlannerMerge(result,conflicts);
}
