#!/usr/bin/env python3
"""Host tests mirroring plugin/kindleanki.koplugin/schedule.lua."""

from __future__ import annotations

import unittest


MAX_INTERVAL_DAYS = 36500


def clamp_interval(value: float) -> int:
    value = int(value)
    if value > MAX_INTERVAL_DAYS:
        return MAX_INTERVAL_DAYS
    if value < 1:
        return 1
    return value


def next_interval(interval: int, rating: str) -> int:
    base = interval
    if rating == "again":
        return 0
    if rating == "hard":
        return clamp_interval(1 if base == 0 else base * 6 / 5 + 1)
    if rating == "good":
        return clamp_interval(1 if base == 0 else base * 5 / 2 + 1)
    if rating == "easy":
        return clamp_interval(4 if base == 0 else base * 7 / 2 + 1)
    return base


def preview_days(interval: int, rating: str) -> int:
    if rating == "again":
        return 0
    return next_interval(interval, rating)


AGAIN_SECONDS = 10 * 60


def apply(state: dict, rating: str, today: int, as_extra: bool = False, now: int = 0) -> dict:
    was_new = state["reps"] == 0 and state["lapses"] == 0
    if rating == "again":
        state["interval"] = 0
        state["lapses"] += 1
        state["due"] = today
        state["due_at"] = now + AGAIN_SECONDS
    else:
        state["interval"] = next_interval(state["interval"], rating)
        state["reps"] += 1
        state["due"] = today + state["interval"]
        state["due_at"] = None
    state["last_rating"] = rating
    if as_extra:
        state["extra"] = True
    state["_was_new"] = was_new
    return state


def is_due(state: dict, today: int, now: int) -> bool:
    if state["reps"] == 0 and state["lapses"] == 0:
        return False
    due_at = state.get("due_at")
    if due_at is not None and due_at > now:
        return False
    return state["due"] <= today


def option_letter(index: int) -> str:
    label = ""
    while index > 0:
        remainder = (index - 1) % 26
        label = chr(65 + remainder) + label
        index = (index - 1) // 26
    return label


def selected_labels(selected) -> list[str]:
    if isinstance(selected, dict):
        return sorted(option_letter(index) for index, is_selected in selected.items() if is_selected)
    return sorted(option_letter(index) for index in selected)


class KindleScheduleTests(unittest.TestCase):
    def test_new_card_previews(self) -> None:
        self.assertEqual(preview_days(0, "again"), 0)
        self.assertEqual(preview_days(0, "hard"), 1)
        self.assertEqual(preview_days(0, "good"), 1)
        self.assertEqual(preview_days(0, "easy"), 4)

    def test_again_stays_due_today(self) -> None:
        state = {"due": 0, "interval": 0, "reps": 0, "lapses": 0}
        apply(state, "good", today=100)
        apply(state, "again", today=101, now=1000)
        self.assertEqual(state["due"], 101)
        self.assertEqual(state["interval"], 0)
        self.assertEqual(state["lapses"], 1)
        self.assertEqual(state["due_at"], 1000 + AGAIN_SECONDS)

    def test_again_is_not_due_for_ten_minutes(self) -> None:
        state = {"due": 0, "interval": 0, "reps": 1, "lapses": 0, "due_at": None}
        apply(state, "again", today=50, now=2000)
        self.assertFalse(is_due(state, today=50, now=2000))
        self.assertFalse(is_due(state, today=50, now=2000 + AGAIN_SECONDS - 1))
        self.assertTrue(is_due(state, today=50, now=2000 + AGAIN_SECONDS))

    def test_extra_flag_does_not_change_math(self) -> None:
        a = {"due": 0, "interval": 0, "reps": 0, "lapses": 0}
        b = {"due": 0, "interval": 0, "reps": 0, "lapses": 0}
        apply(a, "good", today=10, as_extra=False)
        apply(b, "good", today=10, as_extra=True)
        self.assertEqual(a["due"], b["due"])
        self.assertEqual(a["interval"], b["interval"])
        self.assertTrue(b["extra"])

    def test_daily_quota_change_affects_remaining_not_extra(self) -> None:
        def remaining(daily_new: int, new_done: int) -> int:
            return max(0, daily_new - new_done)

        self.assertEqual(remaining(20, 0), 20)
        self.assertEqual(remaining(20, 20), 0)
        self.assertEqual(remaining(30, 20), 10)
        self.assertEqual(remaining(10, 20), 0)

    def test_choice_letters_use_one_based_selection_and_zero_based_correct(self) -> None:
        self.assertEqual(option_letter(1), "A")
        self.assertEqual(option_letter(2), "B")
        self.assertEqual(selected_labels({1: True}), ["A"])
        self.assertEqual(selected_labels({2: True}), ["B"])
        self.assertEqual(selected_labels([2]), ["B"])
        self.assertEqual(option_letter(0 + 1), "A")
        self.assertEqual(option_letter(1 + 1), "B")

    def test_empty_study_queue_is_the_extra_prompt(self) -> None:
        def study_empty(due_count: int, new_remaining: int) -> bool:
            return due_count + new_remaining == 0

        self.assertFalse(study_empty(3, 0))
        self.assertFalse(study_empty(0, 5))
        self.assertTrue(study_empty(0, 0))


if __name__ == "__main__":
    unittest.main()
