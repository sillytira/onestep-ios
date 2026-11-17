import SwiftUI

enum L10n {
    static func text(_ key: String) -> String {
        let language = UserDefaults.standard.string(forKey:"uiLanguage") ?? ""
        guard !language.isEmpty,let path = Bundle.main.path(forResource:language,ofType:"lproj"),let bundle = Bundle(path:path) else { return NSLocalizedString(key,comment:"") }
        return bundle.localizedString(forKey:key,value:key,table:nil)
    }
}
struct LanguageView: View {
    @AppStorage("uiLanguage") private var language = ""
    var body: some View {
        Form {
            Picker("Language",selection:$language) {
                Text("System language").tag("");Text("English").tag("en");Text("Deutsch").tag("de");Text("Українська").tag("uk");Text("Русский").tag("ru");Text("Polski").tag("pl");Text("Български").tag("bg")
            }.pickerStyle(.inline)
            Text("Beta translations cover core planner/navigation/settings. Some detailed service messages remain in English. Your task titles, notes and other private content are never sent to a translation service.").font(.footnote)
        }.navigationTitle("Language")
    }
}
