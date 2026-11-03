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

[CmdletBinding(DefaultParameterSetName="inicio")]
param (
    [Parameter(Mandatory=$true)]
    [Alias("d")]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "El directorio a monitorear no existe."
        }
        $true
    })]
    [string]$directorio,

    [Parameter(Mandatory=$true, ParameterSetName="inicio")]
    [Alias("s")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw "El directorio de salida no puede estar vacio."
        }
        if ((Test-Path -LiteralPath $_) -and -not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "La salida debe ser un directorio."
        }
        $true
    })]
    [string]$salida,

    [Parameter(Mandatory=$true, ParameterSetName="detencion")]
    [Alias("k")]
    [switch]$kill,

    [Parameter(Mandatory=$false, ParameterSetName="inicio")]
    [switch]$daemon_mode
)

# Convertir a rutas absolutas nativas
$directorio = (Resolve-Path -LiteralPath $directorio -ErrorAction Stop).Path

$bytes = [System.Text.Encoding]::UTF8.GetBytes($directorio)
$hashDirectorio = (Get-FileHash -InputStream ([IO.MemoryStream]::new($bytes)) -Algorithm MD5).Hash
$pidFile = Join-Path "/tmp" "demonio_ps_$hashDirectorio.pid"
$errorFile = Join-Path "/tmp" "demonio_errores_fondo_$hashDirectorio.log"

# ==============================================================================
# Lógica de detención (-kill)
# ==============================================================================
if ($kill) {
    if (Test-Path $pidFile) {
        $pidDemonio = Get-Content $pidFile
        $proceso = Get-Process -Id $pidDemonio -ErrorAction SilentlyContinue
        try {
            if ($proceso) {
                Stop-Process -InputObject $proceso -Force -ErrorAction Stop
                $proceso.WaitForExit()
                Write-Host "Demonio (PID $pidDemonio) para el directorio '$directorio' detenido exitosamente."
            } else {
                Write-Host "El proceso ya no estaba en ejecución. Se limpiaron los rastros."
            }
        } finally {
            # Se asegura la eliminación de TODOS los archivos temporales vinculados al PID
            Remove-Item -LiteralPath (Join-Path "/tmp" "archivos_temp_$pidDemonio.txt"), $errorFile, $pidFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
        Write-Host "No hay ningún demonio ejecutándose para ese directorio."
    }
    exit
}

# ==============================================================================
# Preparación del directorio de salida (Solo en modo inicio)
# ==============================================================================
if (-not (Test-Path -LiteralPath $salida)) {
    try {
        New-Item -ItemType Directory -Path $salida -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "No se pudo crear el directorio de salida '$salida': $_"
        exit 1
    }
}
$salida = (Resolve-Path -LiteralPath $salida).Path

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
                exit 1
            }
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    $scriptPath = $MyInvocation.MyCommand.Path
    $comando = "& '$scriptPath' -directorio '$directorio' -salida '$salida' -daemon_mode"
    
    # Desconectamos flujos para liberar la terminal
    $proc = Start-Process pwsh -ArgumentList "-Command", $comando -RedirectStandardOutput "/dev/null" -RedirectStandardError $errorFile -PassThru
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
    foreach ($job in @($eventJob1, $eventJob2, $eventJob3)) {
        if ($job) {
            Unregister-Event -SourceIdentifier $job.Name -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
    if (Test-Path $pidFile) { Remove-Item $pidFile -Force }
}