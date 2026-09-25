# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN ALEJANDRO

#!/bin/bash

# Función para mostrar la ayuda del script
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo "Consulta información de Star Wars a través de swapi.tech."
    echo ""
    echo "Opciones:"
    echo "  -p, --people IDs   Id o ids de los personajes a buscar separados por coma (ej: 1,2)."
    echo "  -f, --film IDs     Id o ids de las películas a buscar separados por coma (ej: 1,2)."
    echo "  -h, --help         Muestra esta ayuda."
}

# Inicialización de variables
PEOPLE=""
FILMS=""

# Procesamiento de parámetros (permite cualquier orden)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--people)
            PEOPLE="$2"
            shift 2
            ;;
        -f|--film)
            FILMS="$2"
            shift 2
            ;;
        *)
            echo "Error: Parámetro desconocido '$1'. Use -h o --help para más información."
            exit 1
            ;;
    esac
done

# Validación de parámetros obligatorios
if [[ -z "$PEOPLE" && -z "$FILMS" ]]; then
    echo "Error: Faltan parámetros. Debe proveer al menos un personaje (-p) o una película (-f)."
    exit 1
fi

# Verificación de dependencias (jq es indispensable para JSON en bash)
if ! command -v jq &> /dev/null; then
    echo "Lo sentimos, el comando 'jq' no está instalado y es necesario para leer los datos. Instálelo primero."
    exit 1
fi

# Configuración de temporales y caché
TEMP_FILE="/tmp/ejercicio5_temp$$.json"
CACHE_DIR="/tmp/ejercicio5_cache"
mkdir -p "$CACHE_DIR" # Crea el directorio de caché si no existe

# Limpieza de archivos temporales (se ejecuta en éxito o error)
cleanup() {
    if [[ -f "$TEMP_FILE" ]]; then
        rm -f "$TEMP_FILE"
    fi
}
trap cleanup EXIT INT TERM

# Función principal para obtener y mostrar datos
fetch_and_show() {
    local type="$1"
    local ids="$2"

    # Permite iterar sobre los IDs separados por coma
    IFS=',' read -r -a id_array <<< "$ids"
    
    for id in "${id_array[@]}"; do
        # Limpiamos espacios en blanco accidentales
        id=$(echo "$id" | xargs)
        [[ -z "$id" ]] && continue
        
        local cache_file="$CACHE_DIR/${type}_${id}.json"
        
        # Lógica de Caché
        if [[ -f "$cache_file" ]]; then
            cp "$cache_file" "$TEMP_FILE"
        else
            local url="https://www.swapi.tech/api/${type}/${id}"
            
            # Si curl falla (-f aborta en HTTP errors), se corta la ejecución del script
            if ! curl -s -f -o "$TEMP_FILE" "$url"; then
                echo "Lo sentimos, hubo un problema de conexión o el ID '$id' no existe en la categoría '$type'."
                exit 1 
            fi
            
            # Guardar exitosamente en el caché
            cp "$TEMP_FILE" "$cache_file"
        fi
        
        # Parseo de JSON y salida por pantalla
        if [[ "$type" == "people" ]]; then
            local name=$(jq -r '.result.properties.name // empty' "$TEMP_FILE")
            if [[ -z "$name" ]]; then
                echo "Lo sentimos, la API no devolvió información válida para el personaje $id."
                exit 1
            fi
            
            echo "Id: $id"
            echo "Name: $name"
            echo "Gender: $(jq -r '.result.properties.gender' "$TEMP_FILE")"
            echo "Height: $(jq -r '.result.properties.height' "$TEMP_FILE")"
            echo "Mass: $(jq -r '.result.properties.mass' "$TEMP_FILE")"
            echo "Birth Year: $(jq -r '.result.properties.birth_year' "$TEMP_FILE")"
            echo ""
            
        elif [[ "$type" == "films" ]]; then
            local title=$(jq -r '.result.properties.title // empty' "$TEMP_FILE")
            if [[ -z "$title" ]]; then
                echo "Lo sentimos, la API no devolvió información válida para la película $id."
                exit 1
            fi
            
            # Limpiamos los saltos de línea del opening crawl para que se vea como en el ejemplo
            local crawl=$(jq -r '.result.properties.opening_crawl' "$TEMP_FILE" | tr '\n' ' ' | tr '\r' ' ' | cut -c 1-40)
            
            echo "Title: $title"
            echo "Episode id: $(jq -r '.result.properties.episode_id' "$TEMP_FILE")"
            echo "Release date: $(jq -r '.result.properties.release_date' "$TEMP_FILE")"
            echo "Opening crawl: $crawl..."
            echo ""
        fi
    done
}

if [[ -n "$PEOPLE" ]]; then
    echo "Personajes:"
    fetch_and_show "people" "$PEOPLE"
fi

if [[ -n "$FILMS" ]]; then
    echo "Películas:"
    fetch_and_show "films" "$FILMS"
fi