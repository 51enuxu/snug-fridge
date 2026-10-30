"""JSON 文件存储: 一份冰箱快照。线程安全 + 原子写 (写临时文件再 rename)。"""
import json
import os
import tempfile
import threading

DATA_FILE = os.environ.get('FRIDGE_DATA_FILE') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fridge_data.json')
_lock = threading.RLock()


def read():
    """返回快照 dict; 从没写过返回 None"""
    with _lock:
        try:
            with open(DATA_FILE, encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            return None
        except json.JSONDecodeError as e:
            raise RuntimeError(f'数据文件损坏: {e}')


def write(snapshot):
    with _lock:
        d = os.path.dirname(os.path.abspath(DATA_FILE))
        fd, tmp = tempfile.mkstemp(dir=d, prefix='.fridge-', suffix='.tmp')
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                json.dump(snapshot, f, ensure_ascii=False, indent=1)
            os.replace(tmp, DATA_FILE)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
