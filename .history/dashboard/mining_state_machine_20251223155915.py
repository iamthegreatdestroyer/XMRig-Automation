"""
Deterministic Finite State Machine for XMRig Mining Control.
Manages mining states with persistence across reboots.
"""

import json
import time
from enum import Enum
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Callable, Optional, Any
from datetime import datetime


class MiningState(Enum):
    """Mining operation states."""
    IDLE = "idle"
    WARMUP = "warmup"
    MINING = "mining"
    THROTTLE = "throttle"
    COOLDOWN = "cooldown"
    ERROR = "error"
    PAUSED = "paused"


@dataclass
class StateTransition:
    """Defines a state transition with condition and action."""
    from_state: MiningState
    to_state: MiningState
    condition: str  # Expression like "temp > 80", "hashrate > 0"
    action: Optional[str] = None  # Action name to execute on transition
    priority: int = 0  # Higher priority transitions checked first


@dataclass
class StateInfo:
    """Current state information for dashboard display."""
    state: str
    state_entry_time: float
    duration_seconds: float
    transition_count: int
    last_transition: Optional[str]
    last_event: Optional[dict]


class MiningStateMachine:
    """Deterministic FSM for mining control with JSON persistence."""
    
    DEFAULT_STATE_FILE = "mining_state.json"
    COOLDOWN_PERIOD = 60  # seconds
    
    def __init__(self, state_file: Optional[Path] = None):
        self.state_file = Path(state_file) if state_file else Path(__file__).parent / self.DEFAULT_STATE_FILE
        self._state = MiningState.IDLE
        self._state_entry_time = time.time()
        self._transition_count = 0
        self._last_transition: Optional[str] = None
        self._last_event: Optional[dict] = None
        self._actions: dict[str, Callable] = {}
        self._transitions = self._build_default_transitions()
        self._load_state()
    
    def _build_default_transitions(self) -> list[StateTransition]:
        """Build default transition table."""
        return [
            # Priority transitions (checked first)
            StateTransition(MiningState.IDLE, MiningState.ERROR, "error", "on_error", 100),
            StateTransition(MiningState.WARMUP, MiningState.ERROR, "error", "on_error", 100),
            StateTransition(MiningState.MINING, MiningState.ERROR, "error", "on_error", 100),
            StateTransition(MiningState.THROTTLE, MiningState.ERROR, "error", "on_error", 100),
            StateTransition(MiningState.COOLDOWN, MiningState.ERROR, "error", "on_error", 100),
            
            # User pause (high priority)
            StateTransition(MiningState.MINING, MiningState.PAUSED, "user_active", "on_pause", 90),
            StateTransition(MiningState.WARMUP, MiningState.PAUSED, "user_active", "on_pause", 90),
            StateTransition(MiningState.THROTTLE, MiningState.PAUSED, "user_active", "on_pause", 90),
            
            # Normal transitions
            StateTransition(MiningState.IDLE, MiningState.WARMUP, "miner_start", "on_warmup", 10),
            StateTransition(MiningState.WARMUP, MiningState.MINING, "hashrate > 0", "on_mining", 10),
            StateTransition(MiningState.MINING, MiningState.THROTTLE, "temp > 80", "on_throttle", 20),
            StateTransition(MiningState.THROTTLE, MiningState.COOLDOWN, "temp < 70", "on_cooldown", 10),
            StateTransition(MiningState.COOLDOWN, MiningState.MINING, "cooldown_complete", "on_mining", 10),
            
            # Recovery transitions
            StateTransition(MiningState.PAUSED, MiningState.MINING, "user_inactive", "on_mining", 10),
            StateTransition(MiningState.ERROR, MiningState.IDLE, "error_cleared", "on_idle", 10),
        ]
    
    def _load_state(self) -> None:
        """Load persisted state from JSON file."""
        if self.state_file.exists():
            try:
                with open(self.state_file, 'r') as f:
                    data = json.load(f)
                self._state = MiningState(data.get("state", "idle"))
                self._state_entry_time = data.get("state_entry_time", time.time())
                self._transition_count = data.get("transition_count", 0)
                self._last_transition = data.get("last_transition")
            except (json.JSONDecodeError, ValueError, KeyError):
                self._state = MiningState.IDLE
                self._state_entry_time = time.time()
    
    def _save_state(self) -> None:
        """Persist current state to JSON file."""
        data = {
            "state": self._state.value,
            "state_entry_time": self._state_entry_time,
            "transition_count": self._transition_count,
            "last_transition": self._last_transition,
            "saved_at": datetime.now().isoformat()
        }
        with open(self.state_file, 'w') as f:
            json.dump(data, f, indent=2)
    
    def _evaluate_condition(self, condition: str, event_data: dict) -> bool:
        """Evaluate transition condition against event data."""
        # Simple boolean flags
        if condition in event_data:
            return bool(event_data[condition])
        
        # Cooldown period check
        if condition == "cooldown_complete":
            elapsed = time.time() - self._state_entry_time
            return elapsed >= self.COOLDOWN_PERIOD
        
        # Comparison expressions: "temp > 80", "hashrate > 0"
        for op in ['>=', '<=', '>', '<', '==', '!=']:
            if op in condition:
                parts = condition.split(op)
                if len(parts) == 2:
                    var_name = parts[0].strip()
                    threshold = float(parts[1].strip())
                    if var_name in event_data:
                        value = float(event_data[var_name])
                        return eval(f"{value} {op} {threshold}")
        return False
    
    def _execute_action(self, action_name: Optional[str]) -> None:
        """Execute registered action callback."""
        if action_name and action_name in self._actions:
            self._actions[action_name](self._state)
    
    def register_action(self, name: str, callback: Callable[[MiningState], None]) -> None:
        """Register an action callback for transitions."""
        self._actions[name] = callback
    
    def process_event(self, event_data: dict) -> Optional[MiningState]:
        """Process event and transition if conditions met. Returns new state or None."""
        self._last_event = event_data
        
        # Sort transitions by priority (highest first)
        applicable = [t for t in self._transitions if t.from_state == self._state]
        applicable.sort(key=lambda t: t.priority, reverse=True)
        
        for transition in applicable:
            if self._evaluate_condition(transition.condition, event_data):
                old_state = self._state
                self._state = transition.to_state
                self._state_entry_time = time.time()
                self._transition_count += 1
                self._last_transition = f"{old_state.value} -> {transition.to_state.value}"
                self._execute_action(transition.action)
                self._save_state()
                return self._state
        return None
    
    def force_state(self, new_state: MiningState) -> None:
        """Force transition to a specific state (for recovery/testing)."""
        old_state = self._state
        self._state = new_state
        self._state_entry_time = time.time()
        self._transition_count += 1
        self._last_transition = f"{old_state.value} -> {new_state.value} (forced)"
        self._save_state()
    
    def get_state_info(self) -> StateInfo:
        """Get current state information for dashboard display."""
        return StateInfo(
            state=self._state.value,
            state_entry_time=self._state_entry_time,
            duration_seconds=time.time() - self._state_entry_time,
            transition_count=self._transition_count,
            last_transition=self._last_transition,
            last_event=self._last_event
        )
    
    @property
    def state(self) -> MiningState:
        """Current mining state."""
        return self._state
    
    @property
    def state_duration(self) -> float:
        """Seconds in current state."""
        return time.time() - self._state_entry_time
    
    def add_transition(self, transition: StateTransition) -> None:
        """Add a custom transition to the table."""
        self._transitions.append(transition)


if __name__ == "__main__":
    # Demo usage
    fsm = MiningStateMachine()
    
    def log_action(state: MiningState):
        print(f"  [ACTION] Entered {state.value}")
    
    for action in ["on_warmup", "on_mining", "on_throttle", "on_cooldown", "on_pause", "on_error", "on_idle"]:
        fsm.register_action(action, log_action)
    
    print("=== Mining State Machine Demo ===")
    print(f"Initial: {fsm.state.value}")
    
    events = [
        {"miner_start": True},
        {"hashrate": 4500, "temp": 65},
        {"hashrate": 4200, "temp": 85},
        {"hashrate": 3000, "temp": 68},
    ]
    
    for event in events:
        print(f"\nEvent: {event}")
        result = fsm.process_event(event)
        info = fsm.get_state_info()
        print(f"  State: {info.state} | Duration: {info.duration_seconds:.1f}s | Transitions: {info.transition_count}")
