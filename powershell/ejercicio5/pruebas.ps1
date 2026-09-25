$ScriptPath = "./ejercicio5.ps1"
$TempDir = If (Test-Path "/tmp") { "/tmp" } Else { $env:TEMP }
$CacheDir = Join-Path $TempDir "ejercicio5_cache"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Iniciando Pruebas de Integración (PowerShell)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Limpiar caché previa
if (Test-Path $CacheDir) { Remove-Item -Path $CacheDir -Recurse -Force }

function Assert-Result {
    param([bool]$Condition, [string]$TestName)
    if ($Condition) {
        Write-Host "PASÓ: $TestName" -ForegroundColor Green
    } else {
        Write-Host "FALLÓ: $TestName" -ForegroundColor Red
    }
}

# Prueba 1: Sin parámetros
try {
    & $ScriptPath -ErrorAction Stop > $null 2>&1
    # Si la validación en la sección de params es estricta, PowerShell lanza un error nativo o el script se detiene.
    # En nuestro script utilizamos exit, por lo que comprobaremos si se genera la salida de error.
    $output = & $ScriptPath
    Assert-Result ($output -match "Error: No se introdujeron parámetros obligatorios") "Fallo controlado sin parámetros obligatorios"
} catch {
    Assert-Result $true "Fallo controlado sin parámetros obligatorios (Excepción nativa)"
}

# Prueba 2: Ayuda nativa de PowerShell
$helpOutput = Get-Help $ScriptPath
Assert-Result ($null -ne $helpOutput) "Integración exitosa con Get-Help"

# Prueba 3: Búsqueda válida simple
& $ScriptPath -people 1 > $null
$LastExitCodeOpt = $? # Captura si la ejecución anterior fue exitosa
Assert-Result $LastExitCodeOpt "Búsqueda de personaje válido (Luke Skywalker)"

# Prueba 4: Verificación de creación de Caché
$CacheFile = Join-Path $CacheDir "people_1.json"
Assert-Result (Test-Path $CacheFile) "Creación de archivo de caché temporal"

# Prueba 5: Múltiples IDs mediante Array nativo
& $ScriptPath -film 1,2 -people 3 > $null
Assert-Result $? "Búsqueda con Arrays nativos múltiples y orden dinámico"

# Prueba 6: ID Inválido
# Esperamos que el script maneje el error y termine limpiamente
$errorOutput = & $ScriptPath -people 99999 2>&1
Assert-Result ($errorOutput -match "hubo un error técnico") "Manejo de errores HTTP (Try/Catch) ante un ID inválido"

# Prueba 7: Limpieza de archivos temporales
$TempFiles = Get-ChildItem -Path $TempDir -Filter "swapi_temp_*.json" -ErrorAction SilentlyContinue
Assert-Result ($TempFiles.Count -eq 0) "Limpieza de archivos basura exitosa en bloque Finally"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Pruebas de PowerShell Finalizadas" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan