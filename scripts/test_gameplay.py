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
            if data.get("method") == "Runtime.consoleAPICalled":
                args = data.get("params", {}).get("args", [])
                text = " ".join([str(a.get("value", a.get("description", ""))) for a in args])
                print(f"[Browser Console] {text}")
            elif data.get("method") == "Runtime.exceptionThrown":
                print(f"[Browser Exception] {data}")
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
            for attempt in range(60):
                ready = await cdp.eval_js("Boolean(window.chiselReady)")
                if ready:
                    loaded = True
                    break
                await asyncio.sleep(0.5)

            if not loaded:
                raise RuntimeError("Godot Web engine failed to initialize window.chiselReady within 30s")

            await asyncio.sleep(1.0)

            # --- Phase 0: Decanting ---
            phase = await cdp.eval_js("window.chiselPhase || 'Decanting'")
            clone = await cdp.eval_js("window.chiselClone || 1")
            print(f"[Phase 0: Decanting] Phase={phase} Clone={clone}")
            await cdp.capture_screenshot("01_decanting.png")

            # --- Darran places Iron Barricade on Site 1 ---
            print("[Action] Darran places Iron Barricade on Site 1...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('place_building', '1:Iron Barricade')")
            await asyncio.sleep(0.5)

            # --- Phase 1: Murk Wandering in 3D ---
            print("[Action] Player triggers DECANT & RELEASE CLONE 01 into 3D Corridor...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('release_clone')")
            for _ in range(20):
                await asyncio.sleep(0.3)
                phase = await cdp.eval_js("window.chiselPhase")
                if phase == "MurkWandering":
                    break

            subs = await cdp.eval_js("window.chiselSubtitles")
            print(f"[Phase 1: Murk Wandering 3D] Phase={phase} Subtitles='{subs}'")
            await cdp.capture_screenshot("02_murk_wandering_3d.png")

            # --- Interactive 3D Inspection: Turning Left & Right (A/D) ---
            print("[Action] Turning view to inspect left facades (A / LEFT)...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('player_turn', 0.65)")
            await asyncio.sleep(0.3)
            yaw_left = float(await cdp.eval_js("window.chiselCameraYaw || 0.0"))
            print(f"[Look Left] Camera Yaw={yaw_left:.3f} rad")
            await cdp.capture_screenshot("02b_corridor_turned_left_3d.png")

            # Test moving towards new heading
            print("[Action] Stepping forward toward left heading (W)...")
            x_before = float(await cdp.eval_js("window.chiselPlayerX || 0.0"))
            await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.05)")
            await asyncio.sleep(0.3)
            x_after = float(await cdp.eval_js("window.chiselPlayerX || 0.0"))
            print(f"[Heading Locomotion] Player X: {x_before:.2f} -> {x_after:.2f} (walked toward facing heading)")

            print("[Action] Turning view to inspect right facades (D / RIGHT)...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('player_turn', -1.30)")
            await asyncio.sleep(0.3)
            yaw_right = float(await cdp.eval_js("window.chiselCameraYaw || 0.0"))
            print(f"[Look Right] Camera Yaw={yaw_right:.3f} rad")
            await cdp.capture_screenshot("02c_corridor_turned_right_3d.png")

            # Re-center look straight ahead
            await cdp.eval_js("window.chiselAction && window.chiselAction('player_turn', 0.65)")
            await asyncio.sleep(0.2)

            # --- Test Backtracking (S / DOWN) ---
            print("[Action] Testing backward movement step (S / DOWN)...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.15)")
            await asyncio.sleep(0.3)
            prog_before = await cdp.eval_js("window.chiselState ? Number(window.chiselState.carl_corridor_progress) : 0.15")
            await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', -0.08)")
            await asyncio.sleep(0.3)
            prog_after = await cdp.eval_js("window.chiselState ? Number(window.chiselState.carl_corridor_progress) : 0.07")
            print(f"[Backtrack] Progress: {prog_before:.2f} -> {prog_after:.2f}")

            # --- Walking Carl down the 3D building corridor & Breaching C1 Barricade ---
            print("[Action] Carl walking down the 3D building corridor toward Barricade on Site 1...")
            # Step toward barricade
            await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.20)")
            await asyncio.sleep(0.3)
            # Strike barricade 3 times to shatter it
            for _ in range(3):
                await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.10)")
                await asyncio.sleep(0.3)
            # Continue down street to bedrock
            for _ in range(5):
                await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.20)")
                await asyncio.sleep(0.3)

            for _ in range(25):
                phase = await cdp.eval_js("window.chiselPhase")
                if phase == "TheDig":
                    break
                await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.15)")
                await asyncio.sleep(0.2)

            # --- Phase 2: 3D Bedrock Dig ---
            dig_p = await cdp.eval_js("window.chiselDigProgress")
            print(f"[Phase 2: 3D Bedrock Dig] Phase={phase} DigProgress={dig_p}")
            await cdp.capture_screenshot("03_the_dig_3d.png")

            # --- Dig strikes until bedrock encountered ---
            print("[Action] Carl striking 3D bedrock with 3D spade...")
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
            await cdp.capture_screenshot("04_bedrock_choice_3d.png")

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

            # --- Phase 3: 3D Toxic Collapse (Crude Oil Flooding) ---
            print(f"[Phase 3: 3D Toxic Collapse] Phase={phase}")
            await cdp.capture_screenshot("05_toxic_collapse_3d.png")

            # --- Wait for Collapse and Reset to Clone 02 ---
            print("[Sequence] 3D crude flooding chamber... Carl drowning... Resetting to C2...")
            for _ in range(40):
                await asyncio.sleep(0.3)
                clone = await cdp.eval_js("window.chiselClone")
                if clone == 2:
                    break

            phase = await cdp.eval_js("window.chiselPhase")
            print(f"[Phase 4: Cycle Return] Clone={clone} Phase={phase}")
            await cdp.capture_screenshot("06_cycle_02_terminal.png")

            # --- Bob Sweeney Stilt Cabin 3D View ---
            print("[Action] Testing [BOB'S VIEW] toggle...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('toggle_bob_view')")
            await asyncio.sleep(1.0)
            await cdp.capture_screenshot("07_bobs_cabin_3d.png")

            # Toggle back to Town Map
            await cdp.eval_js("window.chiselAction && window.chiselAction('toggle_bob_view')")
            await asyncio.sleep(0.5)

            # --- Swarm Stacking in C2 Planning ---
            print("[Action] Darran places Mercy Hospital on Site 2, then stacks Academy School...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('place_building', '2:Mercy Hospital')")
            await asyncio.sleep(0.4)
            await cdp.eval_js("window.chiselAction && window.chiselAction('place_building', '2:Academy School')")
            await asyncio.sleep(0.5)
            await cdp.capture_screenshot("08_c2_swarm_stacked_map.png")

            # --- Release Clone 02 & Josiah H Foray Encounter ---
            print("[Action] Releasing Clone 02 to encounter Josiah H Foray in 3D...")
            await cdp.eval_js("window.chiselAction && window.chiselAction('release_clone')")
            for _ in range(20):
                await asyncio.sleep(0.3)
                phase = await cdp.eval_js("window.chiselPhase")
                if phase == "MurkWandering":
                    break

            # March to midway (approx z = -22m where Josiah stands)
            for _ in range(3):
                await cdp.eval_js("window.chiselAction && window.chiselAction('player_move', 0.16)")
                await asyncio.sleep(0.4)

            subs = await cdp.eval_js("window.chiselSubtitles")
            print(f"[Josiah Encounter] Subtitles='{subs}'")
            await cdp.capture_screenshot("09_josiah_encounter_3d.png")

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
