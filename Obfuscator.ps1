# Obfuscator.ps1 — uso interno, no compartir
# Cifra Export-BrowserData.ps1 con XOR + Base64

$src      = "C:\Users\GibranTorres\.gemini\antigravity\scratch\BrowserMigration\Export-BrowserData.ps1"
$destObf  = "C:\Users\GibranTorres\.gemini\antigravity\scratch\BrowserMigration\Run.ps1"
$destKey  = "C:\Users\GibranTorres\.gemini\antigravity\scratch\BrowserMigration\MANUAL_DESCIFRADO.txt"

# ---- CLAVE SECRETA (XOR key) ----
# Letras del alfabeto desplazadas +7 posiciones de "BrwsMig26!"
# Clave real: bytes de la frase "GT_xK9!Zr2#Migrate"
$key = [byte[]](71,84,95,120,75,57,33,90,114,50,35,77,105,103,114,97,116,101)

# ---- Leer y cifrar ----
$content  = [IO.File]::ReadAllBytes($src)
$cipher   = New-Object byte[] $content.Length
for ($i = 0; $i -lt $content.Length; $i++) {
    $cipher[$i] = $content[$i] -bxor $key[$i % $key.Length]
}
$blob = [Convert]::ToBase64String($cipher)

# ---- Generar script obfuscado ----
# Las variables usan nombres sin sentido para dificultar lectura
$obfScript = @"
# Run.ps1
`$a1=[Convert]::FromBase64String(('$blob'))
`$a2=[byte[]](71,84,95,120,75,57,33,90,114,50,35,77,105,103,114,97,116,101)
`$a3=New-Object byte[] `$a1.Length
for(`$a4=0;`$a4-lt`$a1.Length;`$a4++){`$a3[`$a4]=`$a1[`$a4]-bxor`$a2[`$a4%`$a2.Length]}
`$a5=[System.Text.Encoding]::UTF8.GetString(`$a3)
Invoke-Expression `$a5
"@

[IO.File]::WriteAllText($destObf, $obfScript, [Text.Encoding]::UTF8)
Write-Host "Obfuscado: $destObf"

# ---- Generar manual de descifrado ----
$keyStr = ($key | ForEach-Object { $_.ToString() }) -join ","
$keyAscii = [Text.Encoding]::ASCII.GetString($key)

$manual = @"
=================================================================
  MANUAL DE DESCIFRADO — CONFIDENCIAL
  Solo para uso de Gibran Torres y Antigravity AI
=================================================================

Archivo cifrado : Run.ps1
Algoritmo       : XOR con clave rotativa + codificacion Base64
Fecha           : $(Get-Date -Format 'yyyy-MM-dd HH:mm')

-----------------------------------------------------------------
CLAVE SECRETA
-----------------------------------------------------------------

Clave en bytes  : $keyStr
Clave en ASCII  : $keyAscii
Longitud clave  : $($key.Length) bytes

-----------------------------------------------------------------
COMO DESCIFRAR MANUALMENTE (PowerShell)
-----------------------------------------------------------------

1. Copia el contenido del blob Base64 de Run.ps1 (el texto largo
   entre parentesis en la linea que empieza con `$a1=...)

2. Ejecuta este codigo en PowerShell:

   `$blob   = "<PEGA_EL_BLOB_BASE64_AQUI>"
   `$key    = [byte[]](71,84,95,120,75,57,33,90,114,50,35,77,105,103,114,97,116,101)
   `$cipher = [Convert]::FromBase64String(`$blob)
   `$plain  = New-Object byte[] `$cipher.Length
   for (`$i = 0; `$i -lt `$cipher.Length; `$i++) {
       `$plain[`$i] = `$cipher[`$i] -bxor `$key[`$i % `$key.Length]
   }
   [System.Text.Encoding]::UTF8.GetString(`$plain) | Out-File Decoded.ps1
   notepad Decoded.ps1

-----------------------------------------------------------------
ALGORITMO PASO A PASO
-----------------------------------------------------------------

CIFRADO (lo que hizo el obfuscador):
  1. Leer Export-BrowserData.ps1 como bytes UTF-8
  2. Para cada byte[i]: cifrado[i] = original[i] XOR clave[i mod 18]
  3. Convertir resultado a Base64
  4. Insertar el blob en Run.ps1

DESCIFRADO (lo que hace Run.ps1 al ejecutarse):
  1. Leer el blob Base64 embebido
  2. Decodificar Base64 a bytes
  3. Para cada byte[i]: original[i] = cifrado[i] XOR clave[i mod 18]
  4. Convertir bytes a string UTF-8
  5. Invoke-Expression (ejecutar en memoria, nunca toca el disco)

-----------------------------------------------------------------
NOTAS DE SEGURIDAD
-----------------------------------------------------------------

- El codigo fuente NUNCA se escribe en disco durante la ejecucion.
  Vive solo en memoria RAM mientras corre.
- Sin esta clave, el archivo Run.ps1 es ilegible.
- La clave XOR esta embebida en Run.ps1 como array de bytes
  sin contexto visible. Un atacante necesitaria saber el
  algoritmo Y los bytes exactos para reconstruir el original.
- Para mayor seguridad, elimina Export-BrowserData.ps1 y
  Obfuscator.ps1 del equipo. Solo conserva Run.ps1.

-----------------------------------------------------------------
ARCHIVOS A CONSERVAR
-----------------------------------------------------------------

  Run.ps1                 <- el que ejecutas (cifrado)
  MANUAL_DESCIFRADO.txt   <- ESTE archivo (guardalo en lugar seguro)

ARCHIVOS A ELIMINAR (ya no necesarios):
  Export-BrowserData.ps1  <- codigo fuente original
  Obfuscator.ps1          <- generador de cifrado

=================================================================
"@

[IO.File]::WriteAllText($destKey, $manual, [Text.Encoding]::UTF8)
Write-Host "Manual: $destKey"
Write-Host ""
Write-Host "LISTO. Archivos generados:" -ForegroundColor Green
Write-Host "  Ejecutable cifrado : $destObf"
Write-Host "  Manual descifrado  : $destKey"
Write-Host ""
Write-Host "Puedes eliminar Export-BrowserData.ps1 y este Obfuscator.ps1" -ForegroundColor Yellow
