# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

#!/bin/bash

# ==============================================================================
# Funciones
# ==============================================================================

mostrar_ayuda() {
    echo "Uso: $0 [OPCIONES]"
    echo "Monitorea un directorio buscando archivos duplicados para comprimirlos."
    echo ""
    echo "Opciones:"
    echo "  -d, --directorio RUT  Directorio a monitorear."
    echo "  -s, --salida RUTA     Directorio donde se guardarán los backups (.tar.gz)."
    echo "  -k, --kill            Detiene el demonio ejecutándose en el directorio."
    echo "  -h, --help            Muestra esta ayuda."
}

manejar_error() {
    echo -e "\n[ERROR] $1" >&2
    exit 1
}

# ==============================================================================
# Parseo de parámetros
# ==============================================================================

KILL=0
DAEMON_MODE=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--directorio) MONITOR_DIR="$2"; shift ;;
        -s|--salida) SALIDA_DIR="$2"; shift ;;
        -k|--kill) KILL=1 ;;
        -h|--help) mostrar_ayuda; exit 0 ;;
        --daemon) DAEMON_MODE=1 ;; # Flag interno para el proceso en 2do plano
        *) manejar_error "Parámetro no reconocido: $1. Use -h para ayuda." ;;
    esac
    shift
done

# ==============================================================================
# Validaciones iniciales
# ==============================================================================

if [[ -z "$MONITOR_DIR" ]]; then
    manejar_error "El parámetro -d / --directorio es obligatorio."
fi

# Convertir a rutas absolutas para evitar problemas al correr en background
MONITOR_DIR=$(readlink -m "$MONITOR_DIR")
if [[ ! -d "$MONITOR_DIR" ]]; then
    manejar_error "El directorio a monitorear '$MONITOR_DIR' no existe."
fi

# Identificador único para el demonio de este directorio
DIR_HASH=$(echo -n "$MONITOR_DIR" | md5sum | awk '{print $1}')
PID_FILE="/tmp/demonio_bash_${DIR_HASH}.pid"

# Lógica de detención (--kill)
if [[ $KILL -eq 1 ]]; then
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null; then
            kill "$PID"
            rm -f "$PID_FILE"
            echo "Demonio (PID $PID) monitoreando '$MONITOR_DIR' detenido correctamente."
            exit 0
        else
            rm -f "$PID_FILE"
            manejar_error "El proceso del demonio no existe, pero se limpió el archivo PID."
        fi
    else
        manejar_error "No hay ningún demonio ejecutándose para el directorio '$MONITOR_DIR'."
    fi
fi

if [[ -z "$SALIDA_DIR" ]]; then
    manejar_error "El parámetro -s / --salida es obligatorio para iniciar el monitoreo."
fi

SALIDA_DIR=$(readlink -m "$SALIDA_DIR")
if [[ ! -d "$SALIDA_DIR" ]]; then
    mkdir -p "$SALIDA_DIR" || manejar_error "No se pudo crear el directorio de salida."
fi

if ! command -v inotifywait &> /dev/null; then
    manejar_error "La herramienta 'inotifywait' no está instalada. Instálela usando inotify-tools."
fi

# ==============================================================================
# Lógica de Demonio (Background)
# ==============================================================================
# Obtener la ruta absoluta real de este script
SCRIPT_PATH=$(readlink -f "$0")

if [[ $DAEMON_MODE -eq 0 ]]; then
    # Validación estricta para evitar dobles ejecuciones
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        # kill -0 no mata el proceso, solo verifica a nivel kernel si está vivo
        if kill -0 "$PID" 2>/dev/null; then
            manejar_error "Ya existe un demonio ejecutándose para este directorio (PID: $PID)."
        else
            # El proceso murió inesperadamente, limpiamos el archivo huérfano
            rm -f "$PID_FILE" 
        fi
    fi

    # Lanzar en background
    nohup bash "$SCRIPT_PATH" -d "$MONITOR_DIR" -s "$SALIDA_DIR" --daemon > /dev/null 2>&1 &
    NUEVO_PID=$!
    echo $NUEVO_PID > "$PID_FILE"
    echo "Demonio iniciado exitosamente en 2do plano (PID $NUEVO_PID)."
    exit 0
fi

# ==============================================================================
# Proceso principal (Solo ejecuta el demonio en background)
# ==============================================================================

TEMP_FILE="/tmp/archivos_temp_$$.txt"
trap 'rm -f "$TEMP_FILE" "$PID_FILE"' EXIT ERR

# Solución al "doble proceso": Sustitución de procesos en lugar de Pipe (|)
while read -r NUEVO_ARCHIVO; do
    if [[ ! -f "$NUEVO_ARCHIVO" ]]; then
        continue
    fi
    
    HASH_NUEVO=$(md5sum "$NUEVO_ARCHIVO" | awk '{print $1}')
    
    find "$MONITOR_DIR" -type f ! -path "$NUEVO_ARCHIVO" > "$TEMP_FILE"
    
    while read -r ARCHIVO_EXISTENTE; do
        HASH_EXISTENTE=$(md5sum "$ARCHIVO_EXISTENTE" | awk '{print $1}')
        
        if [[ "$HASH_NUEVO" == "$HASH_EXISTENTE" ]]; then
            TIMESTAMP=$(date +%Y%m%d-%H%M%S)
            TAR_FILE="$SALIDA_DIR/${TIMESTAMP}.tar.gz"
            
            if tar -czf "$TAR_FILE" -C "$(dirname "$NUEVO_ARCHIVO")" "$(basename "$NUEVO_ARCHIVO")" 2>/dev/null; then
                echo "[$TIMESTAMP] DUPLICADO: '$NUEVO_ARCHIVO' es copia de '$ARCHIVO_EXISTENTE'. Archivado en $TAR_FILE" >> "$SALIDA_DIR/demonio.log"
                rm -f "$NUEVO_ARCHIVO"
            fi
            break
        fi
    done < "$TEMP_FILE"
# Se inyecta la salida del inotifywait directamente al while sin crear subshells
done < <(inotifywait -m -r -e close_write,moved_to --format '%w%f' "$MONITOR_DIR" 2>/dev/null)
