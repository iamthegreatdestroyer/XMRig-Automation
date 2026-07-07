"""
Mining Advisor
==============
The Explanation Engine of the Local Intelligence Layer v2 (Section 3).
A small local LLM (granite4.1:3b) answers natural-language questions
about mining behavior, grounded EXCLUSIVELY in the structured decision
log and live telemetry. Every answer must cite reason_codes present in
the log — fabricated evidence is detected and rejected.

The LLM has ZERO direct authority: proposed_action.requires_ratification
is always true.

All inference goes through the AdmissionController (duty-cycled around
mining). Heavy jobs (nightly_reflect) use REFLECT mode with lfm2.5.

Usage:
    python -m intelligence.advisor --ask "Why did hashrate drop?"
    python -m intelligence.advisor --reflect
    python -m intelligence.advisor --audit          # 10-shot schema audit

Author: XMRig Automation
License: MIT
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from intelligence.admission import (  # noqa: E402
    AdmissionController, InferenceJob,
)
from intelligence.decision_logger import DecisionLogger  # noqa: E402

QUERY_MODEL = os.environ.get("ADVISOR_QUERY_MODEL", "granite4.1:3b")
REFLECT_MODEL = os.environ.get("ADVISOR_REFLECT_MODEL", "lfm2.5")

REFLECTIONS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "logs", "reflections",
)

RESPONSE_SCHEMA = {
    "answer": "string",
    "evidence": [{"ts": "string", "reason_code": "string", "event": "string"}],
    "confidence": "high | medium | low",
    "proposed_action": (
        'null | {"type": "config_hint | pool_switch | none", '
        '"params": {}, "requires_ratification": true}'
    ),
}

SYSTEM_PROMPT = """You are the XMRig mining advisor on a Ryzen 7 7730U laptop.
You explain mining decisions using ONLY the DECISION LOG and TELEMETRY provided.
Rules:
1. Cite evidence: every claim must reference ts + reason_code + event values
   that appear VERBATIM in the DECISION LOG below. Never invent evidence.
2. If the log lacks relevant entries, say so and set confidence to "low".
3. You may propose actions but NEVER execute them; requires_ratification
   is always true.
