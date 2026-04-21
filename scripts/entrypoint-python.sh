#!/bin/sh
# No "set -e" here: Windows CRLF or BOM breaks dash on bind mounts. Use explicit || exit 1.
# Image USER is node; named volume /opt/python is often root-owned until chown.

PYTHON_HOME="/opt/python"
PYTHON_SRC="/opt/python-src"
LOCKFILE="/opt/python/.copying.lock"

prepare_python() {
  if [ -f "$PYTHON_HOME/bin/python3" ] && [ -f "$PYTHON_HOME/.ready" ]; then
    return 0
  fi

  if mkdir "$LOCKFILE" 2>/dev/null; then
    trap 'rm -rf "$LOCKFILE"' EXIT

    echo "Initializing standalone Python into named volume..."
    if [ -d "$PYTHON_HOME" ]; then
      find "$PYTHON_HOME" -mindepth 1 -delete 2>/dev/null || true
    fi

    if [ ! -f "$PYTHON_SRC/bin/python3" ]; then
      echo "ERROR: standalone source not found at $PYTHON_SRC"
      echo "Run setup-openclaw.bat and choose with-python first."
      exit 1
    fi

    cp -a "$PYTHON_SRC/"* "$PYTHON_HOME/" || exit 1
    chmod -R +x "$PYTHON_HOME/bin" 2>/dev/null || true
    touch "$PYTHON_HOME/.ready"
    echo "Python seed copied; starting gateway process next."
  else
    echo "Waiting for Python copy to finish..."
    while [ -d "$LOCKFILE" ]; do sleep 1; done
  fi
}

prepare_python || exit 1

export PATH="$PYTHON_HOME/bin:$PATH"
export PYTHON_HOME
export PYTHON_PATH="$PYTHON_HOME/bin/python3"
if [ -f "$PYTHON_HOME/etc/pip.conf" ]; then
  export PIP_CONFIG_FILE="$PYTHON_HOME/etc/pip.conf"
fi

if [ "$(id -u)" = 0 ]; then
  chown -R node:node "$PYTHON_HOME" 2>/dev/null || true
fi

exec_as_node() {
  if [ "$(id -u)" != 0 ]; then
    exec "$@"
  fi
  if command -v runuser >/dev/null 2>&1; then
    exec runuser -u node -- "$@"
  fi
  if command -v setpriv >/dev/null 2>&1; then
    exec setpriv --reuid=1000 --regid=1000 --init-groups -- "$@"
  fi
  echo "ERROR: need runuser or setpriv to drop to node (util-linux)" >&2
  exit 1
}

exec_as_node "$@"
