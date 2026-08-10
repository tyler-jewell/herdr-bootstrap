#!/usr/bin/env python3
"""Unit tests for herdr-discover config parse (drives shipped parse_herdr_config)."""

import importlib.machinery
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent
DISCOVER = ROOT / "herdr-discover"


def load_discover():
    # herdr-discover has no .py suffix; use SourceFileLoader.
    loader = importlib.machinery.SourceFileLoader("herdr_discover", str(DISCOVER))
    return loader.load_module()


class TestParseHerdrConfig(unittest.TestCase):
    def test_wiki_table_does_not_raise(self):
        mod = load_discover()
        text = """
name = "demo"
enabled = true
agent_kind = "grok"
priority = 10

[wiki]
enabled = true
policy_version = 1
"""
        data = mod.parse_herdr_config(text)
        self.assertEqual(data["name"], "demo")
        self.assertTrue(data["enabled"])
        self.assertEqual(data["priority"], 10)

    def test_tabs_still_parse(self):
        mod = load_discover()
        text = """
name = "t"
[[tabs]]
name = "agents"
  [[tabs.panes]]
  name = "builder"
  agent = true
"""
        data = mod.parse_herdr_config(text)
        self.assertEqual(len(data["tabs"]), 1)
        self.assertEqual(data["tabs"][0]["name"], "agents")
        self.assertTrue(data["tabs"][0]["panes"][0]["agent"])


if __name__ == "__main__":
    unittest.main()
