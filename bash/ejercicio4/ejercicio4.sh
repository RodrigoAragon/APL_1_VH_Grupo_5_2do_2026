#!/bin/bash
# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

# ==============================================================================
# Verificación de dependencias
# ==============================================================================
if ! command -v inotifywait &> /dev/null; then
    echo "Error: Se requiere 'inotify-tools'. Instálalo con 'sudo apt install inotify-tools'." >&2
    exit 1
fi

DIRECTORIO=""
SALIDA=""
KILL_MODE=0
DAEMON_MODE=0

# Muestra la ayuda del script.
mostrar_ayuda() {
    echo '
Uso:
  ./ejercicio4.sh -d DIRECTORIO -s SALIDA
  ./ejercicio4.sh -d DIRECTORIO -k

Parametros:
  -d, --directorio   Directorio a monitorear.
  -s, --salida       Directorio donde se crean backups .tar.gz.
  -k, --kill         Detiene el demonio iniciado para ese directorio.
  -h, --help         Muestra esta ayuda.

Requisito:
  Para funcionar necesita tener instalado inotify-tools, que aporta inotifywait.'
  exit 0
}

# Procesar parámetros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--directorio) DIRECTORIO="$2"; shift 2 ;;
        -h|--help) mostrar_ayuda; shift ;;
        -s|--salida) SALIDA="$2"; shift 2 ;;
        -k|--kill) KILL_MODE=1; shift ;;
        --daemon_mode) DAEMON_MODE=1; shift ;; # Interno
        *) echo "Parámetro inválido: $1"; exit 1 ;;
    esac
done

if [[ -z "$DIRECTORIO" ]]; then
    echo "Error: El parámetro -d (directorio) es obligatorio." >&2
    exit 1
fi

# Convertir a ruta absoluta
if [[ ! -d "$DIRECTORIO" ]]; then
    echo "Error: El directorio a monitorear no existe: $DIRECTORIO" >&2
    exit 1
fi
DIRECTORIO=$(realpath "$DIRECTORIO") || exit 1
HASH_DIR=$(echo -n "$DIRECTORIO" | md5sum | awk '{print $1}')
PID_FILE="/tmp/demonio_bash_${HASH_DIR}.pid"
ERROR_FILE="/tmp/errores_bash_fondo_${HASH_DIR}.log"

# ==============================================================================
# Lógica de detención (-kill)
# ==============================================================================
if [[ $KILL_MODE -eq 1 ]]; then
    if [[ -f "$PID_FILE" ]]; then
        PID_DEMONIO=$(cat "$PID_FILE")
        if kill -0 "$PID_DEMONIO" 2>/dev/null; then
            kill -TERM "$PID_DEMONIO" || exit 1
            # El demonio elimina el PID al finalizar la limpieza.
            for (( intento=0; intento<100; intento++ )); do
                [[ ! -f "$PID_FILE" ]] && break
                sleep 0.1
            done
            if [[ -f "$PID_FILE" ]] && kill -0 "$PID_DEMONIO" 2>/dev/null; then
                echo "Error: El demonio no termino de detenerse." >&2
                exit 1
            fi
            echo "Demonio Bash (PID $PID_DEMONIO) detenido exitosamente."
        else
            echo "El proceso ya no estaba en ejecución."
        fi
        rm -f "$PID_FILE"
        rm -f "/tmp/archivos_temp_bash_${PID_DEMONIO}.txt" "$ERROR_FILE"
    else
        echo "No hay ningún demonio ejecutándose para ese directorio."
    fi
    exit 0
fi

if [[ -z "$SALIDA" ]]; then
    echo "Error: El parámetro -s (salida) es obligatorio." >&2
    exit 1
fi

SALIDA=$(realpath -m "$SALIDA")
if ! mkdir -p "$SALIDA"; then
    echo "Error: No se pudo crear o acceder al directorio de salida: $SALIDA" >&2
    exit 1
fi

# ==============================================================================
# Lógica de lanzamiento en 2do plano (Daemonización)
# ==============================================================================
if [[ $DAEMON_MODE -eq 0 ]]; then
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Error: Ya existe un demonio ejecutándose para este directorio." >&2
        exit 1
    fi

    # Se relanza en background aislando los flujos (nohup)
    nohup bash "$0" -d "$DIRECTORIO" -s "$SALIDA" --daemon_mode > /dev/null 2> "$ERROR_FILE" &
    PID_NUEVO=$!
    echo "$PID_NUEVO" > "$PID_FILE"
    echo "Demonio Bash iniciado exitosamente en 2do plano (PID $PID_NUEVO)."
    exit 0
fi

# ==============================================================================
# Proceso principal (Demonio activo)
# ==============================================================================
# Archivo temporal según requerimientos
TEMP_FILE="/tmp/archivos_temp_bash_$$.txt"
WATCH_PID=""
limpiar() {
    trap '' TERM INT
    if [[ -n "$WATCH_PID" ]]; then
        kill "$WATCH_PID" 2>/dev/null
        wait "$WATCH_PID" 2>/dev/null
    fi
    exec 3<&-
    rm -f "$TEMP_FILE" "$ERROR_FILE" "$PID_FILE"
}
trap limpiar EXIT
trap 'exit 0' TERM INT

# close_write: Detecta cuando un archivo se termina de crear, copiar o guardar.
# moved_to: Detecta guardados atómicos (cuando editores de texto renombran archivos temporales).
# La lectura ocurre en el proceso principal; conservamos el PID del monitor.
exec 3< <(exec inotifywait -m -r -e close_write,moved_to --format '%w%f' "$DIRECTORIO" 2>/dev/null)
WATCH_PID=$!
while IFS= read -r pathNuevo <&3; do
    
    if [[ -f "$pathNuevo" ]]; then
        # OBTENER NOMBRE Y TAMAÑO DEL ARCHIVO NUEVO
        nombreNuevo=$(basename "$pathNuevo")
        tamanoNuevo=$(stat -c%s "$pathNuevo")

        # BUSCAR DUPLICADO: Excluimos la ruta exacta (-not -path), pero pedimos que coincida -name y -size.
        # head -n 1 asegura que tomamos el primer duplicado que encuentre y cortamos la búsqueda.
        archivoDuplicado=$(find "$DIRECTORIO" -type f -not -path "$pathNuevo" -name "$nombreNuevo" -size "${tamanoNuevo}c" | head -n 1)

        if [[ -n "$archivoDuplicado" ]]; then
            TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
            TAR_FILE="$SALIDA/$TIMESTAMP.tar.gz"
            DIR_NUEVO=$(dirname "$pathNuevo")

            # Comprimir (navegamos al directorio origen para no guardar toda la estructura de carpetas)
            tar -czf "$TAR_FILE" -C "$DIR_NUEVO" "$nombreNuevo"

            LOG_MSG="[$TIMESTAMP] DUPLICADO: '$pathNuevo' es copia de '$archivoDuplicado'. Archivado en $TAR_FILE"
            echo "$LOG_MSG" >> "$SALIDA/demonio.log"
            echo "$LOG_MSG" >> "$TEMP_FILE"

            # Eliminar el archivo duplicado (el nuevo)
            rm -f "$pathNuevo"
        fi
    fi
done