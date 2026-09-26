# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

<#
.SYNOPSIS
    Monitorea un directorio buscando archivos duplicados y los comprime.

.DESCRIPTION
    El script funciona como un demonio en segundo plano (job/proceso oculto) que utiliza 
    FileSystemWatcher. Si encuentra un archivo con el mismo Hash MD5 que otro ya 
    existente, lo comprime en formato ZIP y lo elimina.

.PARAMETER directorio
    Ruta del directorio a monitorear. Se aceptan rutas relativas y absolutas.

.PARAMETER salida
    Ruta del directorio en donde se van a crear los backups (.zip).

.PARAMETER kill
    Detiene el demonio previamente iniciado para ese directorio.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [Alias("d")]
    [string]$directorio,

    [Parameter(Mandatory=$false)]
    [Alias("s")]
    [string]$salida,

    [Parameter(Mandatory=$false)]
    [Alias("k")]
    [switch]$kill,

    [Parameter(Mandatory=$false)]
    [switch]$daemon_mode # Parámetro de uso interno
)

# Convertir a rutas absolutas nativas
$directorio = (Resolve-Path $directorio -ErrorAction Stop).Path
if (-not (Test-Path $directorio -PathType Container)) {
    Write-Error "El directorio a monitorear no existe."
    exit
}

# Identificador único (se cambia char array a codificación UTF8 explícita)
$bytes = [System.Text.Encoding]::UTF8.GetBytes($directorio)
$hashDirectorio = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm MD5).Hash

# ==============================================================================
# Lógica de detención (-kill)
# ==============================================================================
$pidFile = Join-Path "/tmp" "demonio_ps_$hashDirectorio.pid"

if ($kill) {
    if (Test-Path $pidFile) {
        $pidDemonio = Get-Content $pidFile
        try {
            Stop-Process -Id $pidDemonio -Force -ErrorAction Stop
            Remove-Item $pidFile -Force
            Write-Host "Demonio (PID $pidDemonio) para el directorio '$directorio' detenido exitosamente."
        } catch {
            Remove-Item $pidFile -Force
            Write-Host "El proceso ya no estaba en ejecución. Se limpiaron los rastros."
        }
    } else {
        Write-Host "No hay ningún demonio ejecutándose para ese directorio."
    }
    exit
}

# Validar parámetro -salida que es obligatorio si no es -kill
if ([string]::IsNullOrWhiteSpace($salida)) {
    Write-Error "El parámetro -salida es obligatorio para iniciar el monitoreo."
    exit
}

if (-not (Test-Path $salida)) {
    New-Item -ItemType Directory -Path $salida | Out-Null
}
$salida = (Resolve-Path $salida).Path

