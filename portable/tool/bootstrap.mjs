import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const root = path.resolve('portable');
const temp = path.resolve('build/portable-generated');
fs.mkdirSync(path.dirname(temp),{recursive:true});
execFileSync(process.platform==='win32'?'flutter.bat':'flutter', ['create','--platforms=android,windows,linux','--org','meow.tira','--project-name','onestep','--no-pub',temp], {stdio:'inherit',shell:process.platform==='win32'});
for (const platform of ['android','windows','linux']) fs.cpSync(path.join(temp,platform),path.join(root,platform),{recursive:true});
let manifest=fs.readFileSync(`${root}/android/app/src/main/AndroidManifest.xml`,'utf8');
manifest=manifest.replace('<application',`<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <application android:usesCleartextTraffic="true" android:allowBackup="false"`)
  .replace('android:label="onestep"','android:label="OneStep"')
  .replace('</application>',`<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"><intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/><action android:name="android.intent.action.MY_PACKAGE_REPLACED"/></intent-filter></receiver>
    </application>`);
fs.writeFileSync(`${root}/android/app/src/main/AndroidManifest.xml`,manifest);
let gradle=fs.readFileSync(`${root}/android/app/build.gradle.kts`,'utf8');
gradle=gradle.replace('compileOptions {','compileOptions {\n        isCoreLibraryDesugaringEnabled = true');
gradle+='\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }\n';
// A private release key can be configured by repository secrets. No key is committed.
gradle=gradle.replace('buildTypes {',`signingConfigs {
      if (System.getenv("ONESTEP_KEYSTORE") != null) create("onestep") {
        storeFile = file(System.getenv("ONESTEP_KEYSTORE"))
        storePassword = System.getenv("ONESTEP_STORE_PASSWORD")
        keyAlias = System.getenv("ONESTEP_KEY_ALIAS")
        keyPassword = System.getenv("ONESTEP_KEY_PASSWORD")
      }
    }
    buildTypes {`).replace('signingConfig = signingConfigs.getByName("debug")','signingConfig = signingConfigs.findByName("onestep") ?: signingConfigs.getByName("debug")');
fs.writeFileSync(`${root}/android/app/build.gradle.kts`,gradle);
const kotlin=`package meow.tira.onestep
import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var reply: MethodChannel.Result? = null
    private var backup: ByteArray? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "meow.tira.onestep/files").setMethodCallHandler { call, result ->
            if (call.method != "exportBackup") { result.notImplemented() }
            else if (reply != null) { result.error("busy", "A file dialog is already open", null) }
            else {
                backup = (call.arguments as String).toByteArray(Charsets.UTF_8)
                reply = result
                try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE); type = "application/json"; putExtra(Intent.EXTRA_TITLE, "OneStep-backup.json")
                }, 2107) } catch (error: Exception) { reply = null; backup = null; result.error("export", error.message, null) }
            }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 2107) return
        val result = reply; reply = null
        val bytes = backup; backup = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) { result?.success(null); return }
        try {
            contentResolver.openOutputStream(data.data!!)?.use { it.write(bytes ?: byteArrayOf()) }
                ?: throw Exception("Could not open selected file")
            result?.success(null)
        } catch (error: Exception) { result?.error("export", error.message, null) }
    }
}
`;
fs.writeFileSync(`${root}/android/app/src/main/kotlin/meow/tira/onestep/MainActivity.kt`,kotlin);
fs.mkdirSync(`${root}/android/app/src/main/res/drawable`,{recursive:true});
fs.writeFileSync(`${root}/android/app/src/main/res/drawable/ic_notification.xml`,'<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:fillColor="#FFFFFFFF" android:pathData="M9,16.2L4.8,12l-1.4,1.4L9,19l12,-12l-1.4,-1.4z"/></vector>');
for (const file of ['windows/CMakeLists.txt','windows/runner/Runner.rc','windows/runner/main.cpp','linux/CMakeLists.txt','linux/runner/my_application.cc']) {
  const name=`${root}/${file}`;let value=fs.readFileSync(name,'utf8');
  if(file==='windows/CMakeLists.txt')value=value.replace('set(BINARY_NAME "onestep")','set(BINARY_NAME "Tira-OneStep")');
  if(file.endsWith('Runner.rc'))value=value.replaceAll('onestep.exe','Tira-OneStep.exe').replaceAll('"onestep"','"OneStep"').replaceAll('com.example','meow.tira');
  if(file.endsWith('main.cpp'))value=value.replace('L"onestep"','L"OneStep"');
  if(file.startsWith('linux'))value=value.replaceAll('com.example.onestep','meow.tira.onestep').replaceAll('meow.tira.onestep','meow.tira.onestep').replaceAll('"onestep"','"OneStep"');
  // Keep Linux executable's lowercase filename for AppRun.
  if(file==='linux/CMakeLists.txt')value=value.replace('set(BINARY_NAME "OneStep")','set(BINARY_NAME "onestep")');
  fs.writeFileSync(name,value);
}
console.log('Generated platform projects: Android meow.tira.onestep, Windows Tira-OneStep.exe, Linux meow.tira.onestep.');
