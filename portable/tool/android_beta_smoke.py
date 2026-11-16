"""Exercise the shipped release resources and native notification channel."""
import os, re, subprocess, time, xml.etree.ElementTree as ET
from pathlib import Path

out = Path('release'); out.mkdir(exist_ok=True)
def adb(*args):
    return subprocess.check_output(['adb', *args], text=True, stderr=subprocess.STDOUT)
def capture(name):
    with (out / name).open('wb') as file:
        subprocess.run(['adb', 'exec-out', 'screencap', '-p'], stdout=file, check=True)
def tap(label, scroll=False):
    for attempt in range(8):
        adb('shell', 'uiautomator', 'dump', '/sdcard/onestep-ui.xml')
        xml = adb('shell', 'cat', '/sdcard/onestep-ui.xml')
        (out / 'last-ui.xml').write_text(xml)
        root = ET.fromstring(xml)
        for node in root.iter('node'):
            text = node.get('text', '') + '\n' + node.get('content-desc', '')
            if label in text:
                bounds = list(map(int, re.findall(r'\d+', node.get('bounds', ''))))
                if len(bounds) == 4 and bounds[3] > bounds[1]:
                    adb('shell', 'input', 'tap', str((bounds[0]+bounds[2])//2), str((bounds[1]+bounds[3])//2))
                    time.sleep(1)
                    return
        if scroll:
            size = re.findall(r'(\d+)x(\d+)', adb('shell','wm','size'))[-1]
            width,height=map(int,size)
            adb('shell','input','swipe',str(width//2),str(int(height*.78)),str(width//2),str(int(height*.35)),'350')
        time.sleep(1)
    capture('failure.png')
    raise AssertionError('Could not find control: '+label)

try:
    adb('install', '-r', 'portable/build/app/outputs/flutter-apk/app-release.apk')
    adb('shell','pm','grant','meow.tira.onestep','android.permission.POST_NOTIFICATIONS')
    adb('logcat','-c')
    adb('shell','am','start','-n','meow.tira.onestep/meow.tira.onestep.MainActivity')
    time.sleep(6)
    capture('Android-Now-device.png')
    tap('More')
    capture('Android-More-device.png')
    tap('Reminders and settings',scroll=True)
    tap('Send test reminder',scroll=True)
    time.sleep(2)
    notifications=adb('shell','dumpsys','notification','--noredact')
    assert re.search(r'NotificationRecord[^\n]*pkg=meow\.tira\.onestep[^\n]*id=2147483646',notifications), 'No test notification posted by the release APK'
    adb('shell','cmd','statusbar','expand-notifications'); time.sleep(1)
    capture('Android-notification-device.png')
    log=adb('logcat','-d')
    assert 'invalid_icon' not in log, 'Release notification icon was removed'
    assert 'FATAL EXCEPTION' not in log, 'Android crash detected'
    (out/'ANDROID-SMOKE.txt').write_text('PASS: actual release APK launched; More and reminder controls opened; native test notification posted with precise-alarm access not granted. No invalid_icon or fatal crash. Android API35 x86_64 emulator.\n')
finally:
    (out/'android-logcat.txt').write_text(adb('logcat','-d'))
