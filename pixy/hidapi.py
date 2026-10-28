"""Wrapper ctypes mínimo para libhidapi (Homebrew). Sem dependências pip."""
import ctypes as C
import ctypes.util
import os

_CANDIDATES = [
    os.environ.get("PIXY_HIDAPI", ""),
    "/opt/homebrew/lib/libhidapi.dylib",
    "/usr/local/lib/libhidapi.dylib",
    ctypes.util.find_library("hidapi") or "",
]


def _load():
    for p in _CANDIDATES:
        if p and os.path.exists(p):
            return C.CDLL(p)
    raise OSError("libhidapi não encontrada. Instale com: brew install hidapi")


_lib = _load()


class _DeviceInfo(C.Structure):
    pass


_DeviceInfo._fields_ = [
    ("path", C.c_char_p),
    ("vendor_id", C.c_ushort),
    ("product_id", C.c_ushort),
    ("serial_number", C.c_wchar_p),
    ("release_number", C.c_ushort),
    ("manufacturer_string", C.c_wchar_p),
    ("product_string", C.c_wchar_p),
    ("usage_page", C.c_ushort),
    ("usage", C.c_ushort),
    ("interface_number", C.c_int),
    ("next", C.POINTER(_DeviceInfo)),
]

_lib.hid_init.restype = C.c_int
_lib.hid_exit.restype = C.c_int
_lib.hid_enumerate.restype = C.POINTER(_DeviceInfo)
_lib.hid_enumerate.argtypes = [C.c_ushort, C.c_ushort]
_lib.hid_free_enumeration.argtypes = [C.POINTER(_DeviceInfo)]
_lib.hid_open_path.restype = C.c_void_p
_lib.hid_open_path.argtypes = [C.c_char_p]
_lib.hid_write.restype = C.c_int
_lib.hid_write.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t]
_lib.hid_read_timeout.restype = C.c_int
_lib.hid_read_timeout.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t, C.c_int]
_lib.hid_close.argtypes = [C.c_void_p]
_lib.hid_error.restype = C.c_wchar_p
_lib.hid_error.argtypes = [C.c_void_p]

_lib.hid_init()

# hidapi >= 0.12: abrir sem exclusividade, para conviver com o PixyBar (IOHIDManager, não exclusivo).
try:
    _lib.hid_darwin_set_open_exclusive.argtypes = [C.c_int]
    _lib.hid_darwin_set_open_exclusive(1 if os.environ.get("PIXY_EXCLUSIVE") else 0)
except AttributeError:
    pass


def enumerate(vid=0, pid=0):
    """Lista dispositivos HID como dicts."""
    out = []
    head = _lib.hid_enumerate(vid, pid)
    cur = head
    while cur:
        d = cur.contents
        out.append({
            "path": d.path.decode(),
            "vid": d.vendor_id,
            "pid": d.product_id,
            "serial": d.serial_number,
            "manufacturer": d.manufacturer_string,
            "product": d.product_string,
            "usage_page": d.usage_page,
            "usage": d.usage,
            "interface": d.interface_number,
        })
        cur = d.next
    if head:
        _lib.hid_free_enumeration(head)
    return out


class HidDevice:
    def __init__(self, path: str):
        self._h = _lib.hid_open_path(path.encode())
        if not self._h:
            raise OSError(f"hid_open_path falhou: {_lib.hid_error(None)}")

    def write(self, data: bytes) -> int:
        n = _lib.hid_write(self._h, data, len(data))
        if n < 0:
            raise OSError(f"hid_write falhou: {_lib.hid_error(self._h)}")
        return n

    def read(self, size: int, timeout_ms: int) -> bytes:
        buf = C.create_string_buffer(size)
        n = _lib.hid_read_timeout(self._h, buf, size, timeout_ms)
        if n < 0:
            raise OSError(f"hid_read falhou: {_lib.hid_error(self._h)}")
        return buf.raw[:n]

    def close(self):
        if self._h:
            _lib.hid_close(self._h)
            self._h = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()
