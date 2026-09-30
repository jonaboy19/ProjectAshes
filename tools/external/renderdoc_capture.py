"""Capture ONE frame of an app (Godot) with RenderDoc and print draw-call statistics.
Runs INSIDE qrenderdoc (its embedded Python 3.8 has the `renderdoc` module; there is no standalone pyd):

  set RD_APP=<godot exe>; RD_ARGS=<args string>; RD_OUT=<dir>; [RD_WAIT=8 seconds before capture]
  qrenderdoc.exe --python tools/external/renderdoc_capture.py

Writes <RD_OUT>/capture.rdc, drawcalls.json and capture_log.txt, then exits the process (os._exit) so it is scriptable.
Use scripts/wrapper tools/external/renderdoc_godot.ps1 which sets the variables and kills only its own processes.
"""
import os, sys, time, json
import renderdoc as rd

APP = os.environ["RD_APP"]; ARGS = os.environ.get("RD_ARGS", ""); OUT = os.environ["RD_OUT"]
WAIT = float(os.environ.get("RD_WAIT", "8"))          # seconds to let the app reach steady state
WD = os.environ.get("RD_WD", os.path.dirname(APP))
os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, "capture_log.txt"), "w")


def P(*a):
    log.write(" ".join(str(x) for x in a) + "\n"); log.flush()


def finish(code=0):
    log.close(); os._exit(code)


try:
    opts = rd.CaptureOptions()
    res = rd.ExecuteAndInject(APP, WD, ARGS, [], os.path.join(OUT, "auto.rdc"), opts, False)
    ident = getattr(res, "ident", res)
    P("launched ident", ident, "result", getattr(res, "result", None))
    if not ident:
        finish(2)
    time.sleep(WAIT)
    tc = rd.CreateTargetControl("", ident, "ashes", True)
    if tc is None:
        P("no target control"); finish(3)
    P("target", tc.GetTarget(), "api", tc.GetAPI(), "pid", tc.GetPID())
    open(os.path.join(OUT, "app.pid"), "w").write(str(tc.GetPID()))
    tc.TriggerCapture(1)
    cap_path = None
    t0 = time.time()
    while time.time() - t0 < 30 and cap_path is None:
        msg = tc.ReceiveMessage(None)
        if msg.type == rd.TargetControlMessageType.NewCapture:
            cap_id = msg.newCapture.captureId
            cap_path = os.path.join(OUT, "capture.rdc")
            tc.CopyCapture(cap_id, cap_path)
            while time.time() - t0 < 60:
                m2 = tc.ReceiveMessage(None)
                if m2.type == rd.TargetControlMessageType.CaptureCopied:
                    break
        elif msg.type == rd.TargetControlMessageType.Disconnected:
            break
    tc.Shutdown()
    if not cap_path or not os.path.exists(cap_path):
        P("no capture"); finish(4)
    P("captured", cap_path, os.path.getsize(cap_path))

    cf = rd.OpenCaptureFile()
    P("open", cf.OpenFile(cap_path, "", None))
    st, ctl = cf.OpenCapture(rd.ReplayOptions(), None)
    P("replay", st)
    stats = {"draws": 0, "indexed": 0, "dispatches": 0, "clears": 0, "copies": 0, "passes": 0, "triangles_incl_shadow_passes": 0}

    def walk(acts):
        for a in acts:
            f = a.flags
            if f & rd.ActionFlags.Drawcall:
                stats["draws"] += 1
                stats["triangles_incl_shadow_passes"] += (a.numIndices // 3) * max(1, a.numInstances)
                if f & rd.ActionFlags.Indexed:
                    stats["indexed"] += 1
            if f & rd.ActionFlags.Dispatch: stats["dispatches"] += 1
            if f & rd.ActionFlags.Clear: stats["clears"] += 1
            if f & rd.ActionFlags.Copy: stats["copies"] += 1
            if f & rd.ActionFlags.BeginPass: stats["passes"] += 1
            walk(a.children)

    walk(ctl.GetRootActions())
    stats["api"] = str(cf.DriverName())
    stats["frame_number"] = ctl.GetFrameInfo().frameNumber
    json.dump(stats, open(os.path.join(OUT, "drawcalls.json"), "w"), indent=2)
    P(json.dumps(stats))
    ctl.Shutdown(); cf.Shutdown()
    finish(0)
except SystemExit:
    raise
except Exception as e:
    import traceback
    P("EXC", traceback.format_exc()); finish(9)