# ==============================================================================
# Lógica de lanzamiento en 2do plano
# ==============================================================================
if (-not $daemon_mode) {
    if (Test-Path $pidFile) {
        $pidExistente = Get-Content $pidFile
        if (-not [string]::IsNullOrWhiteSpace($pidExistente)) {
            $proceso = Get-Process -Id $pidExistente -ErrorAction SilentlyContinue
            if ($proceso) {
                Write-Error "Ya existe un demonio ejecutándose para este directorio (PID $pidExistente)."
                exit
            }
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    $scriptPath = $MyInvocation.MyCommand.Path
    
    # SOLUCIÓN: Usamos -Command y encapsulamos la ejecución completa en un string.
    # El símbolo '&' le dice a PowerShell que ejecute la ruta como un script.
    $comando = "& '$scriptPath' -directorio '$directorio' -salida '$salida' -daemon_mode"
    
    # Pasamos el array con -Command y nuestro string seguro
    $proc = Start-Process pwsh -ArgumentList "-Command", $comando -RedirectStandardOutput "/dev/null" -RedirectStandardError "/tmp/demonio_errores_fondo.log" -PassThru
    $proc.Id | Out-File $pidFile -Force
    Write-Host "Demonio iniciado exitosamente en 2do plano (PID $($proc.Id))."
    exit
}

# ==============================================================================
# Proceso principal (FileSystemWatcher)
# ==============================================================================
$watcher = $null
$tempFile = Join-Path "/tmp" "archivos_temp_$PID.txt"

# 1. Empaquetamos nuestras variables para cruzarlas al universo paralelo (Runspace) del evento
$estadoGlobal = @{
    Directorio = $directorio
    Salida     = $salida
    TempFile   = $tempFile
    Cerrojo    = [System.Collections.Concurrent.ConcurrentDictionary[string, byte]]::new()
}

try {
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $directorio
    $watcher.IncludeSubdirectories = $true 
    $watcher.EnableRaisingEvents = $true

    $action = {
        # 2. Desempaquetamos las variables desde $Event.MessageData
        $estado = $Event.MessageData
        $dirMonitoreo = $estado.Directorio
        $dirSalida = $estado.Salida
        $archivoTemp = $estado.TempFile
        $cerrojo = $estado.Cerrojo

        $ProgressPreference = 'SilentlyContinue'
        $pathNuevo = $Event.SourceEventArgs.FullPath
        
        # Ahora el cerrojo sí existe y no causará un crash silencioso
        if (-not $cerrojo.TryAdd($pathNuevo, 1)) {
            return
        }

        try {
            Start-Sleep -Seconds 1 
            
            if (Test-Path $pathNuevo -PathType Leaf) {
                $hashNuevo = (Get-FileHash -Path $pathNuevo -Algorithm MD5 -ErrorAction Stop).Hash
                
                # Usamos $dirMonitoreo en lugar de $directorio
                $archivos = Get-ChildItem -Path $dirMonitoreo -File -Recurse | Where-Object { $_.FullName -ne $pathNuevo }
                
                foreach ($archivo in $archivos) {
                    $hashExistente = (Get-FileHash -Path $archivo.FullName -Algorithm MD5).Hash
                    
                    if ($hashNuevo -eq $hashExistente) {
                        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                        # Usamos $dirSalida en lugar de $salida
                        $zipFile = Join-Path $dirSalida "$timestamp.zip"
                        
                        Compress-Archive -Path $pathNuevo -DestinationPath $zipFile -Force
                        
                        $logMsg = "[$timestamp] DUPLICADO: '$pathNuevo' es copia de '$($archivo.FullName)'. Archivado en $zipFile"
                        Add-Content -Path (Join-Path $dirSalida "demonio.log") -Value $logMsg
                        
                        # Usamos $archivoTemp
                        $logMsg | Out-File $archivoTemp -Append
                        
                        Remove-Item -Path $pathNuevo -Force
                        break
                    }
                }
            }
        } catch {
            $errorMsg = "[$((Get-Date).ToString())] ERROR en evento: $_"
            Add-Content -Path (Join-Path $dirSalida "errores_demonio.log") -Value $errorMsg
        } finally {
            [void]$cerrojo.TryRemove($pathNuevo, [ref]$null)
        }
    }

    # 3. Le inyectamos el estadoGlobal usando -MessageData a todos los eventos
    $eventJob1 = Register-ObjectEvent $watcher 'Created' -MessageData $estadoGlobal -Action $action
    $eventJob2 = Register-ObjectEvent $watcher 'Changed' -MessageData $estadoGlobal -Action $action
    $eventJob3 = Register-ObjectEvent $watcher 'Renamed' -MessageData $estadoGlobal -Action $action

    while ($true) {
        Start-Sleep -Seconds 5
    }

} catch {
    $errorMsg = "[$((Get-Date).ToString())] ERROR CRÍTICO: $_"
    Add-Content -Path (Join-Path $salida "errores_demonio.log") -Value $errorMsg
} finally {
    if ($watcher) {
        $watcher.EnableRaisingEvents = $false
        $watcher.Dispose()
    }
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force
    }
}