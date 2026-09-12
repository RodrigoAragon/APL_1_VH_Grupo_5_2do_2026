# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO
<#
.Synopsis
    Procesa archivos de texto plano que contienen matrices para realizar operaciones de producto escalar o trasposición.

.Description
    Este script lee una matriz desde un archivo de texto plano utilizando un carácter separador personalizado.
    Valida la integridad de la matriz (columnas consistentes, valores numéricos válidos) y ejecuta exclusivamente
    una de dos operaciones posibles: un producto escalar por un valor entero o la trasposición de la matriz.
    El resultado se almacena automáticamente en un archivo con el formato "salida.nombreArchivoEntrada"
    dentro del mismo directorio del archivo original.

.Parameter matriz
    Ruta obligatoria del archivo de texto plano que contiene la matriz a procesar.

.Parameter producto
    Valor entero opcional para realizar el producto escalar de la matriz.
    Es mutuamente excluyente con el parámetro -trasponer.

.Parameter trasponer
    Interruptor (switch) opcional que indica que se debe realizar la operación de trasposición sobre la matriz.
    Es mutuamente excluyente con el parámetro -producto.

.Parameter separador
    Carácter obligatorio utilizado para separar las columnas dentro del archivo de matriz.
    Debe ser estrictamente un único carácter y no puede ser un número (0-9) ni el símbolo menos ('-').

.Example
    .\ProcesarMatriz.ps1 -matriz "C:\datos\matriz.txt" -producto 5 -separador "|"
    Realiza el producto escalar de la matriz multiplicando cada valor por 5, utilizando el carácter pipe "|"
    como separador de columnas.
#>

Param
(
#hay 3 conjuntos 1-producto 2-trasponer 3-help
#si es conjunto 1 pide si o si matriz, prod y separador
#si es conjunto 2 pide si o si matriz, trasponer y separador
#si es conjunto 3 pide si o si help
    [Parameter(Mandatory=$true, ParameterSetName="producto")]
    [Parameter(Mandatory=$true, ParameterSetName="trasponer")]
    [String]$matriz,

    [Parameter(Mandatory=$true, ParameterSetName="producto")]
    [double]$producto,

    [Parameter(Mandatory=$true, ParameterSetName="trasponer")]
    [switch]$trasponer,

    [Parameter(Mandatory=$true, ParameterSetName="producto")]
    [Parameter(Mandatory=$true, ParameterSetName="trasponer")]
    [ValidateLength(1, 1)]
    [ValidatePattern('^[^0-9\-]$')]
    [String]$separador,

    [Parameter(Mandatory=$true, ParameterSetName="help")]
    [switch]$help
)

if ($help -eq $true)
{
    write-host "Uso: .\ejercicio2.ps1 -matriz <archivo> (-producto <valor> | -trasponer) -separador <caracter>"
    write-host " -matriz Ruta del archivo .txt que contiene la matriz."
    write-host " -producto Valor entero por el cual multiplicar la matriz."
    write-host " -trasponer Realiza la trasposicion de la matriz."
    write-host " -separador Caracter utilizado para separar las columnas."
    write-host " -help Muestra esta ayuda."
    exit 1
}
if ($matriz -notmatch '\.txt$')
{
    write-host "El archivo debe tener obligatoriamente la extension .txt"
    exit 1
}
#verificar que exista el archivo de la matriz
if ((Test-Path -Path $matriz -PathType Leaf) -eq $false)
{
    write-host "El archivo especificado no existe o no es valido: $matriz"
    exit 1
}

#fin validar parametros

#validar misma cantidad de cols en todas las filas

#filas queda como un array donde en cada posicion hay 1 linea del archivo
#get content separa por \n cada elemento
$filas = Get-Content $matriz
#separa la primer fila en cada componente, usando como separador el separador que se le paso
#se usa [regex]::Escape($separador) para que de la forma de un caracter literal y no una expresion. EJ: el |
$columnas = $filas[0] -split [regex]::Escape($separador)
$cantColumnas = $columnas.Count #count da la cantidad de elementos

