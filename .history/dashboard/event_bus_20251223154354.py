"""
Lightweight Event-Driven Messaging for XMRig Mining Components
Zero external dependencies - Python stdlib only
"""

import json
import threading
import queue
import time
from dataclasses import dataclass, field, asdict
from enum import Enum
from pathlib import Path
from typing import Callable, Dict, List, Optional, Any
from datetime import datetime


class EventType(Enum):
    """Mining system event types."""
    HASHRATE_UPDATE = "hashrate_update"
    TEMP_UPDATE = "temp_update"
    SHARE_ACCEPTED = "share_accepted"
    SHARE_REJECTED = "share_rejected"
    COIN_SWITCH = "coin_switch"
    ALERT = "alert"
    HEALTH_STATUS = "health_status"
    POOL_CHANGE = "pool_change"


@dataclass
class MiningEvent:
    """Immutable event container for mining system messages."""
    type: EventType
    data: Dict[str, Any]
    source: str
    timestamp: float = field(default_factory=time.time)
    event_id: str = field(default_factory=lambda: f"{time.time_ns():x}")

    def to_dict(self) -> dict:
        return {
            "type": self.type.value,
            "data": self.data,
            "source": self.source,
            "timestamp": self.timestamp,
            "event_id": self.event_id
        }

    @classmethod
    def from_dict(cls, d: dict) -> "MiningEvent":
        return cls(
            type=EventType(d["type"]),
            data=d["data"],
            source=d["source"],
            timestamp=d["timestamp"],
            event_id=d["event_id"]
        )


class EventBus:
    """Thread-safe in-process pub/sub event bus using queue.Queue."""
    
    _instance: Optional["EventBus"] = None
    _lock = threading.Lock()

    def __new__(cls) -> "EventBus":
        """Singleton pattern for global event bus."""
        with cls._lock:
            if cls._instance is None:
                cls._instance = super().__new__(cls)
                cls._instance._initialized = False
            return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self._subscribers: Dict[EventType, List[Callable[[MiningEvent], None]]] = {}
        self._event_queue: queue.Queue = queue.Queue()
        self._running = False
        self._dispatcher_thread: Optional[threading.Thread] = None
        self._sub_lock = threading.Lock()
        self._initialized = True

    def subscribe(self, event_type: EventType, callback: Callable[[MiningEvent], None]) -> None:
        """Register a callback for an event type. Thread-safe."""
        with self._sub_lock:
            if event_type not in self._subscribers:
                self._subscribers[event_type] = []
            self._subscribers[event_type].append(callback)

    def unsubscribe(self, event_type: EventType, callback: Callable[[MiningEvent], None]) -> bool:
        """Remove a callback. Returns True if found and removed."""
        with self._sub_lock:
            if event_type in self._subscribers and callback in self._subscribers[event_type]:
                self._subscribers[event_type].remove(callback)
                return True
            return False

    def publish(self, event: MiningEvent) -> None:
        """Publish event to all subscribers. Non-blocking."""
        self._event_queue.put(event)

    def publish_now(self, event_type: EventType, data: dict, source: str) -> MiningEvent:
        """Convenience method to create and publish event."""
        event = MiningEvent(type=event_type, data=data, source=source)
        self.publish(event)
        return event

    def _dispatch_loop(self) -> None:
        """Background dispatcher thread."""
        while self._running:
            try:
                event = self._event_queue.get(timeout=0.1)
                with self._sub_lock:
                    callbacks = list(self._subscribers.get(event.type, []))
                for cb in callbacks:
                    try:
                        cb(event)
                    except Exception as e:
                        print(f"[EventBus] Callback error: {e}")
            except queue.Empty:
                continue

    def start(self) -> None:
        """Start the dispatcher thread."""
        if not self._running:
            self._running = True
            self._dispatcher_thread = threading.Thread(target=self._dispatch_loop, daemon=True)
            self._dispatcher_thread.start()

    def stop(self) -> None:
        """Stop the dispatcher thread."""
        self._running = False
        if self._dispatcher_thread:
            self._dispatcher_thread.join(timeout=1.0)


