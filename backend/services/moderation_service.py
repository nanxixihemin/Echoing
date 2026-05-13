from __future__ import annotations

import os
from dataclasses import dataclass


DEFAULT_BLOCK_KEYWORDS = [
    "suicide",
    "self-harm",
    "kill myself",
    "terrorism",
    "gambling",
    "drug",
    "porn",
    "诈骗",
    "赌博",
    "毒品",
    "色情",
    "自杀",
    "轻生",
]


@dataclass(frozen=True)
class ModerationResult:
    flag: str
    reason: str


class ModerationService:
    def __init__(self) -> None:
        configured = os.environ.get("MODERATION_BLOCK_KEYWORDS", "")
        configured_keywords = [item.strip() for item in configured.split(",") if item.strip()]
        self.block_keywords = configured_keywords or DEFAULT_BLOCK_KEYWORDS

    def review_text(self, content: str) -> ModerationResult:
        normalized = content.lower()
        for keyword in self.block_keywords:
            if keyword.lower() in normalized:
                return ModerationResult("blocked", f"blocked keyword: {keyword}")
        return ModerationResult("clean", "")
