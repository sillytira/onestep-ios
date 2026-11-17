import Foundation

struct PlannerConflict {
    let collection: String, key: String
    let local: Any?, remote: Any?
    var label: String { (local as? [String:Any])?["title"] as? String ?? (remote as? [String:Any])?["title"] as? String ?? collection }
}
struct PlannerMergeResult {
    var state: [String:Any]
    var conflicts: [PlannerConflict]
    func resolved(_ choices: [Int:Bool]) throws -> [String:Any] {
        guard choices.count == conflicts.count, conflicts.indices.allSatisfy({ choices[$0] != nil }) else { throw TransferError.invalid }
        var output = state
        for (i,c) in conflicts.enumerated() {
            let value = choices[i] == true ? c.remote:c.local
            if PlannerMerge.lists.contains(c.collection) {
                var rows = (output[c.collection] as? [[String:Any]] ?? []).filter { PlannerMerge.id(c.collection,$0) != c.key }
                if let row = value as? [String:Any] { rows.append(row) }; output[c.collection] = rows
            } else { output[c.key] = value }
        }
        return output
    }
}
enum PlannerMerge {
    static let lists = ["tasks","routines","days","notes","xpCompletions"]
    static func shared(_ state: [String:Any]) -> [String:Any] {
        var s = state; s.removeValue(forKey:"focusSession"); s.removeValue(forKey:"contentAutoUpdate")
        for key in lists { s[key] = s[key] as? [[String:Any]] ?? [] }
        func normalize(_ value: Any) -> Any {
            if let map = value as? [String:Any] { return Dictionary(uniqueKeysWithValues:map.map { key,value -> (String,Any) in
                if ["id","stepID","sourceID","repeatParentID","accountID","rewardAccountID"].contains(key), let string = value as? String { return (key,string.lowercased()) }
                return (key,normalize(value))
            }) }
            if let array = value as? [Any] { return array.map { normalize($0) } }
            return value
        }
        return normalize(s) as! [String:Any]
    }
    static func id(_ collection: String, _ row: [String:Any]) -> String {
        if collection == "days" { return "\(row["stepID"] ?? "").\(row["day"] ?? "")".lowercased() }
        if collection == "xpCompletions" { return "\(row["accountID"] ?? "").\(row["eventKey"] ?? "")".lowercased() }
        return (row["id"] as? String ?? "").lowercased()
    }
    static func equal(_ a: Any?, _ b: Any?) -> Bool {
        let x = try? JSONSerialization.data(withJSONObject:a ?? NSNull(),options:[.sortedKeys,.fragmentsAllowed])
        let y = try? JSONSerialization.data(withJSONObject:b ?? NSNull(),options:[.sortedKeys,.fragmentsAllowed])
        return x == y
    }
    static func merge(base: [String:Any], local: [String:Any], remote: [String:Any]) -> PlannerMergeResult {
        let b = shared(base), l = shared(local), r = shared(remote)
        var result = l, conflicts: [PlannerConflict] = []
        func choose(_ collection: String,_ key: String,_ old: Any?,_ here: Any?,_ there: Any?) -> Any? {
            if equal(here,there) || equal(there,old) { return here }
            if equal(here,old) { return there }
            conflicts.append(PlannerConflict(collection:collection,key:key,local:here,remote:there)); return here
        }
        for collection in lists {
            func keyed(_ s: [String:Any]) -> [String:[String:Any]] { Dictionary((s[collection] as? [[String:Any]] ?? []).map { (id(collection,$0),$0) }, uniquingKeysWith: { first,_ in first }) }
            let old = keyed(b), here = keyed(l), there = keyed(r)
            result[collection] = Set(old.keys).union(here.keys).union(there.keys).sorted().compactMap { key -> Any? in
                if collection == "xpCompletions", here[key] == nil || there[key] == nil { return here[key] ?? there[key] }
                return choose(collection,key,old[key],here[key],there[key])
            }
        }
        for key in Set(b.keys).union(l.keys).union(r.keys) where !lists.contains(key) { result[key] = choose("settings",key,b[key],l[key],r[key]) }
        return PlannerMergeResult(state:result,conflicts:conflicts)
    }
}
