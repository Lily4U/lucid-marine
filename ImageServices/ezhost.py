#!/usr/bin/env python3
"""ezhost.py — e-z.host image uploads for Lucid.

  ezhost.py upload <image>   send it, copy the link, notify
  ezhost.py set-key          save the API key (mode 600): from $EZ_HOST_NEW_KEY, else stdin
  ezhost.py clear-key        forget the saved key
  ezhost.py status           print JSON about the key; never the key itself

The key lives in ~/.config/lucid/secrets/e-z-host.key, not in prefs.json, so it is
never part of the shell's own settings file. $EZ_HOST_KEY, if set, wins over
the file. $EZ_HOST_URL and $EZ_HOST_KEY_FILE override the endpoint and the path.

stdlib only. needs wl-copy and notify-send at runtime, both optional: without
them the upload still works and the link is printed on stdout.
"""
import json
import mimetypes
import os
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

APP = "Lucid Screenshot"
URL = os.environ.get("EZ_HOST_URL", "https://api.e-z.host/files")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
KEY_FILE = os.environ.get("EZ_HOST_KEY_FILE", os.path.join(CONFIG, "lucid", "secrets", "e-z-host.key"))
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp", ".gif")
TIMEOUT = 60


def notify(title, body="", icon=None, critical=False):
    cmd = ["notify-send", "-a", APP]
    if critical:
        cmd += ["-u", "critical"]
    if icon:
        cmd += ["-i", icon]
    cmd += [title, body]
    try:
        subprocess.run(cmd, check=False, timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass


def fail(message):
    notify("Upload failed", message, critical=True)
    sys.stderr.write("ezhost: %s\n" % message)
    sys.exit(1)


def clean_key(raw):
    return "".join(raw.split())


def read_key():
    key = clean_key(os.environ.get("EZ_HOST_KEY", ""))
    if key:
        return key
    try:
        with open(KEY_FILE, encoding="utf-8") as f:
            return clean_key(f.readline())
    except OSError:
        return ""


def copy_to_clipboard(text):
    try:
        p = subprocess.Popen(["wl-copy"], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p.stdin.write(text.encode())
        p.stdin.close()
        p.wait(timeout=5)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def multipart(path):
    boundary = uuid.uuid4().hex
    name = os.path.basename(path).replace('"', "_").replace("\r", "_").replace("\n", "_")
    ctype = mimetypes.guess_type(path)[0] or "application/octet-stream"
    with open(path, "rb") as f:
        data = f.read()
    head = ('--%s\r\nContent-Disposition: form-data; name="file"; filename="%s"\r\n'
            'Content-Type: %s\r\n\r\n' % (boundary, name, ctype)).encode()
    tail = ("\r\n--%s--\r\n" % boundary).encode()
    return boundary, head + data + tail


def upload(path):
    if not path or not os.path.isfile(path):
        fail("no image to upload")
    if not path.lower().endswith(IMAGE_EXT):
        fail("only images can be uploaded")
    key = read_key()
    if not key:
        fail("no API key. add it in Settings, Image services")

    boundary, body = multipart(path)
    req = urllib.request.Request(URL, data=body, method="POST", headers={
        "key": key,
        "Content-Type": "multipart/form-data; boundary=" + boundary,
        "User-Agent": "lucid-ezhost/1",
    })
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        # an error status can still carry the server's own explanation
        raw = e.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError, TimeoutError):
        fail("could not reach the server")

    try:
        reply = json.loads(raw)
    except ValueError:
        fail("the server sent back something unreadable")
    if not isinstance(reply, dict):
        fail("the server sent back something unreadable")

    if reply.get("success") is not True:
        err = reply.get("error") or reply.get("message")
        fail(str(err) if err else "server said: " + raw[:200])
    link = reply.get("imageUrl")
    if not link:
        fail("the server did not return a link")

    copy_to_clipboard(link)
    notify("Link copied", link, icon=path)
    print(link)


def set_key():
    # the settings page hands the key over in the environment (not on the
    # command line, where ps would show it); by hand, pipe it through stdin
    key = clean_key(os.environ.get("EZ_HOST_NEW_KEY", ""))
    if not key:
        key = clean_key(sys.stdin.read())
    if not key:
        sys.stderr.write("ezhost: empty key, nothing saved\n")
        sys.exit(1)
    if len(key) > 512:
        sys.stderr.write("ezhost: that does not look like an API key\n")
        sys.exit(1)
    os.makedirs(os.path.dirname(KEY_FILE), mode=0o700, exist_ok=True)
    tmp = KEY_FILE + ".tmp"
    try:
        os.unlink(tmp)
    except OSError:
        pass
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(key + "\n")
    os.replace(tmp, KEY_FILE)


def clear_key():
    try:
        os.unlink(KEY_FILE)
    except FileNotFoundError:
        pass


def status():
    has = bool(clean_key(os.environ.get("EZ_HOST_KEY", ""))) or os.path.isfile(KEY_FILE)
    private = True
    if os.path.isfile(KEY_FILE):
        private = (os.stat(KEY_FILE).st_mode & 0o077) == 0
    print(json.dumps({"hasKey": has and bool(read_key()), "private": private,
                      "keyFile": KEY_FILE, "url": URL}))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "upload":
        upload(sys.argv[2] if len(sys.argv) > 2 else "")
    elif cmd == "set-key":
        set_key()
    elif cmd == "clear-key":
        clear_key()
    elif cmd == "status":
        status()
    else:
        sys.stderr.write(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
