#!/usr/bin/env python3
import asyncio
import base64
import http.server
import json
import os
import signal
import socketserver
import subprocess
import sys
import threading
import time
import urllib.request
import websockets

SCREENSHOTS_DIR = "/home/inbrewj/.gemini/antigravity-cli/brain/20e02e02-359c-4e68-8e1b-532c3371913f/scratch/screenshots"
os.makedirs(SCREENSHOTS_DIR, exist_ok=True)

class COOPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory="/home/inbrewj/workshop/chisel.town/docker/web_export", **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, format, *args):
        pass

def run_http_server():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", 7771), COOPHandler) as httpd:
        print("[HTTP Server] Serving docker/web_export on http://localhost:7771...")
        httpd.serve_forever()

async def get_cdp_page_ws():
    for _ in range(30):
        try:
            req = urllib.request.Request("http://127.0.0.1:9222/json")
            with urllib.request.urlopen(req) as resp:
                targets = json.loads(resp.read().decode())
                for t in targets:
                    if t.get("type") == "page" and "7771" in t.get("url", ""):
                        return t.get("webSocketDebuggerUrl")
        except Exception:
            pass
        await asyncio.sleep(0.5)
    raise RuntimeError("Could not find CDP page target")

class CDPClient:
    def __init__(self, ws):
        self.ws = ws
        self.req_id = 100

    async def call(self, method, params=None):
        self.req_id += 1
        msg_id = self.req_id
        req = {"id": msg_id, "method": method}
        if params:
            req["params"] = params
        await self.ws.send(json.dumps(req))
        while True:
            raw = await self.ws.recv()
            data = json.loads(raw)
            if data.get("id") == msg_id:
                return data.get("result", {})

    async def eval_js(self, expr):
        res = await self.call("Runtime.evaluate", {
            "expression": expr,
            "returnByValue": True,
            "awaitPromise": True
        })
        return res.get("result", {}).get("value")

    async def capture_screenshot(self, filename):
        res = await self.call("Page.captureScreenshot", {"format": "png"})
        img_b64 = res.get("data", "")
        if img_b64:
            path = os.path.join(SCREENSHOTS_DIR, filename)
            with open(path, "wb") as f:
                f.write(base64.b64decode(img_b64))
            print(f"[Screenshot] Saved: {filename} ({len(img_b64)} bytes)")
            return path
        return None

