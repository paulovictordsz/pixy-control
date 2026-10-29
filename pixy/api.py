"""Camada tipada por cima do protocolo. Layouts descobertos nos wrappers do EMEET STUDIO
(EMHidCmdHelper::hidCmdSend*). Onde o significado dos enums ainda não foi confirmado
na câmera real, o valor é passado como inteiro cru."""
import struct
from .protocol import Pixy, DEV_MAIN, DEV_GIMBAL


def _u8(resp, i=0):
    return resp[i] if len(resp) > i else None


class PixyApi:
    """Observação sobre SETs: a resposta é o eco do(s) primeiro(s) byte(s) do pedido seguido
    de um status (0x20 observado = ok). Os métodos set_* devolvem o primeiro byte da resposta
    (o eco); para ver tudo use cam.send(...)."""

    def __init__(self, cam: Pixy):
        self.cam = cam

    # ---- identificação -------------------------------------------------
    def version(self, device_type=DEV_MAIN) -> int:
        r = self.cam.get("GET_VER", device_type=device_type)
        return r[0] | (r[1] << 8) if len(r) >= 2 else None

    def serial(self, device_type=DEV_MAIN) -> str:
        r = self.cam.get("GET_SN", device_type=device_type)
        return r.split(b"\\0")[0].decode(errors="replace")

    def device_ver(self):
        return self.cam.get("GET_DEVICE_VER")

    def alias(self) -> str:
        return self.cam.get("GET_DEVICE_ALIAS").split(b"\\0")[0].decode(errors="replace")

    def func_sta(self):
        return self.cam.get("GET_FUNC_STA")

    # ---- imagem (1 byte on/off) -----------------------------------------
    def get_hdr(self):            return _u8(self.cam.get("GET_HDR_STA"))
    def set_hdr(self, on):        return self.cam.set("SET_HDR_STA", bytes([1 if on else 0]))
    def get_low_light(self):      return _u8(self.cam.get("GET_LOW_LIGHT_STA"))
    def set_low_light(self, on):  return self.cam.set("SET_LOW_LIGHT_STA", bytes([1 if on else 0]))
    def get_lut3d(self):          return _u8(self.cam.get("GET_LUT3D_MODE"))
    def set_lut3d(self, mode):    return self.cam.set("SET_LUT3D_MODE", bytes([mode]))
    def get_video_dir(self):      return _u8(self.cam.get("GET_UVC_VIDEO_DIR"))
    def set_video_dir(self, d):   return self.cam.set("SET_UVC_VIDEO_DIR", bytes([d]))
    def get_wb_lock(self):        return _u8(self.cam.get("GET_WB_LOCK_STA"))
    def get_ev_lock(self):        return _u8(self.cam.get("GET_EV_LOCK_STA"))
    def get_focus_lock(self):     return _u8(self.cam.get("GET_FOCUS_LOCK_STA"))
    def get_focus_mode(self):     return self.cam.get("GET_FOCUS_MODE")
    def get_meter_mode(self):     return self.cam.get("GET_METER_MODE")
    def get_power_line(self):     return _u8(self.cam.get("GET_POWER_LINE_MODE"))
    def set_power_line(self, m):  return self.cam.set("SET_POWER_LINE_MODE", bytes([m]))

    def get_reverse(self, reverse_type):
        return self.cam.get("GET_REVERSE_STA", bytes([reverse_type]))

    def set_reverse(self, reverse_type, on):
        return self.cam.set("SET_REVERSE_STA", bytes([reverse_type, 1 if on else 0]))

    # ---- IA: gestos e tracking ------------------------------------------
    def get_gesture(self, gesture_type):
        return self.cam.get("GET_GESTURE_RECOG_STA", bytes([gesture_type]))

    def set_gesture(self, gesture_type, on):
        return self.cam.set("SET_GESTURE_RECOG_STA", bytes([gesture_type, 1 if on else 0]))

    def get_object_track(self):
        return self.cam.get("GET_OBJECT_TRACK")

    def set_object_track(self, mode, flag=0, f=(0.0, 0.0, 0.0, 0.0, 0.0)):
        """SET_OBJECT_TRACK: [mode u8][flag u8][5 x float32 LE] = 22 bytes."""
        return self.cam.set("SET_OBJECT_TRACK", struct.pack("<BB5f", mode, flag, *f))

    def get_target_track(self):
        return self.cam.get("GET_TARGET_TRACK")

    def is_tracking(self) -> bool:
        """O seguir só roda com device mode 1 (IA)."""
        return _u8(self.cam.get("GET_DEVICE_MODE")) == 1

    def set_tracking(self, on: bool):
        """Liga: device mode 1 + SET_TARGET_TRACK 1. Desliga: SET_TARGET_TRACK 0 + device mode 3.
        Recusado pelo firmware em modo privacidade (2)."""
        if on:
            self.cam.set("SET_DEVICE_MODE", b"\x01")
            return self.cam.set("SET_TARGET_TRACK", b"\x01" + bytes(12))
        self.cam.set("SET_TARGET_TRACK", b"\x00" + bytes(12))
        return self.cam.set("SET_DEVICE_MODE", b"\x03")

    # ---- gimbal / motor (device type 3) ---------------------------------
    def get_gimbal_mode(self):
        return _u8(self.cam.get("GET_GIMBAL_MODE"))

    def set_gimbal_mode(self, mode):
        return self.cam.set("SET_GIMBAL_MODE", bytes([mode]))

    MOTOR_PAN = 1
    MOTOR_TILT = 2

    def get_motor_pos(self, motor):
        """GET_MOTOR_POS: envia [motor u8]; resposta [motor u8][f32 alvo][f32 atual] em graus.
        Confirmado na PIXY: motor 1 = pan, motor 2 = tilt. 'target' muda na hora, 'current' converge em ~2 s."""
        r = self.cam.get("GET_MOTOR_POS", bytes([motor]))
        if len(r) >= 9:
            return {"motor": r[0], "target": struct.unpack("<f", r[1:5])[0],
                    "current": struct.unpack("<f", r[5:9])[0], "raw": r.hex(" ")}
        return {"raw": r.hex(" ")}

    def set_motor_pos(self, motor, pos: float):
        return self.cam.set("SET_MOTOR_POS", struct.pack("<Bf", motor, pos))

    def set_motor_relative(self, motor, delta: float):
        """Na PIXY o movimento relativo não bate exatamente com o delta pedido (overshoot e
        reacomodação). Para posicionar com precisão use set_motor_pos (absoluto)."""
        return self.cam.set("SET_MOTOR_RELATIVE_POS", struct.pack("<Bf", motor, delta))

    def set_motor_speed(self, motor, speed: float):
        return self.cam.set("SET_MOTOR_SPEED", struct.pack("<Bf", motor, speed))

    def get_motor_speed(self, motor):
        return self.cam.get("GET_MOTOR_SPEED", bytes([motor]))

    def set_motor_running(self, a: float, b: float, c: float):
        """SET_MOTOR_RUNNING: 3 floats (provavelmente pan, tilt, velocidade)."""
        return self.cam.set("SET_MOTOR_RUNNING", struct.pack("<3f", a, b, c))

    def set_motor_default_pos(self):
        return self.cam.set("SET_MOTOR_DEFAULT_POS", b"")

    def set_preset_pos(self, index):
        return self.cam.set("SET_MOTOR_PRESET_POS", bytes([index]))

    def get_preset_mode(self, index):
        return self.cam.get("GET_MOTOR_PRESET_POS_MODE", bytes([index]))

    def set_preset_mode(self, index, mode):
        return self.cam.set("SET_MOTOR_PRESET_POS_MODE", bytes([index, mode]))

    # ---- áudio -----------------------------------------------------------
    def get_mic_mute(self):       return _u8(self.cam.get("GET_MIC_MUTE_STA"))
    def set_mic_mute(self, on):   return self.cam.set("SET_MIC_MUTE_STA", bytes([1 if on else 0]))
    def get_denoise(self):        return _u8(self.cam.get("GET_DENOISE_STA"))
    def set_denoise(self, on):    return self.cam.set("SET_DENOISE_STA", bytes([1 if on else 0]))
    def get_agc(self):            return _u8(self.cam.get("GET_AUDIO_AGC_STA"))
    def get_mic_cur(self):        return self.cam.get("GET_MIC_CUR")
