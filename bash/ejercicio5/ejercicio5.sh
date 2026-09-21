#!/usr/bin/env bash

# GRUPO 5
# INTREGRANTES:
#   ARAGON, RODRIGO EZEQUIEL
#   ORFANO, NICOLAS
#   VALENTE, MARTIN 

# Ejercicio 5 - Consulta a la API de Star Wars con cache local.

# Se usa set -u para detectar variables no inicializadas.
set -u

# Muestra ayuda del script.
mostrar_ayuda() {
    cat <<'AYUDA'
Uso:
  ./ejercicio5.sh -p "1,2" -f "1,2"
  ./ejercicio5.sh --people "1,2" --film "1,2"

Parametros:
  -p, --people   Id o ids de personajes separados por coma.
  -f, --film     Id o ids de peliculas separados por coma.
  -h, --help     Muestra esta ayuda.

Notas:
  La primera consulta se descarga desde https://www.swapi.tech.
  Luego se guarda en la carpeta cache para reutilizarla.
AYUDA
}

# Imprime un error y termina.
error() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

# Valida que un id sea entero positivo.
es_id_valido() {
    local id="$1"
    [[ "$id" =~ ^[0-9]+$ ]] && [ "$id" -gt 0 ]
}

# Extrae un campo simple de un archivo JSON sin usar herramientas avanzadas.
obtener_campo_texto() {
    local clave="$1"
    local archivo="$2"

    # Se pasa el JSON a una sola linea y se busca "clave": "valor".
    tr '\n' ' ' < "$archivo" | sed -n "s/.*\"$clave\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# Extrae un campo numerico de un archivo JSON.
obtener_campo_numero() {
    local clave="$1"
    local archivo="$2"

    # Se busca "clave": numero y se quitan comillas si existieran.
    tr '\n' ' ' < "$archivo" | sed -n "s/.*\"$clave\"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p" | tr -d '"'
}

# Descarga un recurso si no esta en cache.
asegurar_cache() {
    local tipo="$1"
    local id="$2"
    local endpoint="$3"
    local archivo="$cache_dir/${tipo}_${id}.json"
    local temporal="$archivo.tmp.$$"

    # Si el archivo ya existe y tiene contenido, se reutiliza.
    if [ -s "$archivo" ]; then
        printf '%s' "$archivo"
        return 0
    fi

    # Se descarga desde la API.
    if ! curl -fsSL "https://www.swapi.tech/api/$endpoint/$id" -o "$temporal"; then
        rm -f "$temporal"
        printf 'No se pudo obtener %s con id %s desde la API.\n' "$tipo" "$id" >&2
        return 1
    fi

    # Se valida que la respuesta tenga result, que es la seccion esperada.
    if ! grep -q '"result"' "$temporal"; then
        rm -f "$temporal"
        printf 'La API no devolvio datos validos para %s con id %s.\n' "$tipo" "$id" >&2
        return 1
    fi

    mv "$temporal" "$archivo"
    printf '%s' "$archivo"
}

# Imprime datos basicos de un personaje.
mostrar_personaje() {
    local id="$1"
    local archivo

    archivo=$(asegurar_cache 'people' "$id" 'people') || return 0

    printf 'Personajes:\n'
    printf 'Id: %s\n' "$id"
    printf 'Name: %s\n' "$(obtener_campo_texto 'name' "$archivo")"
    printf 'Gender: %s\n' "$(obtener_campo_texto 'gender' "$archivo")"
    printf 'Height: %s\n' "$(obtener_campo_texto 'height' "$archivo")"
    printf 'Mass: %s\n' "$(obtener_campo_texto 'mass' "$archivo")"
    printf 'Birth Year: %s\n' "$(obtener_campo_texto 'birth_year' "$archivo")"
    printf '\n'
}

# Imprime datos basicos de una pelicula.
mostrar_pelicula() {
    local id="$1"
    local archivo opening

    archivo=$(asegurar_cache 'film' "$id" 'films') || return 0
    opening=$(obtener_campo_texto 'opening_crawl' "$archivo")

    # Se reemplazan saltos escapados para que se vea en una sola linea.
    opening=$(printf '%s' "$opening" | sed 's/\\r\\n/ /g; s/\\n/ /g')

    printf 'Peliculas:\n'
    printf 'Title: %s\n' "$(obtener_campo_texto 'title' "$archivo")"
    printf 'Episode id: %s\n' "$(obtener_campo_numero 'episode_id' "$archivo" | tr -d ' ')"
    printf 'Release date: %s\n' "$(obtener_campo_texto 'release_date' "$archivo")"
    printf 'Opening crawl: %s\n' "$opening"
    printf '\n'
}

# Variables para parametros.
people=''
film=''

# Lectura de parametros en cualquier orden.
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        -p|--people)
            shift
            [ "$#" -gt 0 ] || error 'Falta indicar ids de personajes.'
            people="$1"
            ;;
        -f|--film)
            shift
            [ "$#" -gt 0 ] || error 'Falta indicar ids de peliculas.'
            film="$1"
            ;;
        *)
            error "Parametro no reconocido: $1"
            ;;
    esac
    shift
done

# Se valida que se haya pedido al menos una busqueda.
if [ -z "$people" ] && [ -z "$film" ]; then
    error 'Debe indicar -p/--people o -f/--film.'
fi

# Se valida que curl este disponible para consultar la API.
command -v curl >/dev/null 2>&1 || error 'No se encontro curl para consultar la API.'

# Se obtiene la carpeta donde esta el script para crear ahi el cache.
script_dir=$(cd "$(dirname "$0")" && pwd -P)
cache_dir="$script_dir/cache"
mkdir -p "$cache_dir" || error 'No se pudo crear la carpeta cache.'

# Si el script termina, se limpian descargas temporales.
trap 'rm -f "$cache_dir"/*.tmp.$$ 2>/dev/null' EXIT

# Se procesan personajes si fueron pedidos.
if [ -n "$people" ]; then
    IFS=',' read -r -a ids_personas <<< "$people"

    for id in "${ids_personas[@]}"; do
        es_id_valido "$id" || error "Id de personaje invalido: $id"
        mostrar_personaje "$id"
    done
fi

# Se procesan peliculas si fueron pedidas.
if [ -n "$film" ]; then
    IFS=',' read -r -a ids_peliculas <<< "$film"

    for id in "${ids_peliculas[@]}"; do
        es_id_valido "$id" || error "Id de pelicula invalido: $id"
        mostrar_pelicula "$id"
    done
fi
