# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

<#
.SYNOPSIS
Consulta información de personajes y películas de Star Wars usando swapi.tech.

.DESCRIPTION
Este script permite buscar información en la API de Star Wars. Cuenta con manejo de caché 
para evitar re-consultar, y limpia sus rastros temporales del sistema al finalizar.

.PARAMETER people
Arreglo de IDs numéricos de los personajes a buscar (ej: 1,2).

.PARAMETER film
Arreglo de IDs numéricos de las películas a buscar (ej: 1,2).

.EXAMPLE
./swapi.ps1 -people 1,2 -film 1,2
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [int[]]$people,

    [Parameter(Mandatory=$false)]
    [int[]]$film
)

# Validación nativa: No se permite la ejecución si ambos arreglos están vacíos
if (-not $people -and -not $film) {
    Write-Host "Error: No se introdujeron parámetros obligatorios. Debe usar al menos -people o -film." -ForegroundColor Red
    Write-Host "Ejecute 'Get-Help ./ejercicio5.ps1' para más información." -ForegroundColor Yellow
    exit
}

# Ubicación temporal obligada en /tmp si existe (compatible WSL/Linux), sino usa la variable de entorno
$TempDir = If (Test-Path "/tmp") { "/tmp" } Else { $env:TEMP }
$CachePath = Join-Path $TempDir "ejercicio5_cache"

if (-not (Test-Path $CachePath)) {
    New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
}

function Get-SwapiData {
    param (
        [string]$Type,
        [int[]]$Ids
    )

    foreach ($id in $Ids) {
        $CacheFile = Join-Path $CachePath "${Type}_${id}.json"
        $TempFile = Join-Path $TempDir "ejercicio5_temp_$($PID)_$([guid]::NewGuid()).json"

        try {
            # Lógica de Caché
            if (Test-Path $CacheFile) {
                $json = Get-Content $CacheFile -Raw | ConvertFrom-Json
            } else {
                $url = "https://www.swapi.tech/api/$Type/$id"
                
                # Descarga a un archivo temporal primero (con Stop para forzar que el Catch atrape errores HTTP)
                Invoke-RestMethod -Uri $url -Method Get -OutFile $TempFile -ErrorAction Stop
                
                $json = Get-Content $TempFile -Raw | ConvertFrom-Json
                
                if ($json.message -ne 'ok') {
                    throw "La API devolvió una respuesta no válida o el ID no se encontró."
                }
                
                # Si todo sale bien, lo pasamos al caché
                Copy-Item -Path $TempFile -Destination $CacheFile -Force
            }

            # Impresión de datos según el tipo
            if ($Type -eq "people") {
                $props = $json.result.properties
                Write-Host "Id: $id"
                Write-Host "Name: $($props.name)"
                Write-Host "Gender: $($props.gender)"
                Write-Host "Height: $($props.height)"
                Write-Host "Mass: $($props.mass)"
                Write-Host "Birth Year: $($props.birth_year)"
                Write-Host ""
            } elseif ($Type -eq "films") {
                $props = $json.result.properties
                Write-Host "Title: $($props.title)"
                Write-Host "Episode id: $($props.episode_id)"
                Write-Host "Release date: $($props.release_date)"
                
                # Limpiar texto del "opening crawl" para que no ocupe 10 líneas en pantalla
                $crawl = $props.opening_crawl -replace "`r`n"," " -replace "`n"," "
                if ($crawl.Length -gt 40) { $crawl =$crawl.Substring(0,40) + "..." }
                Write-Host "Opening crawl: $crawl"
                Write-Host ""
            }

        } catch {
            Write-Host "Lo sentimos, hubo un error técnico. No se pudo obtener la información de $Type con ID$id." -ForegroundColor Red
            Write-Host "Detalle técnico: Asegúrese de estar conectado a internet y que el ID sea correcto." -ForegroundColor Red
            # Si un comando da error, detenemos toda la ejecución como solicita el enunciado
            exit
        } finally {
            # Limpieza: se ejecuta sí o sí (en éxito y en error) borrando el archivo temporal de paso
            if (Test-Path $TempFile) {
                Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

if ($people) {
    Write-Host "Personajes:"
    Get-SwapiData -Type "people" -Ids $people
}

if ($film) {
    Write-Host "Películas:"
    Get-SwapiData -Type "films" -Ids $film
}