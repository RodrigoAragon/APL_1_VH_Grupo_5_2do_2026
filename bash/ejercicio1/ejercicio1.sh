# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO
#!/bin/bash

opciones=$(getopt -o d:a:ph --l directorio:,archivo:,pantalla,help -- "$@" 2> /dev/null)
# si getopt falla sale con error
if [ "$?" != "0" ]
then
    echo "opciones incorrectas"
    exit 1
fi


eval set -- "$opciones"

directorio=""
archivo_salida=""
pantalla=false
ganadores=(-1 -1 -1 -1 -1)

function mostrar_ayuda() 
{
    echo "Uso: $0 -d <directorio> [-a <archivo> | -p]"
    echo "  -d, --directorio  Ruta del directorio con los archivos CSV."
    echo "  -a, --archivo     Ruta del archivo JSON de salida."
    echo "  -p, --pantalla    Muestra la salida en consola."
    echo "  -h, --help        Muestra esta ayuda."
    exit 1 #le pongo 1 pero no se si iria mejor 0
}

function validarGanadores()
{
    for(( i = 0 ; i < 5 ; i++))
    do
        if [[ ${ganadores[i]} < 0 || ${ganadores[i]} > 99 ]]
        then
            echo "ganadores invalidos"
            exit 1
        fi
    done
}

function contarGanadores()
{
    if [[ "${ganadores[0]}" == "$n1" ]]
    then
        ((contador++))
    fi
    if [[ "${ganadores[1]}" == "$n2" ]]
    then
        ((contador++))
    fi
    if [[ "${ganadores[2]}" == "$n3" ]]
    then
        ((contador++))
    fi
    if [[ "${ganadores[3]}" == "$n4" ]]
    then
        ((contador++))
    fi
    if [[ "${ganadores[4]}" == "$n5" ]]
    then
        ((contador++))
    fi
}

function agregarString()
{
    case $contador in
        5)
            if [[ $primero5 == true ]]
            then
                aciertos5+="{\"agencia\":\"${nombre_agencia}\",\"jugada\":\"${id}\"}"
                primero5=false
            else
                aciertos5+=",{\"agencia\":\"${nombre_agencia}\",\"jugada\":\"${id}\"}"
            fi
            ;;
        4)
            if [[ $primero4 == true ]]
            then
                aciertos4+="{\"agencia\":\"${nombre_agencia}\",\"jugada\":\"${id}\"}"
                primero4=false
            else
                aciertos4+=",{\"agencia\":\"${nombre_agencia}\",\"jugada\":\"${id}\"}"
            fi
            ;;
        3)
            if [[ $primero3 == true ]]
            then
                aciertos3+="{\"agencia\":\"${nombre_agencia}\",\"jugada\":\"${id}\"}"
                primero3=false
            else
                aciertos3+=",{\"agencia\":\"${nombre_agencia}\",\"jugada\":\"${id}\"}"
            fi
            ;;
    esac
}
#bucle de parseo
while true
do
    case "$1" in
        -d|--directorio)
            directorio="$2"
            shift 2
            ;;
        -a|--archivo)
            archivo_salida="$2"
            shift 2
            ;;
        -p|--pantalla)
            pantalla=true
            shift 1
            ;;
        -h|--help)
            mostrar_ayuda
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

#validar que se hayan enviado los parametros
#si o si directorio y pantalla o ruta de salida
if [[ $directorio == "" ]]
then
    echo "Se debe enviar una ruta de directorio con los archivos csv"
    exit 1
fi

if [[ $pantalla == false && $archivo_salida == "" ]]
then
    echo "Se debe enviar alguna forma de salida"
    exit 1;
fi

if [[ $pantalla == false && $archivo_salida == "" ]]
then
    echo "Se debe enviar alguna forma de salida"
    exit 1;
fi

if [[ $pantalla == true && $archivo_salida != "" ]]
then
    echo "Solo se puede usar una forma de salida a la vez"
    exit 1;
fi

#---fin validacion de parametros-----

#como no habla de un parametro de ganadores asumo nombre fijo
#en la carpeta de directorios

#buscar ganadores
if [[ ! -f "${directorio}/ganadores.csv" ]]
then
    echo "Error: El archivo ganadores.csv no existe en el directorio."
    exit 1
fi
#leer ganadores
ganadores=( $(awk -F',' 'NR == 1 { print $1, $2, $3, $4, $5 }' "${directorio}/ganadores.csv") )
validarGanadores
aciertos5=""
aciertos4=""
aciertos3=""
primero5=true
primero4=true
primero3=true
#recorrer todos los archivos en el directorio que se envio por -d
for arch in "$directorio"/*.csv
do
    #si es el de ganadores no hacer nada
    if [[ "$arch" == "${directorio}/ganadores.csv" ]]
    then
        #el continue hace q salte el resto del bucle
        continue
    fi
    #conseguir nombre de la agencia
    #basename saca la ruta y la extension
    nombre_agencia=$(basename "$arch" .csv)
    #el < $arch le manda al while el archivo como entrada
    #el read lo asigna a variables linea por linea
    #el while corta cuando read devuelve 1 osea q no pudo leer nada
    while IFS=',' read id n1 n2 n3 n4 n5
    do
        contador=0
        #echo "${nombre_agencia}: ${id},${n1},${n2},${n3},${n4},${n5}"
        #deja en contador la cantidad que coinciden con los ganadores leidos
        contarGanadores
        #echo $contador
        #agrega a aciertosX un string con el formato json correspondiente
        agregarString
    done < "$arch"
done

#crear JSON completo
json=""
json+="{\"5_aciertos\":["
json+="$aciertos5"
json+="],"

json+="\"4_aciertos\":["
json+="$aciertos4"
json+="],"

json+="\"3_aciertos\":["
json+="$aciertos3"
json+="]}"

#uso jq para que quede formateado mas comodo, preguntar si se puede
if [[ $pantalla == true ]]
then
    echo "$json" | jq
    exit 0
else
    echo "$json" | jq > "$archivo_salida"
fi

exit 0
