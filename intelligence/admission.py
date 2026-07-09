"""
Inference Admission Controller
==============================
Duty-cycles CPU mining around LLM inference bursts. The core of the
Local Intelligence Layer v2 architecture (Section 3): the LLM never
runs simultaneously with full-throttle mining — the controller
downshifts mining threads, runs the inference job, and restores.

Operating modes:
  MINING   - 8 threads (cores 0,2,4,6,8,10,12,14), no inference
  QUERY    - 4 threads (cores 0,2,4,6), inference on freed cores
  REFLECT  - mining paused, full bandwidth to inference (nightly only)
  COOLDOWN - inference blocked/queued by thermal gate

Design notes:
  - Thread reduction uses PUT /2/config editing ONLY cpu.rx affinity;
    the RandomX dataset stays resident (no ~30s re-init penalty).
  - Full pause (REFLECT) uses /2/pause and pays the re-init on resume.
  - Hashrate canary: if the 10s hashrate fails to recover after
    restore, a downgrade flag persists for subsequent jobs.

Usage:
  python -m intelligence.admission --self-test
  python -m intelligence.admission --self-test --model granite4.1:3b

Author: XMRig Automation
License: MIT
"""

import argparse
import copy
import json
import os
import sys
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Optional
from urllib.request import Request, urlopen

# Repo-root imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dashboard.xmrig_api_client import XMRigAPIClient, XMRigAPIError  # noqa: E402
from intelligence.decision_logger import DecisionLogger  # noqa: E402

XMRIG_CONFIG_PATH = r"C:\XMRig\xmrig-6.22.0\config.json"
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")

FULL_THREADS = [0, 2, 4, 6, 8, 10, 12, 14]
REDUCED_THREADS = [0, 2, 4, 6]

RECOVERY_TIMEOUT_S = 45.0  # config PUT re-inits dataset (~6s) + 10s hashrate
                           # window needs ~10s of full-speed mining to reflect
CANARY_TOLERANCE = 0.85  # restored hashrate must reach 85% of baseline


def _metrics():
    """Best-effort accessor for the Prometheus metrics registry (Sprint
    4.2). Returns None if no metrics server has been started (e.g. under
    test, or if this instrumentation isn't wanted) -- every call site
    must guard for that rather than assume metrics are always running.
    Never raises: a metrics-recording failure must never be allowed to
    affect mining or inference admission."""
    try:
        from dashboard.prometheus_metrics import get_metrics
        return get_metrics()
    except Exception:
        return None


class Mode(Enum):
    MINING = "MINING"
    QUERY = "QUERY"
    REFLECT = "REFLECT"
    COOLDOWN = "COOLDOWN"


@dataclass
class InferenceJob:
    prompt: str
    model: str = "granite4.1:3b"
    heavy: bool = False          # heavy=True -> REFLECT (full pause)
    duration_est_s: float = 30.0


@dataclass
class AdmissionDecision:
    admitted: bool
    mode: Mode
    reason_code: str
    result: Optional[str] = None
    metrics: dict = field(default_factory=dict)


def _load_access_token(config_path: str = XMRIG_CONFIG_PATH) -> Optional[str]:
    """Read the API token from the local XMRig config (never committed)."""
    token = os.environ.get("XMRIG_ACCESS_TOKEN")
    if token:
        return token
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        return cfg.get("http", {}).get("access-token")
    except (OSError, json.JSONDecodeError):
        return None


def default_thermal_gate() -> Callable[[], bool]:
    """Returns a gate callable: True = safe to run inference.

    Uses ml.thermal_predictor if temperature readings are being fed;
    falls back to always-safe when no sensor data is available
    (interim static behavior per v2 plan risk R5).
    """
    try:
        from ml.thermal_predictor import ThermalPredictor
        predictor = ThermalPredictor()

        def gate() -> bool:
            if predictor.sample_count < 5:  # property, not method
                return True  # no data -> do not block
            return predictor.predict(seconds_ahead=60) < 80.0

        gate.predictor = predictor  # expose for injection of readings
        return gate
    except ImportError:
        return lambda: True


