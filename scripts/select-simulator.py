import json
import subprocess

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-" not in runtime:
        continue
    for device in devices[runtime]:
        if device["name"].startswith("iPhone") and device.get("isAvailable", False):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator. Install an iOS simulator runtime in Xcode.")
