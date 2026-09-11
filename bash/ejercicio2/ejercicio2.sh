# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO
#!/bin/bash

opciones=$(getopt -o m:p:s:th --l matriz:,producto:,transponer,separador:,help -- "$@" 2> /dev/null)
# si getopt falla sale con error
if [ "$?" != "0" ]
then
    echo "opciones incorrectas"
    exit 1
fi
eval set -- "$opciones"
matriz_arch=""
producto_nro=0
separador_ch=''
producto=false
trasponer=false
separador=false
function mostrar_ayuda() 
{
    echo "Uso: $0 -m <archivo> -s <caracter> [-t | -p <entero>]"
    echo "  -m, --matriz      Ruta del archivo matriz."
    echo "  -s, --separador   Caracter que separa los valores en el archivo."
    echo "  -t, --trasponer   Indica operacion de trasponer."
    echo "  -p, --producto    Indica operacion de producto escalar."
    echo "  -h, --help        Muestra esta ayuda."
    exit 1 #le pongo 1 pero no se si es mejor 0
}

#bucle de parseo
while true
do
    case "$1" in
        -m|--matriz)
            matriz_arch="$2"
            shift 2
            ;;
        -p|--producto)
            producto_nro=$2
            producto=true
            shift 2
            ;;
        -s|--separador)
            separador_ch="$2"
            separador=true
            shift 2
            ;;
        -h|--help)
            mostrar_ayuda
            shift 1
            ;;
        -t|--trasponer)
            trasponer=true
            shift 1
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error"
            exit 1
            ;;
    esac
done
if [[ $matriz_arch == "" ]]
then
    echo "Se debe enviar una ruta de archivo con la matriz"
    exit 1
fi
if [[ $separador == false ]]
then
    echo "Se debe enviar un caracter separador para la matriz"
    exit 1
fi
if [[ $separador_ch == '-' ]]
then
    echo "Se debe enviar un caracter separador para la matriz que no sea un -"
    exit 1
fi
if [[ $producto == false && $trasponer == false ]]
then
    echo "Se debe enviar al menos una operacion, producto o trasposicion"
    exit 1
fi
if [[ $producto == true && $trasponer == true ]]
then
    echo "Se debe enviar solo una operacion, producto o trasposicion"
    exit 1
fi

#fin parametros
if [ ! -s "$matriz_arch" ]
then
    echo "No existe o esta vacio el archivo enviado para la matriz "
    exit 1
fi

#ver la cantidad de elementos de la primer fila
#meto todo en un vector con read
#si la cantidad de elementos de otra fila != cantidad elementos primera
#la matriz esta mal
cantAnterior=0
primeroLeido=true
while IFS="$separador_ch" read -a vector
do
    cantidadFilaAct=${#vector[*]}
    if [[ $primeroLeido == true ]]
    then
        cantAnterior=$cantidadFilaAct
        primeroLeido=false
    else
        if [ $cantAnterior -ne $cantidadFilaAct ]
        then
            echo "cantidad de elementos diferentes entre filas"
            exit 1
        fi
    fi
done < "$matriz_arch"


if [ $? -ne 0 ]
then
    echo "El archivo de matriz es invalido"
    exit 1
fi
#uso awk porque no encontre una forma mejor de hacerlo directamente en bash puro
#recorre y en cada linea hace un for para ver cada campo, si el campo no tiene
#el formato dado (puede empezar con -, tener 1 o mas valores numericos, coma o punto y 1 o mas numericos)
awk -F"${separador_ch}" '
    {
        for (i = 1; i <= NF; i++)
        {
            if ($i !~ /^-?[0-9]+([.,][0-9]+)?$/)
            {
                print "Error en linea " NR ", columna " i ": el valor \"" $i "\" no es numerico."
                exit 1
            }
        }
    }
' "$matriz_arch"

if [ $? -ne 0 ]
then
    echo "El archivo de matriz es invalido"
    exit 1
fi

#fin de validaciones sobre la matriz
#si pide producto
#leer 1 por 1 y meter multiplicado en otro archivo
#asumo q producto escalar se refiere a producto por un escalar
directorioGuardar=$(dirname "$matriz_arch")
resultadoProducto=""
if [[ $producto == true ]]
then
    while IFS=$separador_ch read -a vec
    do
        #en vec hay 1 linea sola pero puesta como elementos
        filaAct=""
        for (( i=0; i<${#vec[*]}; i++))
        do
            resultado=$(($producto_nro * ${vec[i]}))
            if [[ $i -eq 0 ]]
            then
                filaAct+="${resultado}"
            else
                filaAct+="|${resultado}"
            fi
        done
        resultadoProducto+="${filaAct}"$'\n'
    done < "$matriz_arch"
    echo "$resultadoProducto" > "${directorioGuardar}/salida.${matriz_arch}"
    echo "Resultado guardado en ${directorioGuardar}/salida.${matriz_arch}"
    exit 0
fi

#si pide transponer
#es crear 1 vector de n lugares y en cada uno tener un string q agrega la fila leida
#pero en cada pos un lugar
#EJ: leo 1 2. en la pos[0] agrego 1, en la pos[1] agrego 2 y dps cada pos del vector es una fila a imprimir
if [[ $trasponer == true ]]
then
    primeraLeida=true
    filasNuevas[0]=""
    while IFS=$separador_ch read -a vec
    do
        #en vec hay 1 linea sola pero puesta como elementos
        for (( i=0; i<${#vec[*]}; i++ ))
        do
            if [[ $primeraLeida == true ]]
            then
                filasNuevas[$i]="${vec[$i]}"
            else
                filasNuevas[$i]+="|${vec[$i]}"
            fi
        done
        primeraLeida=false
    done < "$matriz_arch"
fi
filasUnidas=""
for (( i=0; i<${#filasNuevas[*]}; i++))
do
    filasUnidas+="${filasNuevas[$i]}"$'\n'
done
echo "$filasUnidas" > "${directorioGuardar}/salida.${matriz_arch}"
echo "Resultado guardado en ${directorioGuardar}/salida.${matriz_arch}"
exit 0