class AdmissionController:
    """Thermal-gated, duty-cycled inference admission."""

    def __init__(
        self,
        xmrig_client: Optional[XMRigAPIClient] = None,
        thermal_gate: Optional[Callable[[], bool]] = None,
        logger: Optional[DecisionLogger] = None,
        ollama_url: str = OLLAMA_URL,
    ):
        self.client = xmrig_client or XMRigAPIClient(
            access_token=_load_access_token()
        )
        self.thermal_gate = thermal_gate or default_thermal_gate()
        self.logger = logger or DecisionLogger()
        self.ollama_url = ollama_url
        self.mode = Mode.MINING
        self.downgrade_active = False  # canary flag: persists across jobs
        self._queue: list = []

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def request(self, job: InferenceJob) -> AdmissionDecision:
        """Admit, queue, or run an inference job through the full cycle."""
        # 1. Thermal gate
        if not self.thermal_gate():
            self._queue.append(job)
            self._log("thermal_gate", "TEMP_FORECAST",
                      detail={"queued": True, "model": job.model})
            m = _metrics()
            if m:
                m.admission_queue_depth.set(len(self._queue))
            return AdmissionDecision(
                admitted=False, mode=Mode.COOLDOWN,
                reason_code="TEMP_FORECAST",
            )

        mining = self._miner_running()
        baseline = self._hashrate_10s() if mining else 0.0

        # 2. Downshift (or pause for heavy jobs)
        target_mode = Mode.REFLECT if job.heavy else Mode.QUERY
        if mining:
            if job.heavy:
                self._pause()
            else:
                self._set_threads(REDUCED_THREADS)
            self._transition(target_mode, baseline)
        else:
            self.mode = target_mode
        m = _metrics()
        if m:
            m.record_mode(target_mode.value)

        # 3. Execute
        t0 = time.time()
        try:
            result = self._run_inference(job)
            error = None
        except Exception as e:  # inference failure must never strand mining
            result, error = None, str(e)
        elapsed = time.time() - t0
        m = _metrics()
        if m:
            m.inference_latency.set(elapsed)
            m.advisor_calls.inc()

        # 4. Restore
        recovery_s = None
        if mining:
            if job.heavy:
                self._resume()
            else:
                self._set_threads(FULL_THREADS)
            recovery_s = self._await_recovery(baseline)
            self._transition(Mode.MINING, baseline, recovery_s=recovery_s)
        else:
            self.mode = Mode.MINING
        m = _metrics()
        if m:
            m.record_mode(Mode.MINING.value)
            if mining:
                lost_s = elapsed + (recovery_s or 0.0)
                m.hashrate_minutes_lost.inc(lost_s / 60.0)

        # 5. Canary check
        if mining and recovery_s is None:
            self.downgrade_active = True
            self._log("canary_tripped", "HASHRATE_NO_RECOVERY",
                      detail={"baseline": baseline})

        metrics = {
            "inference_s": round(elapsed, 2),
            "baseline_hs": baseline,
            "recovery_s": recovery_s,
            "error": error,
        }
        self._log(
            "inference_complete", "ADMITTED_DUTY_CYCLE",
            detail={"model": job.model, "heavy": job.heavy,
                    "mining_active": mining, **metrics},
        )
        return AdmissionDecision(
            admitted=True, mode=Mode.MINING,
            reason_code="ADMITTED_DUTY_CYCLE",
            result=result, metrics=metrics,
        )

    def drain_queue(self) -> int:
        """Run queued jobs if the thermal gate has cleared."""
        ran = 0
        while self._queue and self.thermal_gate():
            self.request(self._queue.pop(0))
            ran += 1
        return ran

    # ------------------------------------------------------------------
    # XMRig control
    # ------------------------------------------------------------------

    def _miner_running(self) -> bool:
        try:
            return self.client.is_running()
        except Exception:
            return False

    def _hashrate_10s(self) -> float:
        try:
            return self.client.get_summary(use_cache=False).hashrate_10s or 0.0
        except XMRigAPIError:
            return 0.0

    def _set_threads(self, cores: list) -> bool:
        """Hot-swap the RandomX affinity list via config PUT."""
        try:
            cfg = self.client.get_config()
        except XMRigAPIError:
            return False
        cfg = copy.deepcopy(cfg)  # never mutate a shared/cached dict
        cpu = cfg.get("cpu", {})
        cpu["rx"] = list(cores)
        cfg["cpu"] = cpu
        ok = self.client.put_config(cfg)
        self._log(
            "threads_set", "DUTY_CYCLE",
            detail={"cores": cores, "ok": ok},
        )
        return ok

    def _pause(self) -> None:
        self.client.pause()
        self._log("miner_paused", "REFLECT_JOB")

    def _resume(self) -> None:
        self.client.resume()
        self._log("miner_resumed", "REFLECT_DONE")

    def _await_recovery(self, baseline: float,
                        timeout: float = RECOVERY_TIMEOUT_S) -> Optional[float]:
        """Poll until 10s hashrate returns to tolerance of baseline."""
        if baseline <= 0:
            return 0.0
        start = time.time()
        while time.time() - start < timeout:
            if self._hashrate_10s() >= baseline * CANARY_TOLERANCE:
                return round(time.time() - start, 2)
            time.sleep(1.0)
        return None

    # ------------------------------------------------------------------
    # Ollama
    # ------------------------------------------------------------------

    def _run_inference(self, job: InferenceJob) -> str:
        body = json.dumps({
            "model": job.model,
            "prompt": job.prompt,
            "stream": False,
            "keep_alive": "30m",
            "options": {"num_ctx": 4096},
        }).encode("utf-8")
        req = Request(
            f"{self.ollama_url}/api/generate",
            data=body, headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(req, timeout=300) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data.get("response", "")

    # ------------------------------------------------------------------
    # Logging / state
    # ------------------------------------------------------------------

    def _transition(self, mode: Mode, baseline: float,
                    recovery_s: Optional[float] = None) -> None:
        before = self.mode
        self.mode = mode
        self._log(
            "mode_change", "DUTY_CYCLE",
            state_before={"mode": before.value, "hashrate_10s": baseline},
            state_after={"mode": mode.value, "recovery_s": recovery_s},
        )

    def _log(self, event: str, reason_code: str, **kwargs) -> None:
        self.logger.log(source="admission", event=event,
                        reason_code=reason_code, **kwargs)


# ----------------------------------------------------------------------
# Self-test
# ----------------------------------------------------------------------

def self_test(model: str) -> int:
    print("=== Admission Controller Self-Test ===")
    ctrl = AdmissionController()

    mining = ctrl._miner_running()
    print(f"Miner running:      {mining}")
    baseline = ctrl._hashrate_10s() if mining else 0.0
    print(f"Baseline 10s H/s:   {baseline:.0f}")

    job = InferenceJob(
        prompt=("Reply ONLY with JSON: "
                '{"status": "ok", "advisor": "<model name you are>"}'),
        model=model,
    )
    t0 = time.time()
    decision = ctrl.request(job)
    total = time.time() - t0

    print(f"Admitted:           {decision.admitted}")
    print(f"Reason:             {decision.reason_code}")
    print(f"Inference time:     {decision.metrics.get('inference_s')}s")
    print(f"Recovery time:      {decision.metrics.get('recovery_s')}s")
    print(f"Total cycle:        {total:.1f}s")
    print(f"Canary downgrade:   {ctrl.downgrade_active}")
    print(f"Response:           {(decision.result or '')[:200]}")
    if decision.metrics.get("error"):
        print(f"ERROR:              {decision.metrics['error']}")
        return 1
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Inference admission controller")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--model", default="granite4.1:3b")
    args = parser.parse_args()
    if args.self_test:
        sys.exit(self_test(args.model))
    parser.print_help()
