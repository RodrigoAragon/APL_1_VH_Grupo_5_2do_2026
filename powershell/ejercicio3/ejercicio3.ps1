# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

<#
.SYNOPSIS
Busca archivos duplicados en un directorio y sus subdirectorios.

.DESCRIPTION
Este script identifica archivos duplicados basándose en que tengan exactamente
el mismo nombre y el mismo tamaño (en bytes), sin importar su contenido.
La salida mostrará el nombre del archivo seguido de las rutas donde fue encontrado.

.PARAMETER directorio
Ruta del directorio a analizar. Puede ser una ruta relativa, absoluta y contener espacios.

.EXAMPLE
.\ejercicio.ps1 -directorio "C:\Mis Documentos"

.EXAMPLE
.\ejercicio.ps1 -directorio ./archivos_de_prueba
#>

[CmdletBinding()]
param (
    # Validación nativa de PowerShell: El parámetro es obligatorio. 
    # Si no se ingresa, PowerShell frenará la ejecución y se lo pedirá al usuario.
    [Parameter(Mandatory=$true, HelpMessage="Por favor, ingrese la ruta del directorio a analizar.")]
    [ValidateNotNullOrEmpty()]
    [string]$directorio
)

# Variable global para rastrear el archivo temporal
$script:archivoTmp = $null

function Buscar-Duplicados {
    param (
        [string]$Ruta
    )

    try {
        # 1. Validaciones de existencia (lanzan errores que serán capturados por el 'catch')
        if (-not (Test-Path -Path $Ruta)) {
            throw "La ruta ingresada ('$Ruta') no existe. Por favor, verifica que esté bien escrita."
        }
        if (-not (Test-Path -Path $Ruta -PathType Container)) {
            throw "La ruta ingresada ('$Ruta') no es una carpeta válida."
        }

        # 2. Creación del archivo temporal
        # Utilizamos GetTempPath() que apunta a /tmp en Linux o a la carpeta Temp de usuario en Windows
        $tempDir = [System.IO.Path]::GetTempPath()
        $nombreTemp = "duplicados_$([guid]::NewGuid().ToString().Substring(0,8)).tmp"
        $script:archivoTmp = Join-Path $tempDir $nombreTemp

        # 3. Obtención de datos y guardado en archivo temporal
        # SilentlyContinue evita que errores de permisos rompan la ejecución; simplemente los salta.
        Get-ChildItem -Path $Ruta -File -Recurse -ErrorAction SilentlyContinue | 
            Select-Object Name, Length, DirectoryName | 
            Export-Csv -Path $script:archivoTmp -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

        # 4. Lectura y procesamiento de la información
        $archivos = Import-Csv -Path $script:archivoTmp -Encoding UTF8 -ErrorAction Stop

        # Agrupamos por Nombre y Tamaño, y filtramos solo los que tienen más de 1 aparición
        $duplicados = $archivos | Group-Object -Property Name, Length | Where-Object { $_.Count -gt 1 }

        # 5. Salida por consola en el formato requerido
        if ($duplicados.Count -gt 0) {
            foreach ($grupo in $duplicados) {
                # El grupo de propiedades contiene [Name, Length]. Extraemos el nombre.
                $nombreArchivo = $grupo.Values[0]
                
                # Write-Output envía los datos a la consola de forma limpia
                Write-Output $nombreArchivo
                foreach ($archivo in $grupo.Group) {
                    Write-Output $archivo.DirectoryName
                }
            }
        } else {
            Write-Host "No se encontraron archivos duplicados en la ruta analizada." -ForegroundColor Cyan
        }
    }
    catch {
        # 6. Manejo amigable de errores
        Write-Host ""
        Write-Host "Ups! Ocurrió un problema durante la ejecución." -ForegroundColor Red
        Write-Host "Detalle del error: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Tip: Puedes escribir 'Get-Help .\ejercicio.ps1' para ver las instrucciones de uso." -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
    finally {
        # 7. Limpieza garantizada: Este bloque se ejecuta SIEMPRE (haya éxito o error)
        if ($null -ne $script:archivoTmp -and (Test-Path $script:archivoTmp)) {
            Remove-Item -Path $script:archivoTmp -Force -ErrorAction SilentlyContinue
        }
    }
}

# Flujo principal
Buscar-Duplicados -Ruta $directorio