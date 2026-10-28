"""Protocolo HID "V2" da EMEET (EMHidCmdV2 no EMEET STUDIO).

Report HID de 32 bytes (report ID 0x09), tanto na ida quanto na volta:

  byte 0     0x09            report ID (faz parte do cabeçalho do comando)
  byte 1     grupo           (3 bits altos = device type, 5 bits baixos = function type)
  byte 2     subgrupo
  byte 3     id do comando
  byte 4     índice do fragmento (0, 1, 2 ...)
  byte 5..6  tamanho total do payload (little-endian)
  byte 7     tamanho do payload neste fragmento (máx. 24)
  byte 8..31 payload

A resposta repete os 4 bytes de cabeçalho (o byte 1 pode vir com o device type
nos 3 bits altos; comparar com máscara 0x1f) e traz o payload fragmentado do
mesmo jeito. Para GET o payload é o valor; para SET o byte 0 do payload é o
código de resultado (0 = ok).
"""
import json
import os
import time

REPORT_ID = 0x09
REPORT_SIZE = 32
CHUNK = 24

VID = 0x328F   # EMEET
PID_PIXY = 0x00C0

_HERE = os.path.dirname(__file__)
with open(os.path.join(_HERE, "commands.json")) as f:
    COMMANDS = {k: bytes(v) for k, v in json.load(f).items()}

# Grupos que não fazem sentido mandar sem saber exatamente o que se está fazendo.
DANGEROUS = {"SET_START_UPG_DEVICE", "SET_START_UPG_MASTER", "SET_END_UPG_MASTER",
             "SET_END_UPG_DEVICE", "SET_FACTORY_RESET", "SET_SD_FORMAT",
             "SET_CONFIG_PASSWD", "SET_DEVICE_VER"}


class PixyError(Exception):
    pass


class Timeout(PixyError):
    pass


# Device types (3 bits altos do byte 1). 0 = câmera principal, 3 = gimbal/motor.
DEV_MAIN = 0
DEV_GIMBAL = 3

# Comandos que o EMEET STUDIO sempre manda para o device type 3 (gimbal).
GIMBAL_COMMANDS = {n for n in COMMANDS if n.startswith(("SET_MOTOR", "GET_MOTOR", "SET_GIMBAL", "GET_GIMBAL"))}


def head_of(name: str, device_type=None) -> bytes:
    try:
        h = bytearray(COMMANDS[name])
    except KeyError:
        raise PixyError(f"comando desconhecido: {name}") from None
    if device_type is None:
        device_type = DEV_GIMBAL if name in GIMBAL_COMMANDS else DEV_MAIN
    h[1] = ((device_type & 0x7) << 5) | (h[1] & 0x1F)
    return bytes(h)


def build_reports(head: bytes, payload: bytes = b"") -> list:
    """Fragmenta o payload em reports de 32 bytes, igual ao EMHidCmdHelper::hidCmdSend."""
    total = len(payload)
    reports = []
    if total == 0:
        rep = bytearray(REPORT_SIZE)
        rep[0:4] = head
        rep[5] = 0
        rep[6] = 0
        rep[7] = 0
        return [bytes(rep)]
    idx = 0
    off = 0
    while off < total:
        n = min(CHUNK, total - off)
        rep = bytearray(REPORT_SIZE)
        rep[0:4] = head
        rep[4] = idx
        rep[5] = total & 0xFF
        rep[6] = (total >> 8) & 0xFF
        rep[7] = n
        rep[8:8 + n] = payload[off:off + n]
        reports.append(bytes(rep))
        off += n
        idx += 1
    return reports


def head_matches(head: bytes, rep: bytes) -> bool:
    return (rep[0] == head[0] and (rep[1] & 0x1F) == (head[1] & 0x1F)
            and rep[2] == head[2] and rep[3] == head[3])


class Pixy:
    """Sessão HID com a câmera. Uso: with Pixy.open() as cam: cam.get('GET_VER')"""

    def __init__(self, dev, verbose=False):
        self.dev = dev
        self.verbose = verbose

    @classmethod
    def find(cls, vid=VID, pid=0):
        from . import hidapi
        devs = [d for d in hidapi.enumerate(vid, pid) if d["usage_page"] >= 0x80 or d["usage_page"] == 0x83]
        if not devs:
            devs = hidapi.enumerate(vid, pid)
        return devs

    @classmethod
    def open(cls, vid=VID, pid=0, verbose=False):
        from . import hidapi
        devs = cls.find(vid, pid)
        if not devs:
            raise PixyError("nenhum dispositivo EMEET HID encontrado (câmera conectada? EMEET STUDIO fechado?)")
        return cls(hidapi.HidDevice(devs[0]["path"]), verbose=verbose)

    def close(self):
        self.dev.close()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def _log(self, tag, data):
        if self.verbose:
            print(f"  {tag} {data.hex(' ')}")

    def drain(self):
        """Descarta reports pendentes (a câmera pode emitir eventos espontâneos)."""
        while True:
            r = self.dev.read(REPORT_SIZE, 5)
            if not r:
                return
            self._log("<- (descartado)", r)

    def send(self, name: str, payload: bytes = b"", timeout_s: float = 1.0, allow_dangerous=False,
             device_type=None) -> bytes:
        """Envia o comando e devolve o payload da resposta (sem o cabeçalho)."""
        if name in DANGEROUS and not allow_dangerous:
            raise PixyError(f"{name} está bloqueado por segurança (use --eu-sei-o-que-estou-fazendo)")
        head = head_of(name, device_type)
        self.drain()
        for rep in build_reports(head, payload):
            self._log("->", rep)
            self.dev.write(rep)

        deadline = time.monotonic() + timeout_s
        total = None
        got = bytearray()
        expect_idx = 0
        while time.monotonic() < deadline:
            r = self.dev.read(REPORT_SIZE, 50)
            if not r:
                continue
            self._log("<-", r)
            if len(r) < 8 or r[0] != REPORT_ID:
                continue
            if not head_matches(head, r):
                # evento ou resposta de outro comando: ignora
                continue
            idx, lo, hi, n = r[4], r[5], r[6], r[7]
            if total is None:
                if idx != 0:
                    continue
                total = lo | (hi << 8)
            elif idx != expect_idx:
                raise PixyError(f"fragmento fora de ordem: esperava {expect_idx}, veio {idx}")
            got += r[8:8 + n]
            expect_idx += 1
            if len(got) >= total:
                return bytes(got[:total])
        raise Timeout(f"sem resposta para {name} em {timeout_s}s")

    # atalhos
    def get(self, name, payload=b"", **kw):
        return self.send(name, payload, **kw)

    def set(self, name, payload: bytes, **kw) -> int:
        resp = self.send(name, payload, **kw)
        return resp[0] if resp else -1
