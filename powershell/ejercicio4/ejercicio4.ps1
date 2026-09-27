# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

<#
.SYNOPSIS
    Monitorea un directorio buscando archivos duplicados y los comprime en ZIP.
    Un archivo se considera duplicado si tiene el MISMO NOMBRE y el MISMO TAMAÑO.
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
    [switch]$daemon_mode
)

# Convertir a rutas absolutas nativas
$directorio = (Resolve-Path $directorio -ErrorAction Stop).Path
if (-not (Test-Path $directorio -PathType Container)) {
    Write-Error "El directorio a monitorear no existe."
    exit
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($directorio)
$hashDirectorio = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm MD5).Hash
$pidFile = Join-Path "/tmp" "demonio_ps_$hashDirectorio.pid"

# ==============================================================================
# Lógica de detención (-kill)
# ==============================================================================
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

if ([string]::IsNullOrWhiteSpace($salida)) {
    Write-Error "El parámetro -salida es obligatorio para iniciar el monitoreo."
    exit
}

if (-not (Test-Path $salida)) {
    New-Item -ItemType Directory -Path $salida | Out-Null
}
$salida = (Resolve-Path $salida).Path

# ==============================================================================
# Lógica de lanzamiento en 2do plano (Daemonización Segura)
# ==============================================================================
if (-not $daemon_mode) {
    if (Test-Path $pidFile) {
        $pidExistente = Get-Content $pidFile
        if (-not [string]::IsNullOrWhiteSpace($pidExistente)) {
            $proceso = Get-Process -Id $pidExistente -ErrorAction SilentlyContinue
            if ($proceso) {
                Write-Error "Ya existe un demonio ejecutándose (PID $pidExistente)."
                exit
            }
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    $scriptPath = $MyInvocation.MyCommand.Path
    $comando = "& '$scriptPath' -directorio '$directorio' -salida '$salida' -daemon_mode"
    
    # Desconectamos flujos para liberar la terminal
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

# Estado inyectado para el Runspace
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
        $estado = $Event.MessageData
        $dirMonitoreo = $estado.Directorio
        $dirSalida = $estado.Salida
        $archivoTemp = $estado.TempFile
        $cerrojo = $estado.Cerrojo

        $ProgressPreference = 'SilentlyContinue'
        $pathNuevo = $Event.SourceEventArgs.FullPath
        
        if (-not $cerrojo.TryAdd($pathNuevo, 1)) { return }

        try {
            # Espera activa: Aguardar a que Linux libere el archivo copiado
            $liberado = $false
            for ($i = 0; $i -lt 10; $i++) {
                try {
                    $stream = [System.IO.File]::Open($pathNuevo, 'Open', 'Read', 'None')
                    $stream.Close()
                    $liberado = $true
                    break
                } catch { Start-Sleep -Milliseconds 50 }
            }
            
            if (-not $liberado) { return }
            
            if (Test-Path $pathNuevo -PathType Leaf) {
                # OBTENER NOMBRE Y TAMAÑO DEL ARCHIVO NUEVO
                $infoNuevo = Get-Item -LiteralPath $pathNuevo -ErrorAction Stop
                $nombreNuevo = $infoNuevo.Name
                $tamanoNuevo = $infoNuevo.Length
                
                # BUSCAR DUPLICADOS (MISMO NOMBRE Y TAMAÑO) EXCLUYENDO AL NUEVO
                $archivos = Get-ChildItem -LiteralPath $dirMonitoreo -File -Recurse | Where-Object { $_.FullName -ne $pathNuevo }
                
                foreach ($archivo in $archivos) {
                    if ($archivo.Name -eq $nombreNuevo -and $archivo.Length -eq $tamanoNuevo) {
                        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                        $zipFile = Join-Path $dirSalida "$timestamp.zip"
                        
                        Compress-Archive -Path $pathNuevo -DestinationPath $zipFile -Force
                        
                        $logMsg = "[$timestamp] DUPLICADO: '$pathNuevo' es copia de '$($archivo.FullName)'. Archivado en $zipFile"
                        Add-Content -Path (Join-Path $dirSalida "demonio.log") -Value $logMsg
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

    $eventJob1 = Register-ObjectEvent $watcher 'Created' -MessageData $estadoGlobal -Action $action
    $eventJob2 = Register-ObjectEvent $watcher 'Changed' -MessageData $estadoGlobal -Action $action
    $eventJob3 = Register-ObjectEvent $watcher 'Renamed' -MessageData $estadoGlobal -Action $action

    while ($true) { Start-Sleep -Seconds 5 }

} catch {
    $errorMsg = "[$((Get-Date).ToString())] ERROR CRÍTICO: $_"
    Add-Content -Path (Join-Path $salida "errores_demonio.log") -Value $errorMsg
} finally {
    if ($watcher) { $watcher.EnableRaisingEvents = $false; $watcher.Dispose() }
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    if (Test-Path $pidFile) { Remove-Item $pidFile -Force }
}