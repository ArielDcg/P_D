#!/bin/bash
################################################################################
# Script para limpiar archivos generados por la simulación
################################################################################

echo "Limpiando archivos de simulación..."

# Eliminar archivos generados
rm -f i2c_lm75_sim
rm -f i2c_lm75_tb.vcd
rm -f *.vcd
rm -f *.out

echo "Archivos de simulación eliminados."
