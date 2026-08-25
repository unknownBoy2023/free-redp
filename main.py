from kivy.app import App
from kivy.uix.button import Button
from kivy.uix.floatlayout import FloatLayout
from kivy.core.window import Window
from kivy.utils import platform
from proxy_engine import snitch_addon, start_proxy
import threading
Window.size = (300, 200) if platform != 'android' else (250, 150)
Window.borderless = True
Window.topmost = True
class NetSnitchApp(App):
    def build(self):
        threading.Thread(target=start_proxy, daemon=True).start()
        root = FloatLayout()
        self.toggle_btn = Button(text="🔴 OFF", size_hint=(None, None), size=(70, 70), pos=(100, 50), background_color=(1, 0, 0, 0.8))
        root.add_widget(self.toggle_btn)
        return root
if __name__ == '__main__':
    NetSnitchApp().run()
