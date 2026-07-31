from __future__ import annotations

import os
import threading
import time
from collections import defaultdict, deque


class RateLimitExceeded(PermissionError):
    pass


class RateLimitService:
    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check_ai_request(self, app_user_id: str, client_ip: str) -> None:
        window = self._integer_env("AI_RATE_LIMIT_WINDOW_SECONDS", 60, 1, 3600)
        user_limit = self._integer_env("AI_RATE_LIMIT_USER_REQUESTS", 20, 1, 10000)
        ip_limit = self._integer_env("AI_RATE_LIMIT_IP_REQUESTS", 60, 1, 10000)
        now = time.monotonic()
        with self._lock:
            self._check_key(f"user:{app_user_id}", user_limit, window, now)
            self._check_key(f"ip:{client_ip}", ip_limit, window, now)

    def _check_key(self, key: str, limit: int, window: int, now: float) -> None:
        events = self._events[key]
        cutoff = now - window
        while events and events[0] <= cutoff:
            events.popleft()
        if len(events) >= limit:
            raise RateLimitExceeded("AI request rate limit exceeded")
        events.append(now)

    def _integer_env(self, name: str, default: int, minimum: int, maximum: int) -> int:
        try:
            value = int(os.environ.get(name, str(default)))
        except ValueError:
            value = default
        return max(minimum, min(value, maximum))
