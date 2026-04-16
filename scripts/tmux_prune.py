#!/usr/bin/env python3
import libtmux
import os

def main() -> None:
    socket = f"/tmp/tmux-{os.geteuid()}/default"
    server = libtmux.Server(socket_path=socket)
    print(socket)

    killed = 0

    for session in server.sessions:
        # tmux exposes `session_attached` as a field
        attached = int(session.get("session_attached", "0"))
        if attached == 0:
            print(f"Killing detached session: {session.name}")
            session.kill()
            killed += 1

    if killed == 0:
        print("No detached sessions to prune.")
    else:
        print(f"Pruned {killed} session(s).")

if __name__ == "__main__":
    main()
