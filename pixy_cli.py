#!/usr/bin/env python3
"""CLI de validação do protocolo HID da EMEET PIXY.

  python3 pixy_cli.py devices                  lista dispositivos HID EMEET
  python3 pixy_cli.py list [filtro]            lista comandos conhecidos
  python3 pixy_cli.py info                     versão, SN, alias, status
  python3 pixy_cli.py get NOME [hexpayload]    manda um GET e mostra a resposta
  python3 pixy_cli.py set NOME hexpayload      manda um SET e mostra o código
  python3 pixy_cli.py raw 09 04 00 13 [hex]    cabeçalho explícito
  python3 pixy_cli.py scan [grupo]             tenta todos os GET sem payload
  python3 pixy_cli.py monitor [segundos]       mostra reports espontâneos
  python3 pixy_cli.py pos pan|tilt [graus]    lê ou posiciona o motor (absoluto)
  python3 pixy_cli.py gesture N [on|off]      reconhecimento de gesto tipo N (0-3 na PIXY)
  python3 pixy_cli.py flip h|v [on|off]       espelhamento horizontal/vertical
  python3 pixy_cli.py preset N                vai para a posição preset N

Flags: -v (bytes na tela), --dev N (device type), --eu-sei-o-que-estou-fazendo
"""
import sys
import struct
from pixy import hidapi
from pixy.protocol import Pixy, COMMANDS, DANGEROUS, PixyError, Timeout, VID, head_matches, REPORT_SIZE
from pixy.api import PixyApi


def hx(b):
    return b.hex(" ") if b else "(vazio)"


def main(argv):
    verbose = "-v" in argv
    allow = "--eu-sei-o-que-estou-fazendo" in argv
    dev_type = None
    if "--dev" in argv:
        i = argv.index("--dev"); dev_type = int(argv[i + 1]); del argv[i:i + 2]
    argv = [a for a in argv if a not in ("-v", "--eu-sei-o-que-estou-fazendo")]
    if not argv:
        print(__doc__); return 1
    cmd, args = argv[0], argv[1:]

    if cmd == "devices":
        for d in hidapi.enumerate(VID, 0):
            print(f"vid={d['vid']:04x} pid={d['pid']:04x} usage_page={d['usage_page']:#06x} usage={d['usage']:#06x} "
                  f"iface={d['interface']} sn={d['serial']} product={d['product']}")
        return 0

    if cmd == "list":
        f = args[0].upper() if args else ""
        for n, h in COMMANDS.items():
            if f in n:
                print(f"{h.hex(' ')}  {n}{'   [BLOQUEADO]' if n in DANGEROUS else ''}")
        return 0

    with Pixy.open(verbose=verbose) as cam:
        api = PixyApi(cam)
        kw = {"allow_dangerous": allow}
        if dev_type is not None:
            kw["device_type"] = dev_type

        if cmd == "info":
            for label, fn in [("versão fw (main)", lambda: api.version(0)),
                              ("versão fw (gimbal)", lambda: api.version(3)),
                              ("SN", lambda: api.serial(0)),
                              ("device ver", lambda: hx(api.device_ver())),
                              ("alias", api.alias),
                              ("func sta", lambda: hx(api.func_sta())),
                              ("HDR", api.get_hdr), ("low light", api.get_low_light),
                              ("gimbal mode", api.get_gimbal_mode),
                              ("mic mute", api.get_mic_mute), ("denoise", api.get_denoise)]:
                try:
                    print(f"{label:22s} {fn()}")
                except Timeout:
                    print(f"{label:22s} (sem resposta)")
                except PixyError as e:
                    print(f"{label:22s} erro: {e}")
            return 0

        if cmd in ("get", "set"):
            name = args[0].upper()
            payload = bytes.fromhex("".join(args[1:])) if len(args) > 1 else b""
            r = cam.send(name, payload, **kw)
            if cmd == "set":
                print(f"{name} -> resposta {hx(r)}")
            else:
                print(f"{name} -> {hx(r)}")
            return 0

        if cmd == "raw":
            head = bytes.fromhex("".join(args[:4]))
            payload = bytes.fromhex("".join(args[4:])) if len(args) > 4 else b""
            from pixy.protocol import build_reports
            cam.drain()
            for rep in build_reports(head, payload):
                print("->", rep.hex(" ")); cam.dev.write(rep)
            import time
            t = time.monotonic() + 1.0
            while time.monotonic() < t:
                r = cam.dev.read(REPORT_SIZE, 50)
                if r: print("<-", r.hex(" "))
            return 0

        if cmd == "scan":
            f = args[0].upper() if args else "GET_"
            for n in COMMANDS:
                if not n.startswith("GET_") or f not in n or n in DANGEROUS:
                    continue
                try:
                    r = cam.send(n, b"", timeout_s=0.4, **kw)
                    print(f"{n:40s} {hx(r)}")
                except Timeout:
                    print(f"{n:40s} (sem resposta)")
                except PixyError as e:
                    print(f"{n:40s} erro: {e}")
            return 0

        if cmd == "monitor":
            import time
            secs = float(args[0]) if args else 10
            print(f"ouvindo por {secs}s (mexa a câmera, faça gestos, aperte botões)...")
            t = time.monotonic() + secs
            while time.monotonic() < t:
                r = cam.dev.read(REPORT_SIZE, 200)
                if r:
                    print(time.strftime("%H:%M:%S"), r.hex(" "))
            return 0

        if cmd == "hdr":
            print("HDR =", api.get_hdr() if not args else api.set_hdr(args[0] == "on")); return 0
        if cmd == "lowlight":
            print("low light =", api.get_low_light() if not args else api.set_low_light(args[0] == "on")); return 0
        if cmd == "gimbal":
            print("gimbal mode =", api.get_gimbal_mode() if not args else api.set_gimbal_mode(int(args[0]))); return 0
        if cmd == "pos":
            motor = {"pan": 1, "tilt": 2}.get(args[0], None) or int(args[0])
            if len(args) > 1:
                api.set_motor_pos(motor, float(args[1]))
                import time; time.sleep(2.0)
            p = api.get_motor_pos(motor)
            print(f"motor {p.get('motor')}: alvo={p.get('target', 0):.2f}  atual={p.get('current', 0):.2f}"); return 0
        if cmd == "gesture":
            t = int(args[0])
            if len(args) > 1:
                api.set_gesture(t, args[1] == "on")
            r = api.get_gesture(t); print(f"gesto {r[0]}: {'ligado' if r[1] else 'desligado'}"); return 0
        if cmd == "flip":
            t = {"h": 1, "v": 2}.get(args[0], None) or int(args[0])
            if len(args) > 1:
                api.set_reverse(t, args[1] == "on")
            r = api.get_reverse(t); print(f"flip {r[0]}: {'ligado' if r[1] else 'desligado'}"); return 0
        if cmd == "preset":
            print("preset ->", api.set_preset_pos(int(args[0]))); return 0

    print("comando desconhecido:", cmd); return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except PixyError as e:
        print("ERRO:", e); sys.exit(2)