class FileEventLog:
    """File-based event persistence for cross-process communication."""
    
    def __init__(self, log_path: str = "logs/events.jsonl"):
        self.log_path = Path(log_path)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self._write_lock = threading.Lock()
        self._last_read_pos = 0

    def append(self, event: MiningEvent) -> None:
        """Append event to log file. Thread-safe."""
        with self._write_lock:
            with open(self.log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(event.to_dict()) + "\n")

    def read_new(self) -> List[MiningEvent]:
        """Read events added since last read (polling fallback)."""
        events = []
        if not self.log_path.exists():
            return events
        with open(self.log_path, "r", encoding="utf-8") as f:
            f.seek(self._last_read_pos)
            for line in f:
                if line.strip():
                    try:
                        events.append(MiningEvent.from_dict(json.loads(line)))
                    except (json.JSONDecodeError, KeyError):
                        continue
            self._last_read_pos = f.tell()
        return events

    def rotate(self, max_size_mb: float = 10.0) -> None:
        """Rotate log if too large."""
        if self.log_path.exists() and self.log_path.stat().st_size > max_size_mb * 1024 * 1024:
            backup = self.log_path.with_suffix(".jsonl.old")
            self.log_path.rename(backup)
            self._last_read_pos = 0


class HybridEventBus(EventBus):
    """EventBus with file-based fallback for cross-process scenarios."""
    
    def __init__(self, log_path: str = "logs/events.jsonl", persist: bool = True):
        super().__init__()
        self._file_log = FileEventLog(log_path) if persist else None

    def publish(self, event: MiningEvent) -> None:
        """Publish to in-memory bus and optionally persist."""
        super().publish(event)
        if self._file_log:
            self._file_log.append(event)

    def poll_file_events(self) -> List[MiningEvent]:
        """Poll for events from other processes via file log."""
        return self._file_log.read_new() if self._file_log else []


# === Integration Helpers ===

def create_xmrig_monitor_publisher(bus: EventBus, source: str = "xmrig_monitor"):
    """Factory for XMRig monitor event publisher."""
    def publish_hashrate(hashrate: float, accepted: int, rejected: int):
        bus.publish_now(EventType.HASHRATE_UPDATE, 
                       {"hashrate": hashrate, "accepted": accepted, "rejected": rejected}, source)
    def publish_temp(temp: float, fan_speed: int = 0):
        bus.publish_now(EventType.TEMP_UPDATE, {"temperature": temp, "fan": fan_speed}, source)
    def publish_alert(level: str, message: str):
        bus.publish_now(EventType.ALERT, {"level": level, "message": message}, source)
    return {"hashrate": publish_hashrate, "temp": publish_temp, "alert": publish_alert}


if __name__ == "__main__":
    # Demo: Event-driven mining system
    bus = HybridEventBus(persist=True)
    bus.start()

    # Dashboard subscriber
    def dashboard_handler(e: MiningEvent):
        print(f"[Dashboard] {e.type.value}: {e.data}")
    
    # Optimizer subscriber  
    def optimizer_handler(e: MiningEvent):
        if e.type == EventType.TEMP_UPDATE and e.data.get("temperature", 0) > 80:
            print(f"[Optimizer] High temp alert: {e.data['temperature']}C - throttling")

    bus.subscribe(EventType.HASHRATE_UPDATE, dashboard_handler)
    bus.subscribe(EventType.TEMP_UPDATE, dashboard_handler)
    bus.subscribe(EventType.TEMP_UPDATE, optimizer_handler)

    # Simulate XMRig monitor publishing events
    pub = create_xmrig_monitor_publisher(bus)
    pub["hashrate"](4521.5, 142, 2)
    pub["temp"](72.5, 65)
    pub["temp"](85.0, 100)  # Triggers optimizer alert
    pub["alert"]("warning", "Pool connection unstable")

    time.sleep(0.5)  # Let dispatcher process
    bus.stop()
    print(f"\n[Demo] Events persisted to: logs/events.jsonl")