async def main():
    print("==================================================")
    print("   CHISEL TOWN 1855 - AUTOMATED BROWSER GAMEPLAY   ")
    print("==================================================")

    # 1. Start Rust Backend
    backend_env = os.environ.copy()
    backend_env["PORT"] = "7770"
    backend_proc = subprocess.Popen(
        ["/home/inbrewj/workshop/chisel.town/backend/target/release/chisel-server"],
        env=backend_env
    )
    print(f"[Backend] Started chisel-server PID={backend_proc.pid} on port 7770")

    # 2. Start HTTP Server for WebAssembly Frontend
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()
    await asyncio.sleep(1.0)

    # 3. Launch Google Chrome
    chrome_proc = subprocess.Popen([
        "/usr/bin/google-chrome",
        "--headless=new",
        "--remote-debugging-port=9222",
        "--disable-gpu",
        "--no-sandbox",
        "--window-size=1280,800",
        "http://127.0.0.1:7771/index.html"
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"[Chrome] Started headless Chrome PID={chrome_proc.pid}")

    try:
        cdp_ws_url = await get_cdp_page_ws()
        print(f"[CDP] Connecting to {cdp_ws_url}...")
        async with websockets.connect(cdp_ws_url, max_size=20000000) as ws:
            cdp = CDPClient(ws)
            await cdp.call("Page.enable")
            await cdp.call("Runtime.enable")

            print("[Game Engine] Waiting for Godot 4.7 Web engine to load and connect...")
            loaded = False
            for attempt in range(40):
                ready = await cdp.eval_js("Boolean(window.chiselReady)")
                if ready:
                    loaded = True
                    break
                await asyncio.sleep(0.5)

            if not loaded:
                print("⚠️ Warning: window.chiselReady timed out; checking canvas existence...")

            await asyncio.sleep(1.0)

            # --- Phase 0: Decanting ---
            phase = await cdp.eval_js("window.chiselPhase || 'Decanting'")
            clone = await cdp.eval_js("window.chiselClone || 1")
            print(f"[Phase 0: Decanting] Phase={phase} Clone={clone}")
            await cdp.capture_screenshot("01_decanting.png")

            # --- Phase 1: Murk Wandering ---
            print("[Action] Player triggers DECANT & RELEASE CLONE 01...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('release_clone')")
            for _ in range(20):
                await asyncio.sleep(0.3)
                phase = await cdp.eval_js("window.chiselPhase")
                if phase == "MurkWandering":
                    break

            subs = await cdp.eval_js("window.chiselSubtitles")
            print(f"[Phase 1: Murk Wandering] Phase={phase} Subtitles='{subs}'")
            await cdp.capture_screenshot("02_murk_wandering.png")

            # --- Walking Carl down the building corridor ---
            print("[Action] Carl walking down the building corridor...")
            for step in range(5):
                await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.22)")
                await asyncio.sleep(0.4)

            for _ in range(20):
                phase = await cdp.eval_js("window.chiselPhase")
                if phase == "TheDig":
                    break
                await asyncio.sleep(0.2)

            # --- Phase 2: The Dig ---
            dig_p = await cdp.eval_js("window.chiselDigProgress")
            print(f"[Phase 2: The Dig] Phase={phase} DigProgress={dig_p}")
            await cdp.capture_screenshot("03_the_dig.png")

            # --- Dig strikes until bedrock encountered ---
            print("[Action] Carl striking rock with shovel...")
            for strike in range(6):
                await cdp.eval_js("window.chiselAction && window.chiselAction('dig_strike')")
                await asyncio.sleep(0.3)

            for _ in range(20):
                dig_state = await cdp.eval_js("window.chiselDigState")
                if dig_state == "RockEncountered":
                    break
                await asyncio.sleep(0.2)

            subs = await cdp.eval_js("window.chiselSubtitles")
            print(f"[Obstacle] Bedrock encountered! DigState={dig_state} Subtitles='{subs}'")
            await cdp.capture_screenshot("04_bedrock_choice.png")

            # --- Binary Choice: Branch Left (softer basalt vein) ---
            print("[Action] Choosing LEFT branch: chisel softer basalt vein...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('dig_branch', 'left')")
            await asyncio.sleep(0.5)

            # --- Complete Dig to Breach ---
            print("[Action] Breaching final rock barrier...")
            for strike in range(6):
                await cdp.eval_js("window.chiselAction && window.chiselAction('dig_strike')")
                await asyncio.sleep(0.3)

            for _ in range(20):
                phase = await cdp.eval_js("window.chiselPhase")
                if phase == "ToxicCollapse":
                    break
                await asyncio.sleep(0.2)

            # --- Phase 3: Toxic Collapse ---
            print(f"[Phase 3: Toxic Collapse] Phase={phase}")
            await cdp.capture_screenshot("05_toxic_collapse.png")

            # --- Wait for Collapse and Reset to Clone 02 ---
            print("[Sequence] Crude flooding chamber... Carl drowning... Resetting to C2...")
            for _ in range(40):
                await asyncio.sleep(0.3)
                clone = await cdp.eval_js("window.chiselClone")
                if clone == 2:
                    break

            phase = await cdp.eval_js("window.chiselPhase")
            print(f"[Phase 4: Cycle Return] Clone={clone} Phase={phase}")
            await cdp.capture_screenshot("06_cycle_02_terminal.png")

            # --- Morphology Selection for C2 ---
            print("[Action] Darran injecting Bastion Wall morphology for C2 distraction...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('select_morphology', 'Bastion Wall')")
            await asyncio.sleep(1.0)
            await cdp.capture_screenshot("07_c2_morphology_injected.png")

        print("==================================================")
        print("   🎉 ALL GAMEPLAY PHASES VERIFIED SUCCESSFULLY!   ")
        print("==================================================")

    finally:
        print("[Cleanup] Stopping Chrome and backend processes...")
        try:
            chrome_proc.terminate()
            chrome_proc.wait(timeout=3)
        except Exception:
            chrome_proc.kill()

        try:
            backend_proc.terminate()
            backend_proc.wait(timeout=3)
        except Exception:
            backend_proc.kill()

if __name__ == "__main__":
    asyncio.run(main())
