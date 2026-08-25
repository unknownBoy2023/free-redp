import threading, json, os
from mock_rules import get_mock_response, TARGET_APP_FILTER
LOG_FILE = "/sdcard/NetSnitchX/logs.json"
os.makedirs("/sdcard/NetSnitchX", exist_ok=True)
class SnitchAddon:
    def __init__(self):
        self.log = []
        self.intercept_mode = True
snitch_addon = SnitchAddon()
def start_proxy():
    print("🚀 NetSnitchX Proxy Engine ONLINE")
