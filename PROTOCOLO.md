# Protocolo HID da EMEET PIXY (engenharia reversa do EMEET STUDIO 2.0.4 macOS)

## Como o app fala com a câmera

- A PIXY (VID `0x328F`, PID `0x00C0`) expõe 5 interfaces USB: 2 UVC (vídeo), 2 UAC (áudio) e **1 HID vendor (interface 4)**.
- Todo o controle (PTZ, gestos, tracking, foco, flip, etc.) passa por essa interface HID, via `libhidapi`.
- Descriptor HID: usage page `0x83`, usage `0x83`, **report ID `0x09`**, 31 bytes de dados na saída e na entrada (32 bytes com o ID).
- Classes relevantes no binário: `EMHidCmdHelper` (monta/parseia), `UsbHidCtrl` (hid_write/hid_read), `EMHidCmdV2RecvFsm` (remonta fragmentos), `HidConfigManage` (camada de negócio).
- O app só usa este protocolo ("V2") em dispositivos cujo `getHidProtocolVer(vid,pid) == 2`. A PIXY é V2 (confirmado na prática).

## Formato do report (32 bytes, igual na ida e na volta)

| byte | conteúdo |
|---|---|
| 0 | `0x09` report ID (faz parte do "cabeçalho" `EMHidCmdV2Head`) |
| 1 | `(deviceType << 5) \| functionType` |
| 2 | subgrupo |
| 3 | id do comando |
| 4 | índice do fragmento (0, 1, 2…) |
| 5-6 | tamanho total do payload, little-endian |
| 7 | bytes de payload neste fragmento (máx. 24) |
| 8-31 | payload |

- Payload > 24 bytes é fragmentado em vários reports com índice crescente.
- A resposta ecoa os bytes 0-3. O byte 1 da resposta pode trazer o device type nos 3 bits altos; o app compara com máscara `0x1f`.
- `GET`: payload da resposta é o valor. `SET`: a resposta ecoa o(s) primeiro(s) byte(s) do pedido e termina com um status; na PIXY o status observado em todos os SETs bem-sucedidos foi `0x20` (ex.: `SET_GESTURE_RECOG_STA 03 01` → `03 20`; `SET_MOTOR_POS 01 …` → `01`).
- O app faz `hid_read` em loop com `QThread::msleep(1)` e timeout; respostas com cabeçalho diferente são tratadas como eventos (`UsbHidCtrl::notifyDataRecv`).

### Device type (3 bits altos do byte 1)

| valor | quem | confirmado na PIXY |
|---|---|---|
| 0 | MCU principal | `GET_VER` = `0x2004`, `GET_SN` = `260410600348` |
| 1 | ? | não responde |
| 2 | ? (provável ISP/sensor) | `GET_VER` = `0x2005` |
| 3 | gimbal/motores | `GET_VER` = `0x2007`; todos os `*_MOTOR_*` e `*_GIMBAL_*` são mandados com byte1 = `0x63` |

## Tabela de comandos

Os 161 cabeçalhos extraídos estão em `pixy/commands.json` (bytes 0-3). Resumo dos grupos (byte 1 / byte 2):

| byte1 | byte2 | área |
|---|---|---|
| 00 | 00 | energia: reboot, bateria, auto-shutdown, auto power-on |
| 01 | 00 | identidade: SN, versão, factory reset, func sta, alias |
| 01 | 01 | device mode |
| 02 | 01/02/04 | privacy trigger, luz LED/RGB, função do botão |
| 03 | 01 | motores: pos, speed, preset, relativo, running, gimbal mode |
| 03 | 04 | pareamento de controle remoto |
| 04 | 00 | imagem: foco, medição, OSD, flip, locks WB/EV/foco, HDR, low light, LUT3D, direção do vídeo, power line, WB fine tune |
| 04 | 01 | tracking (target/object) |
| 04 | 02 | reconhecimento de gestos |
| 05 | 00/01 | áudio: denoise, mic, music mode, AGC, ganho, volume |
| 06 | 00/01/02 | senha, Wi-Fi, RTMP/RTSP push (modelos com rede) |
| 08 | 01 | RTC |
| 09 | 00 | **upgrade de firmware (bloqueado no CLI)** |
| 0a | 00 | gravação em SD (modelos com SD) |

## Layouts de payload confirmados (dos wrappers `hidCmdSend*` / `hidCmdParse*`)

