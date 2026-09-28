# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

#!/bin/bash

# ==============================================================================
# Variables Globales
# ==============================================================================
DIRECTORIO=""
ARCHIVO_TMP=""

# ==============================================================================
# Funciones
# ==============================================================================

# Función para limpiar los archivos temporales de forma segura
limpiar_temporales() {
    if [[ -n "$ARCHIVO_TMP" && -f "$ARCHIVO_TMP" ]]; then
        rm -f "$ARCHIVO_TMP"
    fi
}

# Trap: Ejecuta 'limpiar_temporales' al salir (sea por éxito, error o interrupción)
trap limpiar_temporales EXIT

# Función para mostrar la ayuda del script
mostrar_ayuda() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Descripción:"
    echo "  Busca archivos duplicados en un directorio y sus subdirectorios."
    echo "  Un archivo se considera duplicado si tiene el mismo nombre y tamaño."
    echo ""
    echo "Opciones:"
    echo "  -d, --directorio <ruta>   (Obligatorio) Ruta del directorio a analizar."
    echo "  -h, --help                Muestra este mensaje de ayuda y finaliza."
    echo ""
    echo "Ejemplo:"
    echo "  $0 -d /home/user/documentos"
    echo "  $0 --directorio \"/ruta/con espacios\""
}

# Función para manejar errores
manejar_error() {
    local mensaje="$1"
    echo "Error: $mensaje" >&2
    echo "Escribe '$0 --help' para ver cómo utilizar el script correctamente." >&2
    exit 1
}

# Función para analizar los parámetros ingresados
procesar_parametros() {
    # Si no se pasó ningún parámetro
    if [[ $# -eq 0 ]]; then
        manejar_error "No ingresaste ningún parámetro."
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                mostrar_ayuda
                exit 0
                ;;
            -d|--directorio)
                if [[ -z "$2" ]]; then
                    manejar_error "Falta indicar la ruta después del parámetro '$1'."
                fi
                DIRECTORIO="$2"
                shift 2
                ;;
            *)
                manejar_error "El parámetro '$1' no es válido."
                ;;
        esac
    done
}

# Función para realizar el procesamiento principal
buscar_duplicados() {
    # 1. Validaciones del directorio
    if [[ -z "$DIRECTORIO" ]]; then
        manejar_error "El parámetro obligatorio -d (o --directorio) no está presente."
    fi

    if [[ ! -d "$DIRECTORIO" ]]; then
        manejar_error "La ruta ingresada ('$DIRECTORIO') no existe o no es una carpeta."
    fi

    if [[ ! -r "$DIRECTORIO" ]]; then
        manejar_error "No tienes permisos suficientes para leer la carpeta '$DIRECTORIO'."
    fi

    # 2. Creación del archivo temporal en /tmp
    ARCHIVO_TMP=$(mktemp /tmp/duplicados_XXXXXX.tmp) || manejar_error "Ocurrió un problema al crear el archivo temporal de trabajo."

    # 3. Obtención de datos: Usamos 'find' y 'ls -nl'. LC_ALL=C estandariza la salida del ls.
    # El archivo temporal guardará la salida del ls para que AWK la procese.
    if ! LC_ALL=C find "$DIRECTORIO" -type f -exec ls -nl {} + > "$ARCHIVO_TMP" 2>/dev/null; then
        echo "Advertencia: Algunos archivos no pudieron ser leídos por falta de permisos, se procesarán los demás." >&2
    fi

    # 4. Procesamiento con AWK
    awk '
    {
        # En la salida estándar de ls -nl, el campo 5 es el tamaño
        size = $5
        
        # El campo 9 en adelante es la ruta completa (se hace un loop por si la ruta tiene espacios)
        fullpath = $9
        for (i=10; i<=NF; i++) {
            fullpath = fullpath " " $i
        }
        
        # Buscar la última barra "/" para separar la ruta del nombre del archivo
        n = length(fullpath)
        last_slash = 0
        for (i = n; i >= 1; i--) {
            if (substr(fullpath, i, 1) == "/") {
                last_slash = i
                break
            }
        }
        
        # Extraer directorio y nombre del archivo
        if (last_slash == 0) {
            dirpath = "."
            filename = fullpath
        } else {
            dirpath = substr(fullpath, 1, last_slash - 1)
            if (dirpath == "") dirpath = "/"
            filename = substr(fullpath, last_slash + 1)
        }
        
        # Creamos una clave única basada en nombre + tamaño
        key = filename "|" size
        
        # Guardamos los datos en arrays
        count[key]++
        paths[key, count[key]] = dirpath
        names[key] = filename
    }
    END {
        # Recorremos el registro e imprimimos los duplicados
        for (k in count) {
            if (count[k] > 1) {
                print names[k]
                for (i = 1; i <= count[k]; i++) {
                    print paths[k, i]
                }
            }
        }
    }' "$ARCHIVO_TMP"
}

# ==============================================================================
# Flujo principal de ejecución
# ==============================================================================
procesar_parametros "$@"
buscar_duplicados