4. Respond ONLY with JSON matching this schema (no prose outside JSON):
""" + json.dumps(RESPONSE_SCHEMA, indent=2)

_THINK_BLOCK_RE = re.compile(r"<think>.*?</think>\s*", re.DOTALL | re.IGNORECASE)
_MD_FENCE_RE = re.compile(r"^```(?:markdown)?\s*\n(.*)\n```\s*$", re.DOTALL)


def _strip_thinking(text: str) -> str:
    """Remove a model's <think>...</think> reasoning block and an outer
    markdown code fence, if present, leaving just the final answer.

    Reasoning models (lfm2.5 in REFLECT mode) emit visible chain-of-thought
    before the answer — valuable for interactive debugging (MiningAdvisor
    keeps it in .raw), but it must not leak into a written reflection file
    meant to be read as plain markdown.
    """
    text = _THINK_BLOCK_RE.sub("", text).strip()
    fence_match = _MD_FENCE_RE.match(text)
    if fence_match:
        text = fence_match.group(1).strip()
    return text


@dataclass
class AdvisorResponse:
    answer: str
    evidence: list = field(default_factory=list)
    confidence: str = "low"
    proposed_action: Optional[dict] = None
    valid: bool = True
    fabricated_evidence: list = field(default_factory=list)
    raw: str = ""


class MiningAdvisor:
    """Evidence-grounded LLM advisor with hallucination detection."""

    def __init__(
        self,
        admission: Optional[AdmissionController] = None,
        logger: Optional[DecisionLogger] = None,
        query_model: str = QUERY_MODEL,
        reflect_model: str = REFLECT_MODEL,
        context_records: int = 40,
    ):
        self.admission = admission or AdmissionController()
        self.logger = logger or DecisionLogger()
        self.query_model = query_model
        self.reflect_model = reflect_model
        self.context_records = context_records

    # ------------------------------------------------------------------
    # Prompt building
    # ------------------------------------------------------------------

    def _telemetry_snapshot(self) -> dict:
        try:
            s = self.admission.client.get_summary(use_cache=False)
            return {
                "hashrate_10s": s.hashrate_10s,
                "hashrate_60s": s.hashrate_60s,
                "hashrate_15m": s.hashrate_15m,
                "threads": s.threads,
                "pool": s.pool_url,
                "shares_accepted": s.shares_accepted,
                "shares_rejected": s.shares_rejected,
                "uptime_s": s.uptime,
            }
        except Exception:
            return {"miner": "offline"}

    def _build_prompt(self, question: str) -> str:
        records = self.logger.tail(self.context_records)
        log_text = "\n".join(json.dumps(r, separators=(",", ":"))
                             for r in records) or "(empty)"
        telemetry = json.dumps(self._telemetry_snapshot())
        return (
            f"{SYSTEM_PROMPT}\n\n"
            f"DECISION LOG (most recent {len(records)} entries):\n{log_text}\n\n"
            f"LIVE TELEMETRY:\n{telemetry}\n\n"
            f"QUESTION: {question}\n"
        )

    # ------------------------------------------------------------------
    # Validation (anti-hallucination)
    # ------------------------------------------------------------------

    def _validate(self, raw: str) -> AdvisorResponse:
        # Extract JSON (tolerate thinking preamble / code fences)
        text = raw.strip()
        start, end = text.find("{"), text.rfind("}")
        if start == -1 or end == -1:
            return AdvisorResponse(answer=raw, valid=False, raw=raw)
        try:
            data = json.loads(text[start:end + 1])
        except json.JSONDecodeError:
            return AdvisorResponse(answer=raw, valid=False, raw=raw)

        resp = AdvisorResponse(
            answer=str(data.get("answer", "")),
            evidence=data.get("evidence", []) or [],
            confidence=str(data.get("confidence", "low")),
            proposed_action=data.get("proposed_action"),
            raw=raw,
        )

        # Enforce zero-authority rule
        if isinstance(resp.proposed_action, dict):
            resp.proposed_action["requires_ratification"] = True

        # Evidence grounding: every cited reason_code must exist in the log
        known = {(r.get("reason_code"), r.get("event"))
                 for r in self.logger.tail(500)}
        known_codes = {rc for rc, _ in known}
        for ev in resp.evidence:
            rc = ev.get("reason_code") if isinstance(ev, dict) else None
            if rc and rc not in known_codes:
                resp.fabricated_evidence.append(ev)
        if resp.fabricated_evidence:
            resp.valid = False
        return resp

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def answer(self, question: str, retries: int = 1) -> AdvisorResponse:
        """Answer a question via duty-cycled inference; one retry on
        invalid JSON or fabricated evidence."""
        prompt = self._build_prompt(question)
        last = None
        for attempt in range(retries + 1):
            decision = self.admission.request(
                InferenceJob(prompt=prompt, model=self.query_model)
            )
            if not decision.admitted:
                return AdvisorResponse(
                    answer="Inference queued: thermal gate active.",
                    confidence="low", valid=False,
                )
            resp = self._validate(decision.result or "")
            self.logger.log(
                source="advisor", event="question_answered",
                reason_code="ADVISOR_RESPONSE",
                detail={"question": question, "valid": resp.valid,
                        "confidence": resp.confidence,
                        "fabricated": len(resp.fabricated_evidence),
                        "attempt": attempt},
            )
            if resp.valid:
                return resp
            last = resp
        return last

    def nightly_reflect(self) -> Optional[str]:
        """Heavy REFLECT-mode job: summarize the day's decision log.
        Writes logs/reflections/YYYY-MM-DD.md and returns the path.

        Returns None (writing nothing) if the thermal gate deferred the
        job rather than running it — that is not a failure, it means
        "try again later tonight," and a scheduler should retry rather
        than record a misleading "(reflection failed)" file.

        Idempotent: if today's reflection already exists, returns its
        path immediately without re-running inference. This lets a
        scheduler safely fire this repeatedly (e.g. every 30 min via
        Task Scheduler's native repetition) as a retry mechanism for
        thermal deferrals — once one run succeeds, later firings in
        the same night are harmless no-ops.
        """
        today = datetime.now(timezone.utc).date().isoformat()
        existing_path = os.path.join(REFLECTIONS_DIR, f"{today}.md")
        if os.path.exists(existing_path):
            return existing_path

        records = self.logger.tail(500)
        day_records = [r for r in records if r.get("ts", "").startswith(today)]
        log_text = "\n".join(json.dumps(r, separators=(",", ":"))
                             for r in day_records) or "(no events today)"

        prompt = (
            "You are the nightly mining analyst. Summarize today's decision "
            "log: notable events, anomalies, thermal gates, profitability "
            "trend, and 1-3 concrete observations for tomorrow. Be factual; "
            "reference reason_codes. Output plain markdown.\n\n"
            f"TODAY'S DECISION LOG ({len(day_records)} events):\n{log_text}\n"
        )
        decision = self.admission.request(
            InferenceJob(prompt=prompt, model=self.reflect_model,
                         heavy=True, duration_est_s=120)
        )
        if not decision.admitted:
            self.logger.log(
                source="advisor", event="nightly_reflection_deferred",
                reason_code=decision.reason_code,
                detail={"events_pending": len(day_records)},
            )
            return None

        os.makedirs(REFLECTIONS_DIR, exist_ok=True)
        path = os.path.join(REFLECTIONS_DIR, f"{today}.md")
        content = _strip_thinking(decision.result) if decision.result else "(model returned no output)"
        with open(path, "w", encoding="utf-8") as f:
            f.write(f"# Mining Reflection — {today}\n\n{content}\n")
        self.logger.log(
            source="advisor", event="nightly_reflection",
            reason_code="REFLECT_COMPLETE",
            detail={"path": path, "events_analyzed": len(day_records)},
        )
        return path


# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------

def _print_response(resp: AdvisorResponse) -> None:
    print(f"\nAnswer:      {resp.answer}")
    print(f"Confidence:  {resp.confidence}")
    print(f"Valid:       {resp.valid}")
    if resp.evidence:
        print("Evidence:")
        for ev in resp.evidence:
            print(f"  - {ev}")
    if resp.fabricated_evidence:
        print(f"FABRICATED EVIDENCE DETECTED: {resp.fabricated_evidence}")
    if resp.proposed_action:
        print(f"Proposed action (requires ratification): {resp.proposed_action}")


def _audit(advisor: MiningAdvisor) -> int:
    """10-shot schema/grounding audit (Sprint 3 done criterion)."""
    questions = [
        "Why did hashrate drop most recently?",
        "What mode changes happened today?",
        "Were any inference jobs thermally queued?",
        "What was the last profitability calculation?",
        "How long did the last duty cycle take?",
        "Has the canary ever tripped?",
        "Which pool are we mining on and why?",
        "What did the bandit learn recently?",
        "Summarize the last five decisions.",
        "Is mining currently profitable after power costs?",
    ]
    passed = 0
    for i, q in enumerate(questions, 1):
        resp = advisor.answer(q)
        ok = resp.valid and not resp.fabricated_evidence
        passed += ok
        print(f"[{i}/10] {'PASS' if ok else 'FAIL'}  {q}")
    print(f"\nAudit: {passed}/10 valid, zero-fabrication responses")
    return 0 if passed >= 8 else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Mining advisor")
    parser.add_argument("--ask", type=str, help="Ask a question")
    parser.add_argument("--reflect", action="store_true",
                        help="Run nightly reflection (pauses mining)")
    parser.add_argument("--audit", action="store_true",
                        help="10-shot schema/grounding audit")
    args = parser.parse_args()

    advisor = MiningAdvisor()
    if args.ask:
        _print_response(advisor.answer(args.ask))
    elif args.reflect:
        path = advisor.nightly_reflect()
        if path:
            print(f"Reflection written: {path}")
        else:
            print("Deferred: thermal gate blocked the job. Retry later.")
            sys.exit(2)  # distinct exit code so a scheduler knows to retry
    elif args.audit:
        sys.exit(_audit(advisor))
    else:
        parser.print_help()
