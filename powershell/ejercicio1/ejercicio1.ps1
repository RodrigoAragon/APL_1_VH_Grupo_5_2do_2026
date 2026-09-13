# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

<#
.Synopsis
   Esta funcion obtiene los ganadores de la loteria, organizando los resultados por agencia y cantidad de aciertos.
.DESCRIPTION
   Dentro de una misma ruta, procesa los archivos CSV de las distintas agencias y los compara con las jugadas ganadoras.
   Luego puede generar un CSV para guardarlo en nuevo archivo o mostrar los resultados por pantalla en formato JSON.
.EXAMPLE
   .\ejercicio1.ps1 -directorio "C:\ArchivosCSV\" -archivo "Resultados.csv"
.EXAMPLE
   .\ejercicio1.ps1 -directorio "C:\ArchivosCSV\" -pantalla
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>


Param(
    [Parameter(Mandatory=$true)]
    [string]$directorio,

    [Parameter(Mandatory=$true, ParameterSetName="Archivo")]
    [string]$archivo,

    [Parameter(Mandatory=$true, ParameterSetName="Pantalla")]
    [switch]$pantalla

)

#Vamos a tener que levantar y procesar todos los .csv de un directorio, así que los leemos con Get-ChildItem.
#Excluimos a Ganadora.csv.
#De ésta manera no nos importan los nombres de las agencias, no hace falta que vengan con números.

$archivos = Get-ChildItem $directorio -Filter "*.csv" | Where-Object { $_.Name -ne "Ganadora.csv" }
$ganadora = Import-Csv "$directorio/Ganadora.csv" -Header n1,n2,n3,n4,n5

# Convertimos en un array
$numerosGanadores = @(
    $ganadora.n1
    $ganadora.n2
    $ganadora.n3
    $ganadora.n4
    $ganadora.n5
)

#Creamos arrays vacios para luego acumular los exitos que tengamos
$cincoAciertos = @()
$cuatroAciertos = @()
$tresAciertos = @()



Write-Output "Ruta ganadora: $directorio/Ganadora.csv"
Write-Output "Contenido:"
Get-Content "$directorio/Ganadora.csv"

foreach ($a in $archivos)        #Por Agencia
{
   $jugadas = Import-Csv $a.FullName -Header id,n1,n2,n3,n4,n5

   foreach ($jugada in $jugadas)  #Por Jugada     
   {
      <#
      Write-Output "Jugada: $($jugada.id)"
      Write-Output "Numeros: $($jugada.n1), $($jugada.n2), $($jugada.n3), $($jugada.n4), $($jugada.n5)"

      Write-Output "Ganadora:"
      Write-Output "$($ganadora.n1), $($ganadora.n2), $($ganadora.n3), $($ganadora.n4), $($ganadora.n5)"
      #>

      $numerosJugados = @(
        $jugada.n1
        $jugada.n2
        $jugada.n3
        $jugada.n4
        $jugada.n5
      )

      $aciertos = 0

      for ($i = 0; $i -lt 5; $i++)
      {
         if ($numerosJugados[$i] -eq $numerosGanadores[$i])
         {
            $aciertos++
         }

      }

      if ($aciertos -ge 3)
      {
         $resultado = [PSCustomObject]@{
            agencia = $a.BaseName
            jugada  = $jugada.id
         }

         if ($aciertos -eq 5)
         {
            $cincoAciertos += $resultado
         }
         elseif ($aciertos -eq 4)
         {
            $cuatroAciertos += $resultado
         }
         elseif ($aciertos -eq 3)
         {
            $tresAciertos += $resultado
         }
      }

   }
}

$resultadoFinal = [PSCustomObject]@{
    "5_aciertos" = $cincoAciertos
    "4_aciertos" = $cuatroAciertos
    "3_aciertos" = $tresAciertos
}


if ($archivo)
{
    $resultadoFinal | ConvertTo-Json -Depth 3 | Set-Content $archivo
}
elseif ($pantalla)
{
    $resultadoFinal | ConvertTo-Json -Depth 3
}
