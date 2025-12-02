#!/bin/bash
################################################################################
# Script de simulación para testbench I2C LM75
# Uso: ./run_sim.sh
################################################################################

echo "=========================================="
echo "Compilando testbench I2C LM75..."
echo "=========================================="

# Compilar con iverilog (Icarus Verilog)
iverilog -o i2c_lm75_sim \
    i2c_lm75_tb.v

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "Compilación exitosa!"
    echo "Ejecutando simulación..."
    echo "=========================================="
    echo ""

    # Ejecutar simulación
    vvp i2c_lm75_sim

    if [ $? -eq 0 ]; then
        echo ""
        echo "=========================================="
        echo "Simulación completada!"
        echo "=========================================="
        echo ""

        # Verificar si se generó el archivo VCD
        if [ -f "i2c_lm75_tb.vcd" ]; then
            echo "Archivo de formas de onda generado: i2c_lm75_tb.vcd"
            echo "Para visualizar las formas de onda, ejecuta:"
            echo "  gtkwave i2c_lm75_tb.vcd"
            echo ""
        fi
    else
        echo "Error durante la ejecución de la simulación"
        exit 1
    fi
else
    echo "Error durante la compilación"
    exit 1
fi

echo "Para limpiar archivos generados, ejecuta:"
echo "  ./clean_sim.sh"
echo ""