foreach ($fila in $filas)
{
    #fila es la linea entera leida hasta el \n
    #colLeida queda como un array donde cada pos es un elemento leido
    $colsLeidas = $fila -split [regex]::Escape($separador)

    if ($colsLeidas.Count -ne $cantColumnas)
    {
        Write-Host "La matriz no tiene la misma cantidad de columnas en todas sus filas"
        exit 1
    }
    #validar si alguna pos tiene algo no numerico
    foreach ($columna in $colsLeidas)
    {
        #si esta vacia que tire error de una
        if ($columna -eq "")
        {
            Write-Host "La matriz contiene una columna vacia"
            exit 1
        }
        #-as castea a double, si tiene algo no numerico deja null
        if ($columna -as [double] -eq $null)
        {
            Write-Host "La matriz contiene un valor que no es numerico"
            exit 1
        }
    }
}
#si pide producto
if ($PSBoundParameters.ContainsKey("producto"))
{
    $arch = ""
    foreach ($fila in $filas)
    {
        $filaStr = ""
        $colsLeidas = $fila -split [regex]::Escape($separador)
        foreach ($columna in $colsLeidas)
        {
            $valor = ($columna -as [double]) * $producto
            $filaStr += "${valor}$separador"
        }
        #sacar ultimo elemento (el separador extra)
        $filaStr = $filaStr.TrimEnd([regex]::Escape($separador))
        #agregar a arch con salto de linea
        $arch += "$filaStr`n"
    }
    #crear nombre de arch de salida
    #splith path separa en ruta al archivo y nombre
    #con -leaf nos quedamos con el nombre del archivo
    $nombre = Split-Path $matriz -Leaf
    #quedarnos directorio solo
    $directorio = Split-Path $matriz
    #si el directorio es vacio pq se le mando el archivo como "matriz.txt" agregarle el .\
    if($directorio -eq "")
    {
        $directorio = ".\"
    }
    #crear salida directorio + nuevo nombre arch
    $salida = Join-Path $directorio "salida.$nombre"
    #sacar el ultimo \n pq set content lo agrega solo
    $arch = $arch.TrimEnd("`n")
    Set-Content $salida $arch
    exit 0
}
if ($PSBoundParameters.ContainsKey("trasponer"))
{
    $arch = ""
    $columnas = @() #array vacio
    #inicializar cada pos como vacio
    for ($i = 0; $i -lt $cantColumnas; $i++)
    {
        #$columnas += "" crea un elemento nuevo en el array 
        $columnas += ""
    }
    #cargar en columnas en cada pos una fila entera como string
    #osea si leo la fila 1|2|3
    #cargar en columnas[0] = 1|, columnas[1] = 2|, columnas[2] = 3|
    foreach ($fila in $filas)
    {
        $colsLeidas = $fila -split [regex]::Escape($separador)
        for ($i = 0; $i -lt $cantColumnas; $i++)
        {
            $columnas[$i] += "$($colsLeidas[$i])$separador"
        }
    }
    #limpiar el | que quedo al final de cada fila
    for ($i = 0; $i -lt $cantColumnas; $i++)
    {
        $columnas[$i] = $columnas[$i].TrimEnd([regex]::Escape($separador))
    }
    #pasar a $arch con un \n al final de cada fila
    for ($i = 0; $i -lt $cantColumnas; $i++)
    {
        $arch += $columnas[$i]
        $arch +="`n"
    }
    #crear nombre de arch de salida
    #splith path separa en ruta al archivo y nombre
    #con -leaf nos quedamos con el nombre del archivo
    $nombre = Split-Path $matriz -Leaf
    #quedarnos directorio solo
    $directorio = Split-Path $matriz
    #si el directorio es vacio pq se le mando el archivo como "matriz.txt" agregarle el .\
    if($directorio -eq "")
    {
        $directorio = ".\"
    }
    #crear salida directorio + nuevo nombre arch
    $salida = Join-Path $directorio "salida.$nombre"
    #sacar el ultimo \n pq set content lo agrega solo
    $arch = $arch.TrimEnd("`n")
    Set-Content $salida $arch
    exit 0
}
#si no pide producto ni trasponer da error
#nunca deberia salir por este exit
write-host "Estado erroneo"
exit 1
