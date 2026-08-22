#!/usr/bin/env python3
"""Small privacy-first controller for OBS WebSocket v5."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys

import obsws_python as obs


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def client() -> obs.ReqClient:
    password_file = Path(env("STREAMING_OBS_PASSWORD_FILE", ""))
    if not password_file.is_file():
        raise RuntimeError(f"OBS WebSocket password file is not readable: {password_file}")
    password = password_file.read_text(encoding="utf-8")
    if password.endswith("\n"):
        password = password[:-1]
        if password.endswith("\r"):
            password = password[:-1]
    if not password:
        raise RuntimeError(f"OBS WebSocket password file is empty: {password_file}")
    return obs.ReqClient(
        host=env("STREAMING_OBS_HOST", "127.0.0.1"),
        port=int(env("STREAMING_OBS_PORT", "4455")),
        password=password,
        timeout=float(env("STREAMING_OBS_TIMEOUT", "3")),
    )


def clean_recording_request(ws: obs.ReqClient, request: str) -> None:
    response = ws.call_vendor_request(
        "source-record",
        request,
        {
            "source": "[Component] Primary Monitor",
            "filter": "Clean Recording",
        },
    )
    response_data = response.response_data or {}
    if not response_data.get("success", False):
        message = response_data.get("error", "Source Record rejected the request")
        raise RuntimeError(message)


def run(args: argparse.Namespace) -> None:
    ws = client()
    if args.command == "scene":
        scenes = {
            "live": env("STREAMING_OBS_LIVE_SCENE", "Programming"),
            "second": env("STREAMING_OBS_SECOND_SCENE", "Second Monitor"),
            "privacy": env("STREAMING_OBS_PRIVACY_SCENE", "Privacy"),
            "brb": env("STREAMING_OBS_BRB_SCENE", "BRB"),
            "starting": env("STREAMING_OBS_STARTING_SCENE", "Starting Soon"),
        }
        ws.set_current_program_scene(scenes[args.target])
        if args.target == "privacy":
            if env("STREAMING_OBS_PRIVACY_MUTE_MIC", "1") == "1":
                ws.set_input_mute("Microphone", True)
            if env("STREAMING_OBS_PRIVACY_STOP_CLEAN_RECORDING", "1") == "1":
                try:
                    clean_recording_request(ws, "record_stop")
                except Exception as error:  # Privacy scene already succeeded.
                    print(f"warning: could not stop clean recording: {error}", file=sys.stderr)
        return

    if args.command == "stream":
        getattr(ws, f"{args.action}_stream")()
    elif args.command == "record":
        getattr(ws, f"{args.action}_record")()
    elif args.command == "mic":
        if args.action == "toggle":
            ws.toggle_input_mute("Microphone")
        else:
            ws.set_input_mute("Microphone", args.action == "mute")
    elif args.command == "clean-record":
        request = "record_start" if args.action == "start" else "record_stop"
        clean_recording_request(ws, request)
    elif args.command == "callout":
        ws.set_input_settings("Keystroke Display", {"text": args.text}, True)
    elif args.command == "chapter":
        ws.create_record_chapter(args.name)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)

    scene = commands.add_parser("scene")
    scene.add_argument("target", choices=["live", "second", "privacy", "brb", "starting"])

    for command in ("stream", "record"):
        sub = commands.add_parser(command)
        sub.add_argument("action", choices=["start", "stop", "toggle"])

    mic = commands.add_parser("mic")
    mic.add_argument("action", choices=["mute", "unmute", "toggle"])

    clean = commands.add_parser("clean-record")
    clean.add_argument("action", choices=["start", "stop"])

    callout = commands.add_parser("callout")
    callout.add_argument("text")

    chapter = commands.add_parser("chapter")
    chapter.add_argument("name", nargs="?", default=None)
    return result


if __name__ == "__main__":
    try:
        run(parser().parse_args())
    except Exception as error:
        print(f"streaming-obs-control: {error}", file=sys.stderr)
        raise SystemExit(1) from error
