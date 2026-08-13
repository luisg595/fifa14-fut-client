# fifa14-fut-client

Cliente Windows del split remoto de **FIFA 14 Local FUT** (v2.41.1 BETA 2.25.9).
Conecta con el servidor Debian/Docker `fifa14-fut-server` por LAN.

## Requisitos

- Windows, PowerShell, Python 3.10+.
- El server `fifa14-fut-server` levantado y con `BLAZE_PUBLIC_HOST` / `ADMIN_SECRET` definidos.

## Instalación

1. Instalar el entorno de Python (una vez):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1
   ```
2. Copiar `config.local.psd1.example` a `config.local.psd1` y editar:
   - `GameRoot` / `GameExe` → tu instalación de FIFA 14.
   - `ServerHost` → IP-LAN del server (la imprime `up.sh`).
   - `ServerHttpPort` → 8099.
   - `AdminSecret` → el mismo del `.env` del server.
   (También se pueden usar env `FIFA14_GAME_ROOT`, `FIFA14_SERVER_HOST`, `FIFA14_SERVER_HTTP_PORT`, `FIFA14_ADMIN_SECRET`.)
3. Aplicar los parches de disco (una vez por instalación):
   - Doble-clic en `INSTALL_GAME_PATCHES.cmd`.
   - Los pasos que necesitan al server (upload de match-assets, CA, `Test-NetConnection`) degradan con warning si el server aún no responde; re-ejecuta el .cmd cuando `./up.sh` esté listo.

## Uso (cada sesión)

- Doble-clic en `RUN_REMOTE_FUT.cmd`:
  - espera al server (health, hasta 60s), restaura la ruta NAV retail,
  - baja el CA si falta, lanza `fifa14.exe`, adjunta el tracer Frida y muestra `READY`.
- Monedas (repetible): doble-clic en `GIVE_100M_TEST_COINS.cmd` → `{granted: true, balance: 100000000}`.

## Orden recomendado de puesta en marcha

1. En el server: `./up.sh`.
2. En el cliente: `INSTALL_GAME_PATCHES.cmd` (sube el report de match-assets).
3. Primera sesión: `RUN_REMOTE_FUT.cmd`.

## Contenido

- `tools/` — launcher fino (`run_fifa14_remote_beta.ps1`), parcheador de instalación
  (`install_fifa14_game_patches.ps1`), `give_coins_remote.ps1`, tracer Frida con delta `--server-ip`,
  y los apply/verify de los parches de disco.
- `config.local.psd1.example` — plantilla de configuración (no se commitea `config.local.psd1`).
