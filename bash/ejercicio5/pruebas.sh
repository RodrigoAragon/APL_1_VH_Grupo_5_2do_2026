#!/bin/bash

SCRIPT="./ejercicio5.sh"
CACHE_DIR="/tmp/ejercicio5_cache"
TEMP_DIR="/tmp"

# Colores para la salida
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================"
echo "Iniciando Pruebas de Integración (Bash)"
echo "========================================"

# Limpiar caché previa para asegurar pruebas limpias
rm -rf "$CACHE_DIR"

# Función de ayuda para validar resultados
assert_exit_code() {
    local expected=$1
    local actual=$2
    local test_name=$3
    if [ "$expected" -eq "$actual" ]; then
        echo -e "${GREEN}PASÓ:${NC} $test_name"
    else
        echo -e "${RED}FALLÓ:${NC} $test_name (Esperado: $expected, Obtenido: $actual)"
    fi
}

# Prueba 1: Sin parámetros (Debe fallar con exit 1)
$SCRIPT > /dev/null 2>&1
assert_exit_code 1 $? "Fallo controlado sin parámetros obligatorios"

# Prueba 2: Ayuda (Debe salir con exit 0)
$SCRIPT -h > /dev/null 2>&1
assert_exit_code 0 $? "Ejecución del menú de ayuda (-h)"

# Prueba 3: Personaje válido único
$SCRIPT -p 1 > /dev/null 2>&1
assert_exit_code 0 $? "Búsqueda de personaje válido (Luke Skywalker)"

# Prueba 4: Verificación de Caché
if [ -f "$CACHE_DIR/people_1.json" ]; then
    echo -e "${GREEN}PASÓ:${NC} Creación de archivo caché en $CACHE_DIR"
else
    echo -e "${RED}FALLÓ:${NC} No se creó el archivo de caché para people_1"
fi

# Prueba 5: Múltiples películas y orden invertido de parámetros
$SCRIPT --film "1,2" --people "4" > /dev/null 2>&1
assert_exit_code 0 $? "Búsqueda múltiple y parámetros en cualquier orden"

# Prueba 6: ID Inválido (Debe fallar con exit 1 y no romper el script feamente)
$SCRIPT -p 99999 > /dev/null 2>&1
assert_exit_code 1 $? "Fallo controlado ante un ID inexistente en la API"

# Prueba 7: Limpieza de archivos temporales
# Verificamos que no queden archivos temporales swapi_temp_* del script actual
TEMP_FILES=$(ls $TEMP_DIR/swapi_temp_*.json 2>/dev/null | wc -l)
if [ "$TEMP_FILES" -eq 0 ]; then
    echo -e "${GREEN}PASÓ:${NC} Limpieza exitosa de archivos temporales (trap funcionó)"
else
    echo -e "${RED}FALLÓ:${NC} Quedaron archivos temporales basura en $TEMP_DIR"
fi

echo "========================================"
echo "Pruebas de Bash Finalizadas"
echo "========================================"