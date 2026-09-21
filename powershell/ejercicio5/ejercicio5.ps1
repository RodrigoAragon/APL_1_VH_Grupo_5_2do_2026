# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

# Ejercicio 5

<#
.SYNOPSIS
Consulta personajes y peliculas de Star Wars en swapi.tech.

.DESCRIPTION
Permite buscar varios ids de personajes y peliculas. Guarda cada respuesta en cache para no volver a consultar la API si ya existe localmente.

.PARAMETER people
Array de ids de personajes a buscar.

.PARAMETER film
Array de ids de peliculas a buscar.

.EXAMPLE
./ejercicio5.ps1 -people 1,2 -film 1,2
#>
[CmdletBinding()]
param(
    # Array de ids de personajes. Deben ser enteros positivos.
    [ValidateScript({
        foreach ($valor in $_) {
            if ($valor -le 0) {
                throw 'Los ids deben ser enteros positivos.'
            }
        }
        return $true
    })]
    [int[]]$people,

    # Array de ids de peliculas. Deben ser enteros positivos.
    [ValidateScript({
        foreach ($valor in $_) {
            if ($valor -le 0) {
                throw 'Los ids deben ser enteros positivos.'
            }
        }
        return $true
    })]
    [int[]]$film
)

# Los errores se manejan con try/catch.
$ErrorActionPreference = 'Stop'

# Descarga un recurso o lo lee desde cache si ya existe.
function Get-RecursoSwapi {
    param(
        [string]$Tipo,
        [string]$Endpoint,
        [int]$Id
    )

    # Archivo de cache para este tipo e id.
    $archivoCache = Join-Path -Path $cacheDir -ChildPath "$Tipo`_$Id.json"

    # Si existe en cache, se lee y se devuelve.
    if (Test-Path -LiteralPath $archivoCache -PathType Leaf) {
        return (Get-Content -LiteralPath $archivoCache -Raw | ConvertFrom-Json)
    }

    # URL de la API.
    $url = "https://www.swapi.tech/api/$Endpoint/$Id"

    try {
        # Invoke-RestMethod ya convierte JSON a objeto PowerShell.
        $datos = Invoke-RestMethod -Uri $url -Method Get

        # Se valida que la respuesta tenga result.
        if ($null -eq $datos.result) {
            Write-Warning "No se encontraron datos para $Tipo con id $Id."
            return $null
        }

        # Se guarda en cache como JSON.
        $datos | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $archivoCache -Encoding UTF8
        return $datos
    }
    catch {
        # Si la API falla, se informa y se continua con otros ids.
        Write-Warning "No se pudo consultar $Tipo con id $Id. $($_.Exception.Message)"
        return $null
    }
}

try {
    # Se valida que el usuario haya pedido algo.
    if (($null -eq $people -or $people.Count -eq 0) -and ($null -eq $film -or $film.Count -eq 0)) {
        throw 'Debe indicar -people, -film o ambos.'
    }

    # La cache queda dentro de la misma carpeta del script.
    $cacheDir = Join-Path -Path $PSScriptRoot -ChildPath 'cache'

    # Se crea la carpeta cache si no existe.
    if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    # Se procesan personajes.
    foreach ($id in $people) {
        $datos = Get-RecursoSwapi -Tipo 'people' -Endpoint 'people' -Id $id

        if ($null -eq $datos) {
            continue
        }

        $props = $datos.result.properties

        Write-Output 'Personajes:'
        Write-Output "Id: $id"
        Write-Output "Name: $($props.name)"
        Write-Output "Gender: $($props.gender)"
        Write-Output "Height: $($props.height)"
        Write-Output "Mass: $($props.mass)"
        Write-Output "Birth Year: $($props.birth_year)"
        Write-Output ''
    }

    # Se procesan peliculas.
    foreach ($id in $film) {
        $datos = Get-RecursoSwapi -Tipo 'film' -Endpoint 'films' -Id $id

        if ($null -eq $datos) {
            continue
        }

        $props = $datos.result.properties
        $opening = $props.opening_crawl -replace "\r?\n", ' '

        Write-Output 'Peliculas:'
        Write-Output "Title: $($props.title)"
        Write-Output "Episode id: $($props.episode_id)"
        Write-Output "Release date: $($props.release_date)"
        Write-Output "Opening crawl: $opening"
        Write-Output ''
    }
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
}