| comando | envia | resposta |
|---|---|---|
| `GET_VER` | – | `u16 LE` versão |
| `GET_SN` | – | string ASCII (12 chars na PIXY) |
| `GET_DEVICE_MODE` | – | `u8` (PIXY devolve 1) |
| `SET_DEVICE_MODE` | `u8` | eco/status. **Semântica na PIXY:** 1 = tracking (SET é recusado com `0x40`; entra via `SET_TARGET_TRACK` 1), 2 = privacidade (tilt vai a -90°), 3 = manual (ao voltar de 2 o tilt vai a 0°) |
| `GET_MOTOR_POS` (dt 3) | `u8 motor` | `u8 motor, f32, f32` (motor 1 = pan, motor 2 = tilt, graus; 1º float = alvo, 2º = posição atual, que converge em ~2 s; motor 0 devolve zeros) |
| `SET_MOTOR_POS` (dt 3) | `u8 motor, f32 pos` | código |
| `SET_MOTOR_RELATIVE_POS` (dt 3) | `u8 motor, f32 delta` | eco do motor. Na PIXY o deslocamento final não bate com o delta (overshoot e reacomodação): prefira `SET_MOTOR_POS` |
| `GET_MOTOR_SPEED` / `SET_MOTOR_SPEED` (dt 3) | `u8 motor[, f32]` | `u8, f32, f32` (PIXY: motor 1 = 80.0) |
| `SET_MOTOR_RUNNING` (dt 3) | `f32, f32, f32` | código |
| `SET_MOTOR_PRESET_POS` (dt 3) | `u8 índice` | código |
| `SET_MOTOR_PRESET_POS_MODE` (dt 3) | `u8 índice, u8 modo` | código |
| `SET_GIMBAL_MODE` / `GET_GIMBAL_MODE` (dt 3) | `u8` / – | não responde na PIXY (ver abaixo) |
| `GET_GESTURE_RECOG_STA` | `u8 tipo` | `u8 tipo, u8 ligado` (PIXY: tipos 0-3 ligados, 4 desligado) |
| `SET_GESTURE_RECOG_STA` | `u8 tipo, u8 ligado` | código |
| `GET_REVERSE_STA` / `SET_REVERSE_STA` | `u8 tipo[, u8 on]` (app usa tipo 1 e 2 = horizontal/vertical) | `u8 tipo, u8 on` |
| `GET_FOCUS_MODE` | – | `u8 modo, SquareInfo(4 bytes)` |
| `SET_FOCUS_MODE` | `u8 modo, SquareInfo(4)` | código |
| `GET_TARGET_TRACK` | – | `u8 modo, 5 x f32` (PIXY: modo 1, floats ≈ x 0.057, y 0.089, 0, w 0.447, h 0.603 — caixa normalizada do alvo) |
| `SET_TARGET_TRACK` | 13 bytes | código |
| `SET_OBJECT_TRACK` | `u8 modo, u8, f32 x5` (22 bytes) | código |
| `GET_PRIVACY_TRIGGER_TIME` / `SET_PRIVACY_TRIGGER_TIME` | – / `u32 LE` | segundos da "privacidade automática" (padrão 60; 0 = nunca, opção "Never" no EMEET STUDIO). **Qualquer comando HID reinicia o contador**: com 10 s, em silêncio HID a câmera abaixou em menos de 25 s; consultando o modo a cada 3 s, nunca abaixou. Por isso apps de controle não podem ficar consultando a câmera em segundo plano |
| `GET_MUSIC_MODE` | – | `u8` (PIXY: 2) |
| `SET_*_STA` de 1 byte (HDR, low light, locks, OSD…) | `u8` | código |
| `SET_AUTO_SHUTDOWN_TIME` | 3 bytes | código |
| `SET_RTC_TIME` | 19 bytes | código |

`analysis/cmd_lens.txt` tem o tamanho do payload de todos os wrappers.

## O que a PIXY responde (varredura `scan`, somente GETs sem payload, device type 0)

Responderam: `GET_SN`, `GET_VER`, `GET_DEVICE_MODE`, `GET_PRIVACY_TRIGGER_TIME`, `GET_MOTOR_*`, `GET_FOCUS_MODE`, `GET_METER_MODE`, `GET_OSD_STA`, `GET_REVERSE_STA`, `GET_WB_LOCK_STA`, `GET_EV_LOCK_STA`, `GET_FOCUS_LOCK_STA`, `GET_RIO_INFO`, `GET_TARGET_TRACK`, `GET_GESTURE_RECOG_STA`, `GET_MUSIC_MODE`.

Mudos (em qualquer device type): HDR, low light, LUT3D, direção do vídeo, alias, func sta, device ver, mic/denoise/AGC, gimbal mode, luz LED, Wi-Fi, SD, RTMP. Testado também com o stream UVC aberto (ffmpeg capturando 1280x720): continuam mudos. Conclusão: a PIXY não implementa esses comandos (são de outras linhas: C960, S600, Nova, câmeras com luz ou rede). Lista completa em `analysis/scan_dt0.txt`.

## Validado na câmera real (28/10/2026, PIXY fw 0x2004 / gimbal 0x2007)

- `GET_VER`, `GET_SN` (todos os device types que respondem: 0, 2, 3)
- `SET_MOTOR_POS` pan e tilt: posiciona com precisão de 0,01°; `GET_MOTOR_POS` acompanha alvo e atual
- `SET_MOTOR_RELATIVE_POS`: move, mas sem precisão
- `SET_GESTURE_RECOG_STA` tipo 3 off/on, com leitura confirmando; tipo 4 não existe na PIXY (set ignorado)
- `SET_REVERSE_STA` flip horizontal (tipo 1) on/off, com leitura confirmando
- `SET_TARGET_TRACK` modo 1 liga o tracking (GET devolve 1), modo 0 desliga; a caixa do alvo só é preenchida com vídeo rodando
- `SET_DEVICE_MODE` 2 = privacidade (câmera aponta para baixo), 3 = volta ao normal
- Limites aceitos pelo firmware: pan ±150°, tilt ±90° (valores maiores são recortados)
- A PIXY entra sozinha no modo 2 (privacidade, tilt -90°) quando passa `PRIVACY_TRIGGER_TIME` segundos sem comandos HID (padrão 60 s); acorda (modo 3, tilt 0°) quando algum app abre o stream UVC ou com `SET_DEVICE_MODE 3`
- Nenhum report espontâneo observado em 8 s parado (a câmera não "empurra" eventos sem estímulo)

## Segurança

- O CLI bloqueia `SET_START_UPG_*`, `SET_END_UPG_*`, `SET_FACTORY_RESET`, `SET_SD_FORMAT`, `SET_CONFIG_PASSWD` e `SET_DEVICE_VER` por padrão.
- Comandos desconhecidos são ignorados pelo firmware (sem resposta), não há indício de que um pacote errado derrube a câmera.
- O EMEET STUDIO abre o HID em modo exclusivo. Feche-o antes de usar o CLI (e vice-versa).